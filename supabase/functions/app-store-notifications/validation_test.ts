import {
  InputError,
  parseAppAppleId,
  parseAppleRootCertificates,
  parseNotificationRequestBody,
  parseUntrustedNotificationEnvironment,
  validateVerifiedRefundNotification,
} from "./validation.ts";

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

function assertInputError(
  action: () => unknown,
  code: string,
  status = 400,
): void {
  try {
    action();
  } catch (error) {
    assert(
      error instanceof InputError,
      `expected InputError: ${String(error)}`,
    );
    assertEquals(error.code, code);
    assertEquals(error.status, status);
    return;
  }
  throw new Error(`expected ${code}`);
}

function unsignedJWS(payload: Record<string, unknown>): string {
  const encoded = btoa(JSON.stringify(payload))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/g, "");
  return `header.${encoded}.signature`;
}

const userId = "7b5a5cb8-239a-4cd1-b5d8-968cc1d437f4";
const now = Date.UTC(2026, 6, 16, 12);
const outerSignedDate = Date.UTC(2026, 6, 16, 11, 59);
const purchaseDate = Date.UTC(2026, 6, 1);
const transactionSignedDate = Date.UTC(2026, 6, 16, 11, 58);
const revocationDate = Date.UTC(2026, 6, 15);

const refundNotification = {
  notificationType: "REFUND",
  notificationUUID: "8ea875c0-2a6a-4d15-8c98-ab8b28cf8aad",
  version: "2.0",
  signedDate: outerSignedDate,
  data: {
    bundleId: "com.x5studio.app",
    environment: "Production",
    signedTransactionInfo: "inner.header.signature",
  },
};

const creditTransaction = {
  bundleId: "com.x5studio.app",
  environment: "Production",
  productId: "com.x5studio.app.credits.2000",
  transactionId: "2000000123456790",
  originalTransactionId: "2000000123456790",
  appAccountToken: userId,
  type: "Consumable",
  quantity: 1,
  purchaseDate,
  signedDate: transactionSignedDate,
  revocationDate,
  revocationType: "REFUND_FULL",
  revocationPercentage: 100000,
};

Deno.test("request body accepts exactly one camel-case signedPayload", () => {
  assertEquals(
    parseNotificationRequestBody({ signedPayload: "  a.b.c  " }),
    "a.b.c",
  );
  assertInputError(
    () =>
      parseNotificationRequestBody({
        signedPayload: "a.b.c",
        transactionId: "forged",
      }),
    "invalid_request_body",
  );
  assertInputError(
    () => parseNotificationRequestBody({ signed_payload: "a.b.c" }),
    "invalid_request_body",
  );
});

Deno.test("only the unsigned outer environment is used for verifier routing", () => {
  assertEquals(
    parseUntrustedNotificationEnvironment(unsignedJWS({
      notificationType: "forged",
      data: { environment: "Production", bundleId: "attacker.app" },
    })),
    "Production",
  );
  assertEquals(
    parseUntrustedNotificationEnvironment(unsignedJWS({
      data: { environment: "Sandbox" },
    })),
    "Sandbox",
  );
  assertInputError(
    () =>
      parseUntrustedNotificationEnvironment(unsignedJWS({
        data: { environment: "Xcode" },
      })),
    "invalid_environment",
  );
});

Deno.test("summary and appData notifications are routed only for outer verification", () => {
  assertEquals(
    parseUntrustedNotificationEnvironment(unsignedJWS({
      notificationType: "RENEWAL_EXTENSION",
      summary: { environment: "Production", bundleId: "forged" },
    })),
    "Production",
  );
  assertEquals(
    parseUntrustedNotificationEnvironment(unsignedJWS({
      notificationType: "RESCIND_CONSENT",
      appData: { environment: "Sandbox", bundleId: "forged" },
    })),
    "Sandbox",
  );
});

Deno.test("unsigned notification routing rejects missing or conflicting environments", () => {
  for (
    const payload of [
      { notificationType: "TEST" },
      {
        data: { environment: "Production" },
        summary: { environment: "Sandbox" },
      },
      {
        data: { environment: "Production" },
        appData: { environment: "Production" },
      },
    ]
  ) {
    assertInputError(
      () => parseUntrustedNotificationEnvironment(unsignedJWS(payload)),
      "invalid_environment",
    );
  }
});

Deno.test("full credit refund is normalized from two verified JWS payloads", () => {
  const event = validateVerifiedRefundNotification(
    refundNotification,
    creditTransaction,
    "Production",
    now,
  );

  assertEquals(event.eventId, refundNotification.notificationUUID);
  assertEquals(event.notificationType, "REFUND");
  assertEquals(event.userId, userId);
  assertEquals(event.productKind, "consumable");
  assertEquals(event.productId, "com.x5studio.app.credits.2000");
  assertEquals(event.environment, "Production");
  assertEquals(event.quantity, 1);
  assertEquals(event.revocationPercentage, 100000);
  assertEquals(event.revocationDate, "2026-07-15T00:00:00.000Z");
  assertEquals(event.notificationSignedDate, "2026-07-16T11:59:00.000Z");
});

