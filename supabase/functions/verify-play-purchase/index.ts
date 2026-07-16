import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  create as jwtCreate,
  getNumericDate,
} from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import {
  ANDROID_PACKAGE_NAME,
  getProductEntitlement,
  validateInAppPurchaseState,
  validateSubscriptionPurchaseState,
} from "./entitlements.mjs";
import { assertGooglePlayPackageAccess } from "./publisherAccess.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ||
  "https://afwznqjpshybmqhlewmy.supabase.co";
const ANDROID_PUBLISHER_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

type VerifyBody = {
  action?: "preflight";
  product_id?: string;
  purchase_token?: string;
  package_name?: string;
  purchase_type?: "subscription" | "inapp";
};

type GoogleServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!serviceKey || !anonKey) {
      return json({ error: "missing_supabase_env" }, 500);
    }

    const accessToken = (req.headers.get("Authorization") || "").replace(
      /^Bearer\s+/i,
      "",
    ).trim();
    if (!accessToken) return json({ error: "missing_token" }, 401);

    const body = await req.json() as VerifyBody;
    const authClient = createClient(SUPABASE_URL, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await authClient.auth.getUser(
      accessToken,
    );
    if (userError || !userData.user) {
      return json({ error: "invalid_user" }, 401);
    }

    if (body.action === "preflight") {
      try {
        const googleAccessToken = await googlePlayAccessToken();
        await assertGooglePlayPackageAccess(
          ANDROID_PACKAGE_NAME,
          googleAccessToken,
        );
        return json({ ok: true, ready: true });
      } catch (error) {
        console.error("[verify-play-purchase] readiness failed", error);
        return json({
          ok: false,
          ready: false,
          error: "play_payments_unavailable",
        }, 503);
      }
    }

    const productId = body.product_id?.trim() || "";
    const purchaseToken = body.purchase_token?.trim() || "";
    const packageName = body.package_name?.trim() || ANDROID_PACKAGE_NAME;
    const requestedPurchaseType = body.purchase_type;
    if (!productId || !purchaseToken) {
      return json({ error: "missing_purchase_fields" }, 400);
    }
    if (packageName !== ANDROID_PACKAGE_NAME) {
      return json({ error: "invalid_package" }, 400);
    }

    const entitlement = getProductEntitlement(productId);
    if (!entitlement) return json({ error: "unknown_product" }, 400);
    if (
      requestedPurchaseType &&
      requestedPurchaseType !== entitlement.purchaseType
    ) {
      return json({ error: "purchase_type_mismatch" }, 400);
    }

    const googleAccessToken = await googlePlayAccessToken();
    const purchase = entitlement.purchaseType === "subscription"
      ? await loadGoogleSubscription(
        packageName,
        purchaseToken,
        googleAccessToken,
      )
      : await loadGoogleProduct(
        packageName,
        productId,
        purchaseToken,
        googleAccessToken,
      );
    const verified = entitlement.purchaseType === "subscription"
      ? extractSubscriptionEntitlement(productId, purchase)
      : extractInAppEntitlement(purchase);
    if (!verified.ok) return json({ error: verified.error }, verified.status);

    const admin = createClient(SUPABASE_URL, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const userId = userData.user.id;
    const tokenHash = await sha256(purchaseToken);
    const expiry = verified.expiry;
    const claimKey = `${productId}:${tokenHash}:${expiry || "one-time"}`;

    const { data: applyResult, error: applyError } = await admin
      .rpc("apply_android_purchase_entitlement", {
        p_user_id: userId,
        p_claim_key: claimKey,
        p_product_id: productId,
        p_purchase_type: entitlement.purchaseType,
        p_purchase_token_hash: tokenHash,
        p_order_id: verified.orderId || null,
        p_expires_at: expiry || null,
        p_credits: entitlement.credits,
        p_subscription_type: entitlement.subscriptionType || null,
        p_profile_plan: entitlement.profilePlan || null,
        p_verified: entitlement.verified,
      });
    if (applyError) {
      if (applyError.message?.includes("owned_by_other")) {
        return json({ error: "owned_by_other" }, 409);
      }
      return json({
        error: "entitlement_apply_failed",
        message: applyError.message,
      }, 500);
    }

    return json({
      ok: true,
      product_id: productId,
      entitlement,
      already_claimed: applyResult?.already_claimed === true,
      credits_granted: applyResult?.credits_granted || 0,
      profile: applyResult?.profile || null,
    });
  } catch (error) {
    console.error("[verify-play-purchase] verification failed", error);
    return json({ error: "verify_exception" }, 500);
  }
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function extractSubscriptionEntitlement(
  requestedProductId: string,
  purchase: unknown,
): { ok: true; expiry: string; orderId?: string } | {
  ok: false;
  status: number;
  error: string;
} {
  const stateValidation = validateSubscriptionPurchaseState(purchase);
  if (!stateValidation.ok) {
    const failure = stateValidation as {
      ok: false;
      status: number;
      error: string;
    };
    return failure;
  }
  const typedPurchase = purchase as {
    lineItems?: Array<{ productId?: string; expiryTime?: string }>;
    latestOrderId?: string;
  };
  const lineItems = Array.isArray(typedPurchase.lineItems)
    ? typedPurchase.lineItems
    : [];
  const matching =
    lineItems.find((item) => item?.productId === requestedProductId) ||
    lineItems[0];
  if (!matching?.expiryTime) {
    return { ok: false, status: 402, error: "purchase_not_active" };
  }
  if (matching.productId && matching.productId !== requestedProductId) {
    return { ok: false, status: 400, error: "product_mismatch" };
  }
  if (Date.parse(matching.expiryTime) <= Date.now()) {
    return { ok: false, status: 402, error: "purchase_expired" };
  }
  return {
    ok: true,
    expiry: matching.expiryTime,
    orderId: typedPurchase.latestOrderId,
  };
}

function extractInAppEntitlement(
  purchase: unknown,
): { ok: true; expiry: null; orderId?: string } | {
  ok: false;
  status: number;
  error: string;
} {
  const state = validateInAppPurchaseState(purchase);
  if (!state.ok) {
    const failure = state as { ok: false; status: number; error: string };
    return failure;
  }
  const typedPurchase = purchase as { orderId?: string };
  return { ok: true, expiry: null, orderId: typedPurchase.orderId };
}

async function loadGoogleSubscription(
  packageName: string,
  purchaseToken: string,
  accessToken: string,
): Promise<unknown> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
      encodeURIComponent(packageName)
    }/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(
      `Google Play subscription error ${response.status}: ${text}`,
    );
  }
  return JSON.parse(text);
}

