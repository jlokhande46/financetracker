import { describe, it, expect } from "vitest";
import { normalizeMerchant, merchantRuleKey } from "./merchantNormalizer";
import { classify } from "./classifier";
import { rupees } from "../domain/types";

describe("normalizeMerchant", () => {
  it("strips bank prefixes and VPA handles", () => {
    expect(normalizeMerchant("UPI-SWIGGY-swiggy@okicici")).toBe("Swiggy");
    expect(normalizeMerchant("POS SWGY")).toBe("Swiggy");
  });

  it("resolves alias-map entries including obscure ones", () => {
    expect(normalizeMerchant("ASSPL")).toBe("Amazon");
    expect(normalizeMerchant("AGODAPANYPTELTD")).toBe("Agoda");
    expect(normalizeMerchant("ZEPTOMARKETPLACEPRIV")).toBe("Zepto");
  });

  it("prefers the longest alias match", () => {
    // "AMAZON PAY" must not be shortened to "Amazon" by the "AMAZON" key.
    expect(normalizeMerchant("AMAZON PAY")).toBe("Amazon Pay");
  });

  it("strips corporate suffixes", () => {
    expect(normalizeMerchant("SOME SHOP PVT LTD")).toBe("Some Shop");
  });

  it("drops long digit runs that are really ref numbers", () => {
    expect(normalizeMerchant("BATA INDIA 123456789")).toBe("Bata");
  });

  it("lets a learned user rule win outright", () => {
    expect(normalizeMerchant("Upi-jay-rent-vpa123", "Rent")).toBe("Rent");
  });
});

describe("merchantRuleKey", () => {
  it("collapses UPI variants of the same merchant to one key", () => {
    const a = merchantRuleKey("UPI-SWIGGY-987654321@oksbi");
    const b = merchantRuleKey("swiggy");
    expect(a).toContain("swiggy");
    expect(b).toBe("swiggy");
  });
});

describe("classify", () => {
  it("routes CC payments before the salary heuristic", () => {
    // A ₹26K credit would otherwise look like income.
    const r = classify({
      merchantName: "BBPS Payment received",
      amount: rupees(26_000),
      type: "credit",
      rawContent: "BPPY CC PAYMENT RECEIVED",
    });
    expect(r.categorySlug).toBe("cc_payment");
    expect(r.confidence).toBe(1.0);
  });

  it("lets a saved user rule beat the built-in keywords", () => {
    const r = classify({
      merchantName: "Swiggy",
      amount: rupees(380),
      type: "debit",
      userRuleSlug: "dining",
    });
    expect(r.categorySlug).toBe("dining");
    expect(r.confidence).toBe(1.0);
  });

  it("matches built-in keywords at 0.92", () => {
    const r = classify({ merchantName: "Swiggy", amount: rupees(380), type: "debit" });
    expect(r.categorySlug).toBe("food");
    expect(r.confidence).toBe(0.92);
  });

  it("treats large unmatched credits as salary", () => {
    const r = classify({ merchantName: "ACME CORP", amount: rupees(120_000), type: "credit" });
    expect(r.categorySlug).toBe("salary");
  });

  it("falls back to others at review-triggering confidence", () => {
    const r = classify({ merchantName: "ZZZ UNKNOWN", amount: rupees(499), type: "debit" });
    expect(r.categorySlug).toBe("others");
    // Below the 0.85 review threshold, which is the point.
    expect(r.confidence).toBeLessThan(0.85);
  });
});
