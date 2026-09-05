import { describe, it, expect } from "vitest";
import { parseSMS, parseAmountToPaise } from "./smsParser";

/**
 * Parity tests for the SMS parser port.
 *
 * The Swift app had no tests at all, and its parsing bugs (wrong amount, wrong
 * direction) were found by the user in production. Every real bank format the
 * Swift parsers were tuned against is pinned here so the port can't regress.
 */

describe("parseAmountToPaise", () => {
  it("keeps integer paise, no float drift", () => {
    expect(parseAmountToPaise("1,234.50")).toBe(123450);
    expect(parseAmountToPaise("0.10")).toBe(10);
    expect(parseAmountToPaise("999")).toBe(99900);
    expect(parseAmountToPaise("1,23,456.78")).toBe(12345678);
  });

  it("survives the classic float case", () => {
    // 0.1 + 0.2 !== 0.3 in float. In paise it's just 10 + 20 === 30.
    expect(parseAmountToPaise("0.10")! + parseAmountToPaise("0.20")!)
      .toBe(parseAmountToPaise("0.30"));
  });

  it("rejects junk", () => {
    expect(parseAmountToPaise("abc")).toBeNull();
    expect(parseAmountToPaise("")).toBeNull();
  });
});

describe("HDFC Savings", () => {
  it("parses a Sent debit with ref and last4", () => {
    const r = parseSMS(
      "Sent Rs.380.00 From HDFC Bank A/C *6311 To SWIGGY On 15/05/26 Ref 123456789",
    );
    expect(r).toBeTruthy();
    expect(r!.type).toBe("debit");
    expect(r!.amount).toBe(38000);
    expect(r!.merchantRaw).toBe("SWIGGY");
    expect(r!.last4).toBe("6311");
    expect(r!.upiRef).toBe("123456789");
    expect(r!.matchedBy).toBe("hdfc-savings-sent");
  });

  it("parses a Credit Alert", () => {
    const r = parseSMS(
      "Credit Alert! Rs.5000.00 credited to HDFC Bank A/c XX6311 on 15-05-26 from VPA jay@okhdfc (UPI 987654321)",
    );
    expect(r!.type).toBe("credit");
    expect(r!.amount).toBe(500000);
    expect(r!.last4).toBe("6311");
    expect(r!.upiRef).toBe("987654321");
  });
});

describe("HDFC Credit Cards", () => {
  it("parses Tata Neu UPI txn (DD-MM, no year)", () => {
    const r = parseSMS(
      "Txn Rs.1,250.00 On HDFC Bank Card 6624 At AMAZON by UPI 445566 On 12-05",
    );
    expect(r!.type).toBe("debit");
    expect(r!.amount).toBe(125000);
    expect(r!.last4).toBe("6624");
    expect(r!.merchantRaw).toBe("AMAZON");
    // DD-MM has no year — parser must still produce a date.
    expect(r!.date).toBeTypeOf("number");
  });

  it("parses Regalia Spent with full timestamp", () => {
    const r = parseSMS(
      "Spent Rs.3,237.00 On HDFC Bank Card 4493 At MYNTRA On 2026-05-12:14:30:00",
    );
    expect(r!.amount).toBe(323700);
    expect(r!.last4).toBe("4493");
    const d = new Date(r!.date!);
    expect(d.getFullYear()).toBe(2026);
    expect(d.getMonth()).toBe(4); // May
    expect(d.getDate()).toBe(12);
  });
});

describe("ICICI Sapphiro", () => {
  it("parses spend with masked card and month-name date", () => {
    const r = parseSMS(
      "INR 747.50 spent using ICICI Bank Card XX2000 on 12-May-26 on PAYBOOKMYSHOW COM. Avl Limit: INR 87,650",
    );
    expect(r!.type).toBe("debit");
    // The Swift PDF parser once read this row as a ₹14 CREDIT because it
    // grabbed the reward-points column. Pin the real amount and direction.
    expect(r!.amount).toBe(74750);
    expect(r!.last4).toBe("2000");
    expect(r!.merchantRaw).toBe("PAYBOOKMYSHOW COM");
  });
});

describe("SBI Cashback", () => {
  it("parses spend with ending-XXXX card", () => {
    const r = parseSMS(
      "Rs.2,500.00 spent on your SBI Credit Card ending 5075 at BPCL FUEL on 03/05/26",
    );
    expect(r!.type).toBe("debit");
    expect(r!.amount).toBe(250000);
    expect(r!.last4).toBe("5075");
  });
});

describe("Federal Bank", () => {
  it("parses a received credit", () => {
    const r = parseSMS(
      "You have received INR 25,000.00 in your Account XXXXX8708. Amount sent by JAYESH LOKHANDE on May 12, 2026",
    );
    expect(r!.type).toBe("credit");
    expect(r!.amount).toBe(2500000);
    expect(r!.last4).toBe("8708");
    const d = new Date(r!.date!);
    expect(d.getMonth()).toBe(4);
    expect(d.getDate()).toBe(12);
  });

  it("parses a sent debit and keeps the time of day", () => {
    const r = parseSMS(
      "Rs 450.00 sent via UPI on 12-05-2026 at 14:22:10 to ZOMATO.Ref:556677 -Federal Bank",
    );
    expect(r!.type).toBe("debit");
    expect(r!.amount).toBe(45000);
    expect(r!.upiRef).toBe("556677");
    const d = new Date(r!.date!);
    // Time must survive — midnight would collapse same-day ordering.
    expect(d.getHours()).toBe(14);
    expect(d.getMinutes()).toBe(22);
  });
});

describe("precedence", () => {
  it("prefers the specific bank parser over the generic fallback", () => {
    const r = parseSMS(
      "Sent Rs.380.00 From HDFC Bank A/C *6311 To SWIGGY On 15/05/26 Ref 123456789",
    );
    // A generic "debited" rule would lose the merchant, last4 and ref.
    expect(r!.matchedBy).toBe("hdfc-savings-sent");
  });
});

describe("non-transactions", () => {
  it("returns null for OTP and marketing", () => {
    expect(parseSMS("Your OTP is 123456. Do not share it with anyone.")).toBeNull();
    expect(parseSMS("Get 10% off on your next order! Shop now.")).toBeNull();
    expect(parseSMS("")).toBeNull();
  });
});
