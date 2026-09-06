import { describe, expect, it } from "vitest";
import { rupees } from "../domain/types";
import {
  detectBank,
  extractAccountLast4,
  extractAmounts,
  extractDate,
  groupLinesIntoRecords,
  inferAmountAndType,
  isJunkNarration,
  parseHDFCCreditCardRow,
  parseStatementText,
  parseTransactionRecord,
  recordsAppearColumnScrambled,
} from "./pdfParser";

/** Convenience: run the direction inference the way parseTransactionRecord does. */
function infer(line: string, bank: string | null = null) {
  const d = extractDate(line);
  const post = d ? line.slice(d.end) : line;
  const local = extractAmounts(post, true);
  const amounts = local.map((a) => ({ ...a, index: a.index + (d?.end ?? 0) }));
  return inferAmountAndType(amounts, line, bank);
}

describe("amount extraction", () => {
  it("does not treat a space as a thousands separator", () => {
    // The ICICI rewards column renders as "14 747.50". If space grouped, this
    // collapses to a single ₹14,747.50 and both the amount and the direction
    // come out wrong.
    const a = extractAmounts("BookMyShow 14 747.50", true);
    expect(a.map((x) => x.paise)).toEqual([rupees(14), rupees(747.5)]);
  });

  it("accepts comma grouping in both Indian and Western styles", () => {
    expect(extractAmounts("1,00,000.00").map((x) => x.paise)).toEqual([rupees(100000)]);
    expect(extractAmounts("100,000.00").map((x) => x.paise)).toEqual([rupees(100000)]);
  });

  it("ignores digits embedded in reference tokens", () => {
    expect(extractAmounts("UPI/S95818915/PAYU 1.00", true).map((x) => x.paise))
      .toEqual([rupees(1)]);
  });

  it("only accepts bare whole numbers when asked", () => {
    expect(extractAmounts("PAYU 0 1.00").map((x) => x.paise)).toEqual([rupees(1)]);
    expect(extractAmounts("PAYU 0 1.00", true).map((x) => x.paise))
      .toEqual([0, rupees(1)]);
  });

  it("captures a Cr/Dr suffix", () => {
    const [a] = extractAmounts("750.00 CR");
    expect(a).toMatchObject({ paise: rupees(750), cr: true, dr: false });
  });
});

describe("direction inference", () => {
  // These six are the real rows that drove the Swift fixes. PROGRESS.md pins
  // the expected step for each; if a step number moves, the reasoning changed.
  it("step 1: explicit CR wins", () => {
    const r = infer("02/06/2026 PayU 0 1.00 CR");
    expect(r).toMatchObject({ type: "credit", amount: rupees(1), step: "1-CR" });
  });

  it("step 6: no marker falls back to the rightmost amount as a debit", () => {
    const r = infer("02/06/2026 PayU 0 1.00");
    expect(r).toMatchObject({ type: "debit", amount: rupees(1), step: "6-default" });
  });

  it("step 6: BookMyShow takes the money column, not the reward points", () => {
    // The bug: 14 is reward points, 747.50 is the charge. Reading left-to-right
    // booked "+₹14 credit" on the user's ICICI Sapphiro statement.
    const r = infer("02/06/2026 BookMyShow 14 747.50");
    expect(r).toMatchObject({ type: "debit", amount: rupees(747.5), step: "6-default" });
  });

  it("step 6: still correct with a leading zero column", () => {
    const r = infer("02/06/2026 BookMyShow 0 14 747.50");
    expect(r).toMatchObject({ type: "debit", amount: rupees(747.5) });
  });

  it("step 1: a bill payment with CR is a credit", () => {
    const r = infer("02/06/2026 BBPS Payment 0 750.00 CR");
    expect(r).toMatchObject({ type: "credit", amount: rupees(750), step: "1-CR" });
  });

  it("step 4: Federal's withdrawal column reads as a debit", () => {
    const r = infer("02/06/2026 02/06/2026 NEFT OUT 25000 0 90672.62", "Federal");
    expect(r).toMatchObject({ type: "debit", amount: rupees(25000), step: "4-col" });
  });

  it("step 4 is Federal-only, so ICICI reward points are not read as a deposit", () => {
    // Same numeric shape as a Federal row. Without the bank gate this returns
    // a ₹14 credit — exactly the BookMyShow bug.
    const r = infer("02/06/2026 BookMyShow 0 14 747.50", "ICICI");
    expect(r.type).toBe("debit");
    expect(r.amount).toBe(rupees(747.5));
  });

  it("step 2: SBI's trailing C/D marks direction", () => {
    expect(infer("02 Jun 2026 SALARY 50,000.00 1,20,000.00 C"))
      .toMatchObject({ type: "credit", amount: rupees(50000), step: "2-C" });
    expect(infer("02 Jun 2026 SWIGGY 450.00 1,19,550.00 D"))
      .toMatchObject({ type: "debit", amount: rupees(450), step: "2-D" });
  });

  it("step 5 reads keywords from the narration only", () => {
    const r = infer("02/06/2026 PAYMENT RECEIVED 5,000.00");
    expect(r).toMatchObject({ type: "credit", step: "5-cc[payment received]" });
  });

  it("step 5 ignores keywords that appear after the amount", () => {
    // Footer boilerplate glued onto a row must not flip its direction.
    const r = infer("02/06/2026 BookMyShow 747.50 until payment received in full");
    expect(r.type).toBe("debit");
    expect(r.amount).toBe(rupees(747.5));
  });

  it("skips the Cr/Dr shortcut on a 4-column row where it marks the balance", () => {
    // The trailing CR belongs to the running balance, not the transaction.
    const r = infer("02/06/2026 ATM WDL 2000 0 500 45,000.00 CR", "Federal");
    expect(r.type).toBe("debit");
  });
});