Deno.test("prorated credit refund preserves Apple's milliunit percentage", () => {
  const event = validateVerifiedRefundNotification(
    refundNotification,
    {
      ...creditTransaction,
      revocationType: "REFUND_PRORATED",
      revocationPercentage: 67932,
    },
    "Production",
    now,
  );
  assertEquals(event.revocationPercentage, 67932);
});

Deno.test("partial refund fields must be internally consistent", () => {
  for (
    const transaction of [
      {
        ...creditTransaction,
        revocationType: "REFUND_PRORATED",
        revocationPercentage: 100000,
      },
      {
        ...creditTransaction,
        revocationType: "REFUND_PRORATED",
        revocationPercentage: 0,
      },
      {
        ...creditTransaction,
        revocationType: "REFUND_FULL",
        revocationPercentage: 50000,
      },
      {
        ...creditTransaction,
        revocationType: "FAMILY_REVOKE",
        revocationPercentage: 100000,
      },
      { ...creditTransaction, revocationPercentage: 100001 },
    ]
  ) {
    assertInputError(
      () =>
        validateVerifiedRefundNotification(
          refundNotification,
          transaction,
          "Production",
          now,
        ),
      "invalid_revocation_percentage",
    );
  }
});

Deno.test("verified subscription refund remains atomic even when price refund is prorated", () => {
  const event = validateVerifiedRefundNotification(
    refundNotification,
    {
      ...creditTransaction,
      productId: "com.x5studio.app.verified.monthly",
      type: "Auto-Renewable Subscription",
      quantity: undefined,
      expiresDate: Date.UTC(2026, 7, 1),
      revocationType: "REFUND_PRORATED",
      revocationPercentage: 50000,
    },
    "Production",
    now,
  );
  assertEquals(event.productKind, "subscription");
  assertEquals(event.quantity, null);
  assertEquals(event.revocationPercentage, 50000);
  assertEquals(event.expiresDate, "2026-08-01T00:00:00.000Z");
});

Deno.test("refund reversal requires Apple to omit every revocation field", () => {
  const reversed = validateVerifiedRefundNotification(
    { ...refundNotification, notificationType: "REFUND_REVERSED" },
    {
      ...creditTransaction,
      revocationDate: undefined,
      revocationType: undefined,
      revocationPercentage: undefined,
    },
    "Production",
    now,
  );
  assertEquals(reversed.notificationType, "REFUND_REVERSED");
  assertEquals(reversed.revocationDate, null);
  assertEquals(reversed.revocationPercentage, null);

  assertInputError(
    () =>
      validateVerifiedRefundNotification(
        { ...refundNotification, notificationType: "REFUND_REVERSED" },
        creditTransaction,
        "Production",
        now,
      ),
    "invalid_refund_reversal",
  );
});

Deno.test("outer and inner signed identity must agree with X5", () => {
  for (
    const [outer, inner, code] of [
      [
        {
          ...refundNotification,
          data: { ...refundNotification.data, bundleId: "attacker.app" },
        },
        creditTransaction,
        "invalid_bundle",
      ],
      [
        refundNotification,
        { ...creditTransaction, bundleId: "attacker.app" },
        "invalid_bundle",
      ],
      [
        refundNotification,
        { ...creditTransaction, environment: "Sandbox" },
        "invalid_environment",
      ],
      [
        refundNotification,
        { ...creditTransaction, appAccountToken: undefined },
        "missing_account_token",
      ],
      [refundNotification, {
        ...creditTransaction,
        appAccountToken: "not-a-uuid",
      }, "invalid_app_account_token"],
    ] as const
  ) {
    assertInputError(
      () =>
        validateVerifiedRefundNotification(
          outer,
          inner,
          "Production",
          now,
        ),
      code,
    );
  }
});

Deno.test("unsupported signed products are acknowledged separately from invalid data", () => {
  assertInputError(
    () =>
      validateVerifiedRefundNotification(
        refundNotification,
        { ...creditTransaction, productId: "com.x5studio.app.pro.monthly" },
        "Production",
        now,
      ),
    "unsupported_product",
    200,
  );
});

Deno.test("Apple verifier configuration accepts local certificate formats", () => {
  const pem = "-----BEGIN CERTIFICATE-----\nAQID\n-----END CERTIFICATE-----";
  const fromPem = parseAppleRootCertificates(pem, undefined);
  assertEquals(fromPem.length, 1);
  assertEquals(Array.from(fromPem[0]).join(","), "1,2,3");

  const fromBase64 = parseAppleRootCertificates(
    undefined,
    JSON.stringify(["AQID", "BAUG"]),
  );
  assertEquals(fromBase64.length, 2);
  assertEquals(Array.from(fromBase64[1]).join(","), "4,5,6");
  assertEquals(parseAppAppleId("1234567890"), 1234567890);

  assertInputError(
    () => parseAppleRootCertificates(undefined, undefined),
    "missing_apple_root_certificates",
    500,
  );
  assertInputError(
    () => parseAppAppleId(undefined),
    "missing_apple_app_id",
    500,
  );
});
