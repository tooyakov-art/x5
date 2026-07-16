import { Buffer } from "node:buffer";
import {
  Environment,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";
import { createClient } from "@supabase/supabase-js";
import {
  APP_BUNDLE_ID,
  AppStoreEnvironment,
  InputError,
  parseAppAppleId,
  parseAppleRootCertificates,
  parseNotificationRequestBody,
  parseUntrustedNotificationEnvironment,
  RefundNotificationEvent,
  validateVerifiedRefundNotification,
} from "./validation.ts";

export interface NotificationApplyResult {
  status: "applied" | "already_applied" | "ignored_stale";
}

export interface NotificationHandlerDependencies {
  now(): number;
  verifyNotification(
    signedPayload: string,
    environment: AppStoreEnvironment,
  ): Promise<unknown>;
  verifyTransaction(
    signedTransaction: string,
    environment: AppStoreEnvironment,
  ): Promise<unknown>;
  applyNotification(
    event: RefundNotificationEvent,
  ): Promise<NotificationApplyResult>;
  logError(error: unknown): void;
}

export class AppleVerificationError extends Error {
  constructor(readonly retryable: boolean) {
    super("apple_verification_failed");
  }
}

export class NotificationApplyError extends Error {
  constructor(readonly code: string, readonly httpStatus: number) {
    super(code);
  }
}

export function createHandler(
  _dependencies: NotificationHandlerDependencies,
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
      if (
        !request.headers.get("Content-Type")?.toLowerCase().startsWith(
          "application/json",
        )
      ) {
        throw new InputError("invalid_content_type", 415);
      }

      const rawBody = await readJSONBody(request);
      const signedPayload = parseNotificationRequestBody(rawBody);

      // The unsigned data is used only to choose one of two verifier instances.
      // Bundle, environment, event type and transaction identity remain untrusted
      // until the corresponding Apple JWS verification succeeds below.
      const environment = parseUntrustedNotificationEnvironment(signedPayload);
      const notification = await _dependencies.verifyNotification(
        signedPayload,
        environment,
      );

      if (!isRecord(notification)) {
        throw new InputError("invalid_notification_payload");
      }
      if (
        notification.notificationType !== "REFUND" &&
        notification.notificationType !== "REFUND_REVERSED"
      ) {
        return jsonResponse({ status: "ignored" }, 200);
      }
      if (!isRecord(notification.data)) {
        throw new InputError("invalid_notification_payload");
      }
      const signedTransaction = notification.data.signedTransactionInfo;
      if (
        typeof signedTransaction !== "string" ||
        !signedTransaction.trim() ||
        signedTransaction.length > 128 * 1024
      ) {
        throw new InputError("missing_signed_transaction_info");
      }

      const transaction = await _dependencies.verifyTransaction(
        signedTransaction,
        environment,
      );
      const event = validateVerifiedRefundNotification(
        notification,
        transaction,
        environment,
        _dependencies.now(),
      );
      const result = await _dependencies.applyNotification(event);
      return jsonResponse({ status: result.status }, 200);
    } catch (error) {
      if (error instanceof InputError) {
        if (error.status === 200) {
          return jsonResponse(
            { status: "ignored", reason: error.code },
            200,
          );
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
            error: "invalid_apple_signature",
          }, 400);
      }
      if (error instanceof NotificationApplyError) {
        return jsonResponse(
          { status: "rejected", error: error.code },
          error.httpStatus,
        );
      }
      _dependencies.logError(error);
      return jsonResponse({ status: "rejected", error: "server_error" }, 500);
    }
  };
}

const MAX_BODY_BYTES = 132 * 1024;

async function readJSONBody(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("Content-Length");
  if (declaredLength !== null) {
    const parsed = Number(declaredLength);
    if (Number.isFinite(parsed) && parsed > MAX_BODY_BYTES) {
      throw new InputError("request_too_large", 413);
    }
  }

  const reader = request.body?.getReader();
  if (!reader) throw new InputError("invalid_request_body");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new InputError("request_too_large", 413);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const body = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(body));
  } catch {
    throw new InputError("invalid_request_body");
  }
}