describe("record grouping", () => {
  const lines = [
    "02/06/2026 BookMyShow Ltd",
    "MUMBAI 14 747.50",
    "Total amount due 12,345.00",
    "Interest will accrue until payment received in full",
  ];

  it("stops a record at its closing amount so the footer is not absorbed", () => {
    const records = groupLinesIntoRecords(lines, "ICICI");
    expect(records).toHaveLength(1);
    expect(records[0]).toBe("02/06/2026 BookMyShow Ltd MUMBAI 14 747.50");
    expect(records[0]).not.toContain("payment received");
  });

  it("the terminated record still parses as a ₹747.50 debit", () => {
    const [record] = groupLinesIntoRecords(lines, "ICICI");
    const row = parseTransactionRecord(record!, "ICICI");
    expect(row).toMatchObject({ type: "debit", amount: rupees(747.5) });
  });

  it("without the terminator the footer would flip the row to a credit", () => {
    // Documents the regression rather than the fix: Federal is exempt from the
    // terminator, so the same lines under Federal do swallow the footer.
    const [record] = groupLinesIntoRecords(lines, "Federal");
    expect(record).toContain("payment received");
  });

  it("keeps Federal's multi-line amount columns together", () => {
    const federal = [
      "02/06/2026 02/06/2026 NEFT OUT SALARY TRF",
      "25000",
      "0",
      "90672.62",
    ];
    const records = groupLinesIntoRecords(federal, "Federal");
    expect(records).toHaveLength(1);
    expect(records[0]).toContain("90672.62");
  });

  it("starts a new record at each date line", () => {
    const records = groupLinesIntoRecords(
      ["02/06/2026 A 10.00", "03/06/2026 B 20.00", "04/06/2026 C 30.00"],
      "ICICI",
    );
    expect(records).toHaveLength(3);
  });
});

describe("column-scramble detection", () => {
  it("flags a column-first extraction", () => {
    const scrambled = Array.from({ length: 5 }, () =>
      "01/06/2026 02/06/2026 03/06/2026 04/06/2026 05/06/2026 06/06/2026",
    );
    expect(recordsAppearColumnScrambled(scrambled)).toBe(true);
  });

  it("does not flag ordinary rows", () => {
    const normal = [
      "02/06/2026 BookMyShow 747.50",
      "03/06/2026 Swiggy 450.00",
      "04/06/2026 Amazon 1,299.00",
    ];
    expect(recordsAppearColumnScrambled(normal)).toBe(false);
  });

  it("does not flag a single-transaction statement", () => {
    expect(recordsAppearColumnScrambled([
      "01/06/2026 02/06/2026 03/06/2026 04/06/2026 05/06/2026",
    ])).toBe(false);
  });
});

describe("HDFC credit-card rows", () => {
  it("reads the amount after the C currency marker", () => {
    const row = parseHDFCCreditCardRow("12/05/2026| 10:15 SWIGGY BANGALORE C 450.00");
    expect(row).toMatchObject({ type: "debit", amount: rupees(450), merchantRaw: "SWIGGY BANGALORE" });
  });

  it("treats '+ N' as a rewards count, not a credit", () => {
    const row = parseHDFCCreditCardRow("12/05/2026| 10:15 AMAZON IN C 1,299.00");
    expect(row?.type).toBe("debit");
    const withPoints = parseHDFCCreditCardRow("12/05/2026| 10:15 AMAZON IN + 25 C 1,299.00");
    expect(withPoints).toMatchObject({ type: "debit", amount: rupees(1299) });
  });

  it("treats a bare '+' before the C as a credit", () => {
    const row = parseHDFCCreditCardRow("12/05/2026| 10:15 PAYMENT + C 5,000.00");
    expect(row).toMatchObject({ type: "credit", amount: rupees(5000) });
  });

  it("carries the time into the timestamp so same-day ordering survives", () => {
    const row = parseHDFCCreditCardRow("12/05/2026| 10:15 SWIGGY C 450.00");
    const d = new Date(row!.date);
    expect([d.getHours(), d.getMinutes()]).toEqual([10, 15]);
  });
});

