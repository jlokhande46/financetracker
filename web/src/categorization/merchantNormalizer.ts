/**
 * Merchant name cleanup, ported from Infrastructure/Categorization/MerchantNormalizer.swift.
 *
 * Pipeline: strip bank prefixes -> strip VPA/ref tails -> clean separators and
 * junk words -> strip corporate suffixes -> alias-map lookup -> title case.
 *
 * User-defined display rules are applied by the caller BEFORE this runs (the
 * Swift version reached into a singleton store from inside normalize; here the
 * dependency is passed in, which keeps this function pure and testable).
 */

const ALIAS_MAP: Record<string, string> = {
  // Amazon — ASSPL is Amazon Seller Services Pvt Ltd (marketplace)
  AMZNPAY: "Amazon Pay", "AMAZON PAY": "Amazon Pay", AMAZN: "Amazon",
  AMAZON: "Amazon", AMZN: "Amazon", ASSPL: "Amazon", ASPL: "Amazon",
  // Food delivery
  SWGY: "Swiggy", SWIGGY: "Swiggy", "SWIGGY ORDER": "Swiggy",
  "CAS*SWIGGY": "Swiggy", "CAS SWIGGY": "Swiggy",
  ZOMTO: "Zomato", ZOMATO: "Zomato",
  BLINKIT: "Blinkit", GROFERS: "Blinkit",
  BIGBASKET: "BigBasket", BIGBZR: "BigBasket",
  ZEPTO: "Zepto", "ZEPTO MARKETPLACE": "Zepto", "ZEPTO MARKETPLACE PRIV": "Zepto",
  ZEPTOMARKETPLACEPRIV: "Zepto", ZEPTOMARKETPLACE: "Zepto",
  DUNZO: "Dunzo",
  // Dining
  DISTRICTDININGCYBS: "District Dining", "DISTRICT DINING": "District Dining",
  // Entertainment / ticketing
  BOOKMYSHOW: "BookMyShow", "PAY*BOOKMYSHOW": "BookMyShow",
  PAYBOOKMYSHOW: "BookMyShow",
  NETFLIX: "Netflix", "NETFLIX.COM": "Netflix",
  SPOTIFY: "Spotify", "SPOTIFY AB": "Spotify",
  HOTSTAR: "Disney+ Hotstar", "DISNEY HOTSTAR": "Disney+ Hotstar",
  "PRIME VIDEO": "Amazon Prime", "AMAZON PRIME": "Amazon Prime",
  "YOUTUBE PREMIUM": "YouTube Premium",
  "SONY LIV": "SonyLIV", SONYLIV: "SonyLIV",
  ZEE5: "ZEE5", VOOT: "VOOT",
  // Travel
  AGODAPANYPTELTD: "Agoda", AGODA: "Agoda",
  MAKEMYTRIP: "MakeMyTrip", MMT: "MakeMyTrip",
  GOIBIBO: "Goibibo", CLEARTRIP: "Cleartrip", YATRA: "Yatra",
  // Transport
  UBER: "Uber", "UBER INDIA": "Uber",
  OLA: "Ola", "ANI TECHNOLOGIES": "Ola", RAPIDO: "Rapido",
  DMRC: "Delhi Metro", "BANGALORE METRO": "Metro",
  BMTC: "BMTC Bus", IRCTC: "IRCTC", "IRCTC RAIL": "IRCTC",
  // Fuel
  BPCL: "BPCL Fuel", IOC: "Indian Oil", IOCL: "Indian Oil",
  HPCL: "HPCL Fuel", "RELIANCE PETRO": "Reliance Fuel",
  // Shopping
  MYNTRA: "Myntra", FLIPKART: "Flipkart", FK: "Flipkart",
  MEESHO: "Meesho", NYKAA: "Nykaa", AJIO: "AJIO", SNAPDEAL: "Snapdeal",
  // Telecom
  AIRTEL: "Airtel", "BHARTI AIRTEL": "Airtel",
  "RELIANCE JIO": "Jio", JIO: "Jio", JIOMART: "JioMart",
  VODAFONE: "Vi", "IDEA CELLULAR": "Vi", BSNL: "BSNL",
  // Utilities
  "TATA POWER": "Tata Power", BESCOM: "BESCOM",
  "MAHANAGAR GAS": "MGL Gas", IGL: "IGL Gas",
  JUSPAY: "Juspay", "BILL DESK": "BillDesk",
  // Finance
  "HDFC BANK": "HDFC Bank", "ICICI BANK": "ICICI Bank",
  SBI: "SBI", "AXIS BANK": "Axis Bank",
  ZERODHA: "Zerodha", GROWW: "Groww",
  PAYTM: "Paytm", PHONEPE: "PhonePe", GPAY: "Google Pay",
  // Health
  APOLLO: "Apollo Pharmacy", MEDPLUS: "MedPlus",
  PHARMEASY: "PharmEasy", "1MG": "1mg",
};