async function loadGoogleProduct(
  packageName: string,
  productId: string,
  purchaseToken: string,
  accessToken: string,
): Promise<unknown> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
      encodeURIComponent(packageName)
    }/purchases/products/${encodeURIComponent(productId)}/tokens/${
      encodeURIComponent(purchaseToken)
    }`;
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Google Play product error ${response.status}: ${text}`);
  }
  return JSON.parse(text);
}

async function googlePlayAccessToken(): Promise<string> {
  const raw = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  if (!raw) throw new Error("missing GOOGLE_PLAY_SERVICE_ACCOUNT_JSON");
  const account = JSON.parse(raw) as GoogleServiceAccount;
  const tokenUri = account.token_uri || "https://oauth2.googleapis.com/token";
  const assertion = await serviceAccountJwt(account, tokenUri);
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(
      `Google token error ${response.status}: ${JSON.stringify(data)}`,
    );
  }
  return data.access_token as string;
}

async function serviceAccountJwt(
  account: GoogleServiceAccount,
  audience: string,
): Promise<string> {
  const key = await importRS256(account.private_key);
  return await jwtCreate(
    { alg: "RS256", typ: "JWT" },
    {
      iss: account.client_email,
      scope: ANDROID_PUBLISHER_SCOPE,
      aud: audience,
      iat: getNumericDate(0),
      exp: getNumericDate(3600),
    },
    key,
  );
}

async function importRS256(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(hash)).map((b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
}