function jsonResponse(
  body: Record<string, unknown>,
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

let appleRootCertificates: Buffer[] | undefined;
const appleVerifiers = new Map<AppStoreEnvironment, SignedDataVerifier>();

function getAppleRootCertificates(): Buffer[] {
  if (appleRootCertificates) return appleRootCertificates;
  appleRootCertificates = parseAppleRootCertificates(
    Deno.env.get("APPLE_ROOT_CA_CERTS_PEM"),
    Deno.env.get("APPLE_ROOT_CA_CERTS_BASE64"),
  ).map((certificate) => Buffer.from(certificate));
  return appleRootCertificates;
}

function getAppleVerifier(
  environment: AppStoreEnvironment,
): SignedDataVerifier {
  const cached = appleVerifiers.get(environment);
  if (cached) return cached;
  const verifier = new SignedDataVerifier(
    getAppleRootCertificates(),
    true,
    environment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX,
    APP_BUNDLE_ID,
    environment === "Production"
      ? parseAppAppleId(Deno.env.get("APPLE_APP_ID"))
      : undefined,
  );
  appleVerifiers.set(environment, verifier);
  return verifier;
}

function appleVerificationError(error: unknown): AppleVerificationError {
  return new AppleVerificationError(
    error instanceof VerificationException &&
      error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE,
  );
}

async function verifyNotification(
  signedPayload: string,
  environment: AppStoreEnvironment,
): Promise<ResponseBodyV2DecodedPayload> {
  try {
    return await getAppleVerifier(environment).verifyAndDecodeNotification(
      signedPayload,
    );
  } catch (error) {
    throw appleVerificationError(error);
  }
}

async function verifyTransaction(
  signedTransaction: string,
  environment: AppStoreEnvironment,
): Promise<JWSTransactionDecodedPayload> {
  try {
    return await getAppleVerifier(environment).verifyAndDecodeTransaction(
      signedTransaction,
    );
  } catch (error) {
    throw appleVerificationError(error);
  }
}

async function applyNotification(
  event: RefundNotificationEvent,
): Promise<NotificationApplyResult> {
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
    "apply_verified_app_store_server_notification",
    {
      p_event_id: event.eventId,
      p_notification_type: event.notificationType,
      p_notification_signed_date: event.notificationSignedDate,
      p_user_id: event.userId,
      p_transaction_id: event.transactionId,
      p_original_transaction_id: event.originalTransactionId,
      p_product_id: event.productId,
      p_environment: event.environment,
      p_app_account_token: event.appAccountToken,
      p_purchase_date: event.purchaseDate,
      p_expires_date: event.expiresDate,
      p_transaction_signed_date: event.transactionSignedDate,
      p_revocation_date: event.revocationDate,
      p_revocation_percentage: event.revocationPercentage,
      p_quantity: event.quantity,
    },
  );
  if (error) {
    const token = `${error.code ?? ""} ${error.message ?? ""} ${
      error.details ?? ""
    } ${error.hint ?? ""}`.toLowerCase();
    if (
      token.includes("owned_by_other") ||
      token.includes("notification_event_id_conflict") ||
      token.includes("notification_source_mismatch")
    ) {
      throw new NotificationApplyError("conflict", 409);
    }
    if (
      token.includes("invalid_") || token.includes("unknown_product") ||
      token.includes("missing_") || token.includes("profile_not_found")
    ) {
      throw new NotificationApplyError("invalid_notification", 400);
    }
    throw new Error("apply_app_store_notification_failed");
  }
  if (!isNotificationApplyResult(data)) {
    throw new Error("invalid_notification_rpc_response");
  }
  return data;
}

function isNotificationApplyResult(
  value: unknown,
): value is NotificationApplyResult {
  return isRecord(value) &&
    (value.status === "applied" || value.status === "already_applied" ||
      value.status === "ignored_stale");
}

function requiredEnvironmentVariable(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new InputError(`missing_${name.toLowerCase()}`, 500);
  return value;
}

const runtimeDependencies: NotificationHandlerDependencies = {
  now: () => Date.now(),
  verifyNotification,
  verifyTransaction,
  applyNotification,
  logError: (error) => {
    const name = error instanceof Error ? error.name : typeof error;
    console.error("app-store-notifications failed", { name });
  },
};

if (import.meta.main) {
  Deno.serve(createHandler(runtimeDependencies));
}