describe("junk filtering", () => {
  it("drops fees, charges and statement summary lines", () => {
    for (const n of [
      "Finance Charge", "Late Payment Fee", "Total Amount Due",
      "Minimum Amount Due", "Opening Balance", "Credit Limit",
    ]) {
      expect(isJunkNarration(n)).toBe(true);
    }
  });

  it("drops the inline GST rate that reads as an ₹18 transaction", () => {
    expect(isJunkNarration("IGST-VPS2617489-RATE 18.0")).toBe(true);
  });

  it("keeps real merchants", () => {
    for (const n of ["BookMyShow", "SWIGGY BANGALORE", "AMAZON PAY INDIA"]) {
      expect(isJunkNarration(n)).toBe(false);
    }
  });

  it("rejects junk rows at parse time", () => {
    expect(parseTransactionRecord("02/06/2026 Finance Charge 250.00", "ICICI")).toBeNull();
  });
});

describe("dates", () => {
  it("parses the formats the statements actually use", () => {
    const cases: Array<[string, [number, number, number]]> = [
      ["02/06/2026 X 1.00", [2026, 5, 2]],
      ["02-06-2026 X 1.00", [2026, 5, 2]],
      ["02/06/26 X 1.00", [2026, 5, 2]],
      ["02 Jun 2026 X 1.00", [2026, 5, 2]],
      ["02-Jun-2026 X 1.00", [2026, 5, 2]],
    ];
    for (const [line, [y, m, d]] of cases) {
      const parsed = extractDate(line);
      expect(parsed, line).not.toBeNull();
      const date = new Date(parsed!.date);
      expect([date.getFullYear(), date.getMonth(), date.getDate()], line).toEqual([y, m, d]);
    }
  });

  it("rejects an impossible month rather than rolling it over", () => {
    expect(extractDate("02/13/2026 X 1.00")).toBeNull();
  });

  it("consumes a trailing value-date so it is not read as an amount", () => {
    const line = "02/06/2026 03/06/2026 NEFT 25000";
    const d = extractDate(line)!;
    expect(line.slice(d.end).trim()).toBe("NEFT 25000");
  });
});

describe("account number extraction", () => {
  it("handles the masking styles each bank uses", () => {
    expect(extractAccountLast4("Card 3747XXXXXXXX2001")).toBe("2001");
    expect(extractAccountLast4("XXXX XXXX XXXX 6624")).toBe("6624");
    expect(extractAccountLast4("account ending in 8708")).toBe("8708");
    expect(extractAccountLast4("A/c XXXXXX6311")).toBe("6311");
  });
});

describe("bank detection", () => {
  it("identifies each issuer from the statement header", () => {
    expect(detectBank("HDFC Bank Credit Card Statement")).toBe("HDFC");
    expect(detectBank("ICICI Bank Sapphiro")).toBe("ICICI");
    expect(detectBank("State Bank of India")).toBe("SBI");
    expect(detectBank("The Federal Bank Ltd")).toBe("Federal");
    expect(detectBank("Some Other Lender")).toBeNull();
  });
});

describe("end to end", () => {
  const ICICI_STATEMENT = [
    "ICICI Bank Sapphiro Credit Card Statement",
    "Card Number 3747XXXXXXXX2001",
    "Statement Date : 16/08/2026",
    "Payment Due Date : 30/08/2026",
    "Total Amount Due 12,345.00",
    "Minimum Amount Due 620.00",
    "Date Details Reward Amount",
    "02/08/2026 BookMyShow Ltd",
    "MUMBAI 14 747.50",
    "03/08/2026 BBPS Payment 0 750.00 CR",
    "04/08/2026 Finance Charge 0 250.00",
    "Interest accrues until payment received in full.",
  ].join("\n");

  const result = parseStatementText(ICICI_STATEMENT);

  it("detects the bank and card", () => {
    expect(result.detectedBank).toBe("ICICI");
    expect(result.accountLast4).toBe("2001");
  });

  it("reads the statement totals", () => {
    expect(result.totalDue).toBe(rupees(12345));
    expect(result.minimumDue).toBe(rupees(620));
  });

  it("emits the two real transactions and drops the finance charge", () => {
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0]).toMatchObject({ type: "debit", amount: rupees(747.5) });
    expect(result.rows[1]).toMatchObject({ type: "credit", amount: rupees(750) });
    expect(result.columnScrambled).toBe(false);
  });

  it("keeps the raw text so a misparse can be diagnosed", () => {
    expect(result.rawText).toContain("BookMyShow");
  });

  it("reports nothing rather than guessing when the layout is scrambled", () => {
    const scrambled = [
      "HDFC Bank Statement",
      ...Array.from({ length: 5 }, () =>
        "01/06/2026 02/06/2026 03/06/2026 04/06/2026 05/06/2026 06/06/2026"),
    ].join("\n");
    const r = parseStatementText(scrambled);
    expect(r.columnScrambled).toBe(true);
    expect(r.rows).toHaveLength(0);
  });
});
