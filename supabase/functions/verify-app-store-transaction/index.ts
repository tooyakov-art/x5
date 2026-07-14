import { Buffer } from "node:buffer";
import {
  Environment,
  type JWSTransactionDecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import { createClient } from "@supabase/supabase-js";
import {
  APP_BUNDLE_ID,
  type AppStoreEnvironment,
  InputError,
  type NormalizedTransaction,
  parseAppAppleId,
  parseAppleRootCertificates,
  parseUntrustedTransactionEnvironment,
  parseVerifyRequestBody,
  validateVerifiedTransaction,
  type VerifiedTransactionPayload,
} from "./validation.ts";

export interface EntitlementResult {
  status: "applied" | "already_applied";
  credits_granted: number;
  subscription_end_date: string | null;
  is_verified: boolean;
}

export interface HandlerDependencies {
  now(): number;
  authenticate(accessToken: string): Promise<string | null>;
  verifySignedTransaction(
    signedTransaction: string,
    environment: AppStoreEnvironment,
  ): Promise<VerifiedTransactionPayload>;
  applyVerifiedTransaction(
    userId: string,
    transaction: NormalizedTransaction,
  ): Promise<EntitlementResult>;
  logError(error: unknown): void;
}

export class AppleVerificationError extends Error {
  constructor(readonly retryable: boolean) {
    super("apple_verification_failed");
  }
}

export class EntitlementApplyError extends Error {
  constructor(
    readonly statusValue: "owned_by_other" | "rejected",
    readonly httpStatus: number,
  ) {
    super(statusValue);
  }
}

export function createHandler(
  _dependencies: HandlerDependencies,
): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") {
      return jsonResponse(
        { status: "rejected", error: "method_not_allowed" },
        405,
        { Allow: "POST" },
      );
    }

    try {
      const accessToken = bearerToken(request.headers.get("Authorization"));
      if (!accessToken) {
        return jsonResponse({ status: "rejected", error: "unauthorized" }, 401);
      }

      const userId = await _dependencies.authenticate(accessToken);
      if (!userId) {
        return jsonResponse({ status: "rejected", error: "unauthorized" }, 401);
      }

      if (
        !request.headers.get("Content-Type")?.toLowerCase().startsWith(
          "application/json",
        )
      ) {
        throw new InputError("invalid_content_type", 415);
      }

      let rawBody: unknown;
      try {
        rawBody = await request.json();
      } catch {
        throw new InputError("invalid_request_body");
      }

      const signedTransaction = parseVerifyRequestBody(rawBody);
      const environment = parseUntrustedTransactionEnvironment(
        signedTransaction,
      );
      const verifiedPayload = await _dependencies.verifySignedTransaction(
        signedTransaction,
        environment,
      );
      const transaction = validateVerifiedTransaction(
        verifiedPayload,
        userId,
        environment,
        _dependencies.now(),
      );
      // This function is deployed against the production credit ledger.
      // Sandbox/TestFlight purchases are free and must never mint spendable
      // production credits. Use a separate staging Supabase project for IAP
      // tests instead of adding a production allowlist here.
      if (transaction.environment !== "Production") {
        throw new InputError("sandbox_not_allowed", 403);
      }
      const result = await _dependencies.applyVerifiedTransaction(
        userId,
        transaction,
      );
      return jsonResponse(result, 200);
    } catch (error) {
      if (error instanceof InputError) {
        if (error.code === "transaction_owned_by_other") {
          return jsonResponse({ status: "owned_by_other" }, 409);
        }
        return jsonResponse(
          { status: "rejected", error: error.code },
          error.status,
        );
      }
      if (error instanceof AppleVerificationError) {
        return error.retryable
          ? jsonResponse({
            status: "rejected",
            error: "apple_verification_unavailable",
          }, 503)
          : jsonResponse({
            status: "rejected",
            error: "invalid_apple_transaction",
          }, 400);
      }
      if (error instanceof EntitlementApplyError) {
        return jsonResponse({ status: error.statusValue }, error.httpStatus);
      }
      _dependencies.logError(error);
      return jsonResponse({ status: "rejected", error: "server_error" }, 500);
    }
  };
}

function bearerToken(authorization: string | null): string | null {
  const match = authorization?.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1] ?? null;
}

function jsonResponse(
  body: Record<string, unknown> | EntitlementResult,
  status: number,
  headers: HeadersInit = {},
): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      ...Object.fromEntries(new Headers(headers).entries()),
    },
  });
}

let appleRootCertificates: Buffer[] | undefined;
const appleVerifiers = new Map<AppStoreEnvironment, SignedDataVerifier>();

// Deployment configuration:
// - APPLE_APP_ID: numeric App Store app id (required for Production JWS).
// - APPLE_ROOT_CA_CERTS_PEM: preferred PEM bundle of the current roots from
//   https://www.apple.com/certificateauthority/.
// - APPLE_ROOT_CA_CERTS_BASE64: fallback JSON array of base64 DER roots.
// Root certificates are public material, but Supabase secrets keep deployment
// configuration out of the app binary and allow rotation without a release.
function getAppleRootCertificates(): Buffer[] {
  if (appleRootCertificates) return appleRootCertificates;
  const certificates = parseAppleRootCertificates(
    Deno.env.get("APPLE_ROOT_CA_CERTS_PEM"),
    Deno.env.get("APPLE_ROOT_CA_CERTS_BASE64"),
  );
  appleRootCertificates = certificates.map((certificate) =>
    Buffer.from(certificate)
  );
  return appleRootCertificates;
}