// Longest keys first so "AMAZON PAY" wins over "AMAZON".
const ALIAS_KEYS_BY_LENGTH = Object.keys(ALIAS_MAP).sort((a, b) => b.length - a.length);

const JUNK_WORDS = ["POS", "INR", "TXN", "PURCHASE", "TRANSACTION", "PAYMENT", "DEBIT"];

const BANK_PREFIXES = [
  "UPI-", "UPI/", "UPI ", "POS-", "POS ", "POS/", "BIL/", "ECS/",
  "NEFT-", "NEFT/", "RTGS-", "RTGS/", "IMPS-", "IMPS/", "ATM-", "ATM ",
  "PAY*", "PAY-", "CAS*", "CAS-", "CCD*",
];

const CORP_SUFFIXES = [
  " PVT LTD", " PRIVATE LIMITED", " PVT-LTD", " PVT", " LIMITED", " LTD",
  " INDIA", " IN", " CO", " CORP", " CORPORATION", " PRIV", " PVT-",
];

function stripPrefixes(raw: string): string {
  const upper = raw.toUpperCase();
  for (const prefix of BANK_PREFIXES) {
    if (upper.startsWith(prefix)) return raw.slice(prefix.length).trim();
  }
  return raw;
}

/** Strip VPA handles (anything after @) and trailing UPI ref tokens. */
function stripVPAAndRefs(raw: string): string {
  let result = raw;
  const at = result.indexOf("@");
  if (at !== -1) result = result.slice(0, at);
  result = result.replace(
    /\s*-(?:pvt|ltd|merchant|vpa|upi|ref|txn|[a-z0-9]{6,})(?:-[a-z0-9]+)*\s*$/i,
    "",
  );
  return result.trim();
}

function stripCorpSuffixes(raw: string): string {
  let result = raw;
  let changed = true;
  while (changed) {
    changed = false;
    const upper = result.toUpperCase();
    for (const suffix of CORP_SUFFIXES) {
      if (upper.endsWith(suffix)) {
        result = result.slice(0, result.length - suffix.length).trim();
        changed = true;
        break;
      }
    }
  }
  return result;
}

function cleanup(raw: string): string {
  let result = raw;
  // Long digit runs are UPI/ref numbers, not part of the name.
  result = result.replace(/\d{6,}/g, "");
  result = result.replace(/[/\\|*#_]/g, " ");
  for (const word of JUNK_WORDS) {
    result = result.replace(new RegExp(`\\b${word}\\b`, "gi"), "");
  }
  result = result.replace(/[\s-]{2,}/g, " ");
  return result.replace(/^[\s-]+|[\s-]+$/g, "");
}

/** Title-case, truncated to the first 3 meaningful words (SMS-style names). */
function shortTitleCase(str: string): string {
  return str
    .split(/[\s-]+/)
    .filter(Boolean)
    .slice(0, 3)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(" ");
}

/**
 * @param learnedDisplayName optional user rule; wins over everything else, so a
 *        merchant the user renamed once stays renamed on every future import.
 */
export function normalizeMerchant(raw: string, learnedDisplayName?: string | null): string {
  if (learnedDisplayName) return learnedDisplayName;

  let cleaned = stripPrefixes(raw.trim());
  cleaned = stripVPAAndRefs(cleaned);
  cleaned = cleanup(cleaned);
  cleaned = stripCorpSuffixes(cleaned);

  const upper = cleaned.toUpperCase();
  const exact = ALIAS_MAP[upper];
  if (exact) return exact;

  for (const key of ALIAS_KEYS_BY_LENGTH) {
    if (upper.includes(key)) return ALIAS_MAP[key]!;
  }
  return shortTitleCase(cleaned);
}

/**
 * Normalised lookup key for merchant rules — aggressive on purpose so a rule
 * saved for "UPI-SWIGGY-...-123456789@oksbi" matches any future "Swiggy *".
 */
export function merchantRuleKey(raw: string): string {
  let s = raw.toLowerCase();
  s = s.replace(/^(?:upi[-/ ]|pos[-/ ]|neft[-/ ]|imps[-/ ]|rtgs[-/ ]|pay[-*]|cas[-*])/, "");
  const at = s.indexOf("@");
  if (at !== -1) s = s.slice(0, at);
  s = s.replace(/[^a-z0-9 ]/g, " ");
  s = s.replace(/\b\d{5,}\b/g, " ");
  return s.replace(/\s+/g, " ").trim();
}
