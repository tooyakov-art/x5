import {
  AppleVerificationError,
  createHandler,
  EntitlementApplyError,
  type HandlerDependencies,
} from "./index.ts";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals<T>(actual: T, expected: T): void {
  if (actual !== expected) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function signedTransaction(environment = "Production"): string {
  const payload = btoa(JSON.stringify({ environment }))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
  return `header.${payload}.signature`;
}

const userId = "7b5a5cb8-239a-4cd1-b5d8-968cc1d437f4";
const verifiedPayload = {
  bundleId: "com.x5studio.app",
  productId: "com.x5studio.app.pro.monthly",
  transactionId: "2000000123456789",
  originalTransactionId: "2000000123400000",
  appAccountToken: userId,
  purchaseDate: Date.UTC(2026, 6, 1),
  expiresDate: Date.UTC(2026, 7, 1),
  signedDate: Date.UTC(2026, 6, 14),
  environment: "Production",
};

function dependencies(
  overrides: Partial<HandlerDependencies> = {},
): HandlerDependencies {
  return {
    now: () => Date.UTC(2026, 6, 14),
    authenticate: () => Promise.resolve(userId),
    verifySignedTransaction: () => Promise.resolve(verifiedPayload),
    applyVerifiedTransaction: () =>
      Promise.resolve({
        status: "applied",
        credits_granted: 2000,
        subscription_end_date: "2026-08-01T00:00:00.000Z",
        is_verified: false,
      }),
    logError: () => undefined,
    ...overrides,
  };
}

function post(body: unknown, token = "access-token"): Request {
  return new Request(
    "https://example.test/functions/v1/verify-app-store-transaction",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

Deno.test("handler authenticates before touching the transaction", async () => {
  let verified = false;
  const handler = createHandler(dependencies({
    authenticate: () => Promise.resolve(null),
    verifySignedTransaction: () => {
      verified = true;
      return Promise.resolve(verifiedPayload);
    },
  }));

  const response = await handler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(response.status, 401);
  assertEquals(verified, false);
});

Deno.test("handler ignores no client-declared product or transaction fields", async () => {
  let verified = false;
  const handler = createHandler(dependencies({
    verifySignedTransaction: () => {
      verified = true;
      return Promise.resolve(verifiedPayload);
    },
  }));

  const response = await handler(post({
    signed_transaction: signedTransaction(),
    product_id: "forged.product",
  }));
  assertEquals(response.status, 400);
  assertEquals(verified, false);
});

Deno.test("handler verifies, validates, and applies the Apple payload", async () => {
  let applied: Record<string, unknown> | undefined;
  const handler = createHandler(dependencies({
    applyVerifiedTransaction: (authenticatedUserId, transaction) => {
      applied = { authenticatedUserId, ...transaction };
      return Promise.resolve({
        status: "applied",
        credits_granted: 2000,
        subscription_end_date: transaction.expiresDate,
        is_verified: false,
      });
    },
  }));

  const response = await handler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "applied");
  assertEquals(body.credits_granted, 2000);
  assert(applied);
  assertEquals(applied.authenticatedUserId, userId);
  assertEquals(applied.productId, "com.x5studio.app.pro.monthly");
  assertEquals(applied.environment, "Production");
});

Deno.test("handler verifies but never applies Sandbox transactions to production", async () => {
  let verified = false;
  let applied = false;
  const handler = createHandler(dependencies({
    verifySignedTransaction: () => {
      verified = true;
      return Promise.resolve({
        ...verifiedPayload,
        environment: "Sandbox",
      });
    },
    applyVerifiedTransaction: () => {
      applied = true;
      return Promise.resolve({
        status: "applied",
        credits_granted: 2000,
        subscription_end_date: "2026-08-01T00:00:00.000Z",
        is_verified: false,
      });
    },
  }));

  const response = await handler(
    post({ signed_transaction: signedTransaction("Sandbox") }),
  );

  assertEquals(verified, true);
  assertEquals(response.status, 403);
  assertEquals((await response.json()).error, "sandbox_not_allowed");
  assertEquals(applied, false);
});

Deno.test("handler returns exact already_applied and owned_by_other status contracts", async () => {
  const alreadyHandler = createHandler(dependencies({
    applyVerifiedTransaction: () =>
      Promise.resolve({
        status: "already_applied",
        credits_granted: 0,
        subscription_end_date: "2026-08-01T00:00:00.000Z",
        is_verified: false,
      }),
  }));
  const already = await alreadyHandler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(already.status, 200);
  assertEquals((await already.json()).status, "already_applied");

  const ownedHandler = createHandler(dependencies({
    applyVerifiedTransaction: () =>
      Promise.reject(new EntitlementApplyError("owned_by_other", 409)),
  }));
  const owned = await ownedHandler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(owned.status, 409);
  assertEquals((await owned.json()).status, "owned_by_other");
});

Deno.test("handler distinguishes retryable Apple verification failures", async () => {
  const retryableHandler = createHandler(dependencies({
    verifySignedTransaction: () =>
      Promise.reject(new AppleVerificationError(true)),
  }));
  const retryable = await retryableHandler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(retryable.status, 503);
  assertEquals(
    (await retryable.json()).error,
    "apple_verification_unavailable",
  );

  const invalidHandler = createHandler(dependencies({
    verifySignedTransaction: () =>
      Promise.reject(new AppleVerificationError(false)),
  }));
  const invalid = await invalidHandler(
    post({ signed_transaction: signedTransaction() }),
  );
  assertEquals(invalid.status, 400);
  assertEquals((await invalid.json()).error, "invalid_apple_transaction");
});