function getAppleVerifier(
  environment: AppStoreEnvironment,
): SignedDataVerifier {
  const cached = appleVerifiers.get(environment);
  if (cached) return cached;

  const verifierEnvironment = environment === "Production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
  const appAppleId = environment === "Production"
    ? parseAppAppleId(Deno.env.get("APPLE_APP_ID"))
    : undefined;

  let verifier: SignedDataVerifier;
  try {
    verifier = new SignedDataVerifier(
      getAppleRootCertificates(),
      true,
      verifierEnvironment,
      APP_BUNDLE_ID,
      appAppleId,
    );
  } catch {
    throw new InputError("invalid_apple_verifier_configuration", 500);
  }
  appleVerifiers.set(environment, verifier);
  return verifier;
}

async function verifySignedTransaction(
  signedTransaction: string,
  environment: AppStoreEnvironment,
): Promise<JWSTransactionDecodedPayload> {
  const verifier = getAppleVerifier(environment);
  try {
    return await verifier.verifyAndDecodeTransaction(signedTransaction);
  } catch (error) {
    const retryable = error instanceof VerificationException &&
      error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE;
    throw new AppleVerificationError(retryable);
  }
}

function publicSupabaseKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    requiredEnvironmentVariable("SUPABASE_ANON_KEY");
}

async function authenticate(accessToken: string): Promise<string | null> {
  const client = createClient(
    requiredEnvironmentVariable("SUPABASE_URL"),
    publicSupabaseKey(),
    {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );
  const { data, error } = await client.auth.getUser(accessToken);
  if (error || !data.user) return null;
  return data.user.id;
}

async function applyVerifiedTransaction(
  userId: string,
  transaction: NormalizedTransaction,
): Promise<EntitlementResult> {
  const admin = createClient(
    requiredEnvironmentVariable("SUPABASE_URL"),
    requiredEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    },
  );

  const { data, error } = await admin.rpc(
    "apply_verified_app_store_transaction",
    {
      p_user_id: userId,
      p_transaction_id: transaction.transactionId,
      p_original_transaction_id: transaction.originalTransactionId,
      p_product_id: transaction.productId,
      p_environment: transaction.environment,
      p_app_account_token: transaction.appAccountToken,
      p_purchase_date: transaction.purchaseDate,
      p_expires_date: transaction.expiresDate,
      p_signed_date: transaction.signedDate,
      p_revocation_date: transaction.revocationDate,
    },
  );

  if (error) {
    const safeToken = `${error.code ?? ""} ${error.message ?? ""} ${
      error.details ?? ""
    } ${error.hint ?? ""}`
      .toLowerCase();
    if (
      safeToken.includes("owned_by_other") ||
      safeToken.includes("transaction_id_conflict")
    ) {
      throw new EntitlementApplyError("owned_by_other", 409);
    }
    if (
      safeToken.includes("invalid_user_id") ||
      safeToken.includes("profile_not_found") ||
      safeToken.includes("invalid_transaction_id") ||
      safeToken.includes("invalid_environment") ||
      safeToken.includes("unknown_product") ||
      safeToken.includes("transaction_revoked") ||
      safeToken.includes("missing_transaction_dates") ||
      safeToken.includes("invalid_expiration_date") ||
      safeToken.includes("transaction_expired") ||
      safeToken.includes("invalid_transaction_dates") ||
      safeToken.includes("account_token_mismatch") ||
      safeToken.includes("missing_account_token")
    ) {
      throw new EntitlementApplyError("rejected", 400);
    }
    throw new Error("apply_verified_app_store_transaction_failed");
  }

  if (!isEntitlementResult(data)) {
    throw new Error("invalid_entitlement_rpc_response");
  }
  return data;
}

function isEntitlementResult(value: unknown): value is EntitlementResult {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return false;
  }
  const result = value as Record<string, unknown>;
  return (result.status === "applied" || result.status === "already_applied") &&
    typeof result.credits_granted === "number" &&
    Number.isSafeInteger(result.credits_granted) &&
    result.credits_granted >= 0 &&
    (typeof result.subscription_end_date === "string" ||
      result.subscription_end_date === null) &&
    typeof result.is_verified === "boolean";
}

function requiredEnvironmentVariable(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new InputError(`missing_${name.toLowerCase()}`, 500);
  return value;
}

const runtimeDependencies: HandlerDependencies = {
  now: () => Date.now(),
  authenticate,
  verifySignedTransaction,
  applyVerifiedTransaction,
  logError: (error) => {
    const name = error instanceof Error ? error.name : typeof error;
    console.error("verify-app-store-transaction failed", { name });
  },
};

if (import.meta.main) {
  Deno.serve(createHandler(runtimeDependencies));
}
