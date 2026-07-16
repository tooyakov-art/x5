export const ANDROID_PACKAGE_NAME = "com.x5marketing.mobile";

const productEntitlements = {
  x5_lite_monthly_v2: {
    productId: "x5_lite_monthly_v2",
    purchaseType: "subscription",
    profilePlan: "pro",
    subscriptionType: "lite_monthly",
    credits: 1000,
    verified: false,
    legacy: false,
  },
  x5_pro_monthly_v2: {
    productId: "x5_pro_monthly_v2",
    purchaseType: "subscription",
    profilePlan: "pro",
    subscriptionType: "pro_monthly",
    credits: 2000,
    verified: false,
    legacy: false,
  },
  x5_max_monthly_v2: {
    productId: "x5_max_monthly_v2",
    purchaseType: "subscription",
    profilePlan: "pro",
    subscriptionType: "max_monthly",
    credits: 5000,
    verified: false,
    legacy: false,
  },
  x5_verified_monthly_v2: {
    productId: "x5_verified_monthly_v2",
    purchaseType: "subscription",
    profilePlan: undefined,
    subscriptionType: "verified_monthly",
    credits: 0,
    verified: true,
    legacy: false,
  },
  x5_pro_monthly: {
    productId: "x5_pro_monthly",
    purchaseType: "subscription",
    profilePlan: "pro",
    subscriptionType: "monthly",
    credits: 1000,
    verified: false,
    legacy: true,
  },
  x5_pro_yearly: {
    productId: "x5_pro_yearly",
    purchaseType: "subscription",
    profilePlan: "pro",
    subscriptionType: "yearly",
    credits: 12000,
    verified: false,
    legacy: true,
  },
  x5_credits_1000_v2: {
    productId: "x5_credits_1000_v2",
    purchaseType: "inapp",
    profilePlan: undefined,
    subscriptionType: undefined,
    credits: 1000,
    verified: false,
    legacy: false,
  },
  x5_credits_2000_v2: {
    productId: "x5_credits_2000_v2",
    purchaseType: "inapp",
    profilePlan: undefined,
    subscriptionType: undefined,
    credits: 2000,
    verified: false,
    legacy: false,
  },
  x5_credits_5000_v2: {
    productId: "x5_credits_5000_v2",
    purchaseType: "inapp",
    profilePlan: undefined,
    subscriptionType: undefined,
    credits: 5000,
    verified: false,
    legacy: false,
  },
  x5_verified_monthly: {
    productId: "x5_verified_monthly",
    purchaseType: "subscription",
    profilePlan: undefined,
    subscriptionType: "verified_monthly",
    credits: 0,
    verified: true,
    legacy: true,
  },
};

export function getProductEntitlement(productId) {
  return productEntitlements[productId];
}

export function validateInAppPurchaseState(purchase) {
  if (purchase?.purchaseState === 0) return { ok: true };

  const state = purchase?.purchaseState ?? "missing";
  return {
    ok: false,
    status: 402,
    error: `product_not_purchased:${state}`,
  };
}

export function validateSubscriptionPurchaseState(purchase) {
  const state = purchase?.subscriptionState ?? "missing";
  const activeStates = new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    // Google keeps a canceled auto-renewing subscription entitled until the
    // paid line-item expiry; extractSubscriptionEntitlement validates that next.
    "SUBSCRIPTION_STATE_CANCELED",
  ]);
  if (activeStates.has(state)) return { ok: true };

  return {
    ok: false,
    status: 402,
    error: `purchase_not_active:${state}`,
  };
}

export function buildProfileUpdate({
  productId,
  currentProfile = {},
  now,
  expiry,
  skipCreditGrant = false,
}) {
  const entitlement = getProductEntitlement(productId);
  if (!entitlement) throw new Error(`unknown product: ${productId}`);

  if (entitlement.verified) {
    return {
      is_verified: true,
      verified_until: expiry,
    };
  }

  const currentCredits = Number(currentProfile?.credits || 0);
  if (entitlement.purchaseType === "inapp") {
    return {
      credits: currentCredits + (skipCreditGrant ? 0 : entitlement.credits),
    };
  }

  const currentExpiry = Date.parse(currentProfile?.subscription_end_date || "");
  const newExpiry = Date.parse(expiry || "");
  const expiryAdvances = Number.isNaN(currentExpiry) ||
    newExpiry > currentExpiry;
  const creditsToGrant = !skipCreditGrant && expiryAdvances
    ? entitlement.credits
    : 0;

  return {
    plan: entitlement.profilePlan,
    credits: currentCredits + creditsToGrant,
    subscription_type: entitlement.subscriptionType,
    subscription_date: now,
    subscription_end_date: expiry,
  };
}
