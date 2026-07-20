import { Buffer } from "node:buffer";
import {
  type KeyObject,
  verify as verifySignature,
  X509Certificate,
} from "node:crypto";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "@apple/app-store-server-library";

interface PayloadValidator<T> {
  validate(value: unknown): value is T;
}

function decodeBase64URL(value: string): Buffer {
  const standard = value.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(
    standard.padEnd(Math.ceil(standard.length / 4) * 4, "="),
    "base64",
  );
}

function parseJSONSegment(value: string): unknown {
  return JSON.parse(decodeBase64URL(value).toString("utf8"));
}

/**
 * Apple's official verifier performs the full certificate-chain, Apple OID,
 * effective-date, bundle, app-id and environment checks. Its last step exports
 * the verified KeyObject to PEM before checking the JWS, but KeyObject.export
 * is not supported consistently by the Supabase Edge runtime. Override only
 * that protected step and verify the ES256 signature directly with the already
 * chain-validated leaf key.
 */
export class EdgeCompatibleSignedDataVerifier extends SignedDataVerifier {
  protected override async verifyJWT<T>(
    jwt: string,
    validator: PayloadValidator<T>,
    signedDateExtractor: (decodedJWT: T) => Date,
  ): Promise<T> {
    try {
      const segments = jwt.split(".");
      if (
        segments.length !== 3 ||
        segments.some((segment) => segment.length === 0)
      ) {
        throw new VerificationException(VerificationStatus.FAILURE);
      }

      const decodedJWT = parseJSONSegment(segments[1]);
      if (!validator.validate(decodedJWT)) {
        throw new VerificationException(VerificationStatus.FAILURE);
      }
      if (
        this.environment === Environment.XCODE ||
        this.environment === Environment.LOCAL_TESTING
      ) {
        return decodedJWT;
      }

      let leaf: X509Certificate;
      let intermediate: X509Certificate;
      try {
        const header = parseJSONSegment(segments[0]);
        if (
          typeof header !== "object" ||
          header === null ||
          (header as Record<string, unknown>).alg !== "ES256"
        ) {
          throw new Error("invalid_apple_jws_algorithm");
        }
        const chain = (header as Record<string, unknown>).x5c;
        if (!Array.isArray(chain) || chain.length !== 3) {
          throw new VerificationException(
            VerificationStatus.INVALID_CHAIN_LENGTH,
          );
        }
        if (!chain.every((certificate) => typeof certificate === "string")) {
          throw new Error("invalid_apple_certificate_chain");
        }
        leaf = new X509Certificate(Buffer.from(chain[0], "base64"));
        intermediate = new X509Certificate(Buffer.from(chain[1], "base64"));
      } catch (error) {
        if (error instanceof VerificationException) throw error;
        throw new VerificationException(
          VerificationStatus.INVALID_CERTIFICATE,
          error instanceof Error ? error : undefined,
        );
      }

      const effectiveDate = this.enableOnlineChecks
        ? new Date()
        : signedDateExtractor(decodedJWT);
      const publicKey: KeyObject = await this.verifyCertificateChain(
        this.rootCertificates,
        leaf,
        intermediate,
        effectiveDate,
      );
      const namedCurve = publicKey.asymmetricKeyDetails?.namedCurve;
      if (
        publicKey.asymmetricKeyType !== "ec" ||
        !["prime256v1", "secp256r1", "P-256"].includes(namedCurve ?? "")
      ) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
        );
      }
      const signature = decodeBase64URL(segments[2]);
      if (signature.length !== 64) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
        );
      }
      const validSignature = verifySignature(
        "sha256",
        Buffer.from(`${segments[0]}.${segments[1]}`, "utf8"),
        { key: publicKey, dsaEncoding: "ieee-p1363" },
        signature,
      );
      if (!validSignature) {
        throw new VerificationException(
          VerificationStatus.VERIFICATION_FAILURE,
        );
      }
      return decodedJWT;
    } catch (error) {
      if (error instanceof VerificationException) throw error;
      throw new VerificationException(
        VerificationStatus.VERIFICATION_FAILURE,
        error instanceof Error ? error : undefined,
      );
    }
  }
}
