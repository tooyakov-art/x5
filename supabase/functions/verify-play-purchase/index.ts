import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  create as jwtCreate,
  getNumericDate,
} from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ||
  "https://afwznqjpshybmqhlewmy.supabase.co";
const ANDROID_PUBLISHER_SCOPE =
  "https://www.googleapis.com/auth/androidpublisher";
const DEFAULT_PACKAGE_NAME = "com.x5studio.app";
// No production Google Play purchase has been observed, while the retired
// implementation has no global token owner or renewal ledger. Keep it closed
// until those server-side exact-once guarantees are implemented and tested.
const PLAY_PURCHASES_ENABLED = false;

interface VerifyBody {
  product_id?: string;
  purchase_token?: string;
  package_name?: string;
}

interface GoogleServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface PlanEntitlement {
  profilePlan: string;
  subscriptionType: string;
  credits: number;
}

const planEntitlements: Record<string, PlanEntitlement> = {
  "com.x5studio.app.lite.monthly": {
    profilePlan: "lite",
    subscriptionType: "lite_monthly",
    credits: 1000,
  },
  "com.x5studio.app.pro.monthly": {
    profilePlan: "pro",
    subscriptionType: "pro_monthly",
    credits: 2000,
  },
  "com.x5studio.app.max.monthly": {
    profilePlan: "max",
    subscriptionType: "max_monthly",
    credits: 5000,
  },
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  if (!PLAY_PURCHASES_ENABLED) {
    return Response.json(
      { ok: false, error: "play_payments_temporarily_disabled" },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!serviceKey || !anonKey) {
    return new Response("missing Supabase env", { status: 500 });
  }

  const authHeader = req.headers.get("Authorization") || "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!accessToken) return new Response("missing token", { status: 401 });

  const body = (await req.json()) as VerifyBody;
  const productId = body.product_id?.trim();
  const purchaseToken = body.purchase_token?.trim();
  const packageName = body.package_name?.trim() || DEFAULT_PACKAGE_NAME;
  if (!productId || !purchaseToken) {
    return new Response("missing purchase fields", { status: 400 });
  }
  if (packageName !== DEFAULT_PACKAGE_NAME) {
    return new Response("invalid package", { status: 400 });
  }
  if (
    productId !== "com.x5studio.app.verified.monthly" &&
    !planEntitlements[productId]
  ) {
    return new Response("unknown product", { status: 400 });
  }

  const authClient = createClient(SUPABASE_URL, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser(
    accessToken,
  );
  if (userError || !userData.user) {
    return new Response("invalid user", { status: 401 });
  }

  const googleAccessToken = await googlePlayAccessToken();
  const purchase = await loadGoogleSubscription(
    packageName,
    purchaseToken,
    googleAccessToken,
  );
  const entitlement = extractEntitlement(productId, purchase);
  if (!entitlement.ok) {
    return new Response(entitlement.error, { status: entitlement.status });
  }

  const admin = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const userId = userData.user.id;
  const now = new Date().toISOString();
  const expiry = entitlement.expiry;
  const update = productId === "com.x5studio.app.verified.monthly"
    ? {
      is_verified: true,
      verified_until: expiry,
    }
    : await subscriptionUpdate(admin, userId, productId, now, expiry);

  const { data: rows, error: updateError } = await admin
    .from("profiles")
    .update(update)
    .eq("id", userId)
    .select("*");

  if (updateError) {
    return new Response(`profile update error: ${updateError.message}`, {
      status: 500,
    });
  }
  const profile = rows?.[0];
  if (!profile) return new Response("profile not found", { status: 404 });

  return Response.json({ ok: true, product_id: productId, profile });
});

async function subscriptionUpdate(
  admin: any,
  userId: string,
  productId: string,
  now: string,
  expiry: string,
): Promise<Record<string, unknown>> {
  const plan = planEntitlements[productId];
  if (!plan) return {};

  const { data: current } = await admin
    .from("profiles")
    .select("credits,subscription_end_date")
    .eq("id", userId)
    .maybeSingle();

  const currentExpiry = Date.parse(
    (current?.subscription_end_date as string | undefined) || "",
  );
  const newExpiry = Date.parse(expiry);
  const shouldGrantCredits = Number.isNaN(currentExpiry) ||
    newExpiry > currentExpiry;

  return {
    plan: plan.profilePlan,
    credits: Number(current?.credits || 0) +
      (shouldGrantCredits ? plan.credits : 0),
    subscription_type: plan.subscriptionType,
    subscription_date: now,
    subscription_end_date: expiry,
  };
}

function extractEntitlement(
  requestedProductId: string,
  purchase: any,
): { ok: true; expiry: string } | { ok: false; status: number; error: string } {
  const state = purchase?.subscriptionState;
  const activeStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  ]);
  if (state && !activeStates.has(state)) {
    return { ok: false, status: 402, error: `purchase not active: ${state}` };
  }
  const lineItems = Array.isArray(purchase?.lineItems)
    ? purchase.lineItems
    : [];
  const matching =
    lineItems.find((item: any) => item?.productId === requestedProductId) ||
    lineItems[0];
  const expiry = matching?.expiryTime;
  if (!matching || !expiry) {
    return { ok: false, status: 402, error: "purchase not active" };
  }
  if (matching.productId && matching.productId !== requestedProductId) {
    return { ok: false, status: 400, error: "product mismatch" };
  }
  if (Date.parse(expiry) <= Date.now()) {
    return { ok: false, status: 402, error: "purchase expired" };
  }
  return { ok: true, expiry };
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
    throw new Error(`Google Play purchase error ${response.status}: ${text}`);
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
