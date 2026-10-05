"use strict";

const normalizePhone = (value) => {
  let digits = value.trim().replace(/[^0-9+]/g, "");
  if (digits.startsWith("00")) digits = `+${digits.slice(2)}`;
  if (digits.startsWith("+")) return digits;
  if (digits.startsWith("44")) return `+${digits}`;
  if (digits.startsWith("0") && digits.length > 1) {
    return `+44${digits.slice(1)}`;
  }
  return digits;
};

const activeAccount = (data) => data && data.accountDeleted !== true &&
  data.deleted !== true && data.anonymised !== true &&
  data.active !== false && String(data.status || "").toLowerCase() !== "deleted";

const identityQueries = (kind, raw) => {
  const value = raw.trim();
  if (kind === "email") {
    const email = value.toLowerCase();
    return {
      indexCollections: ["emailIndex", "registrationEmailIndex"],
      indexId: email,
      fields: [["email", email], ["normalizedEmail", email]],
    };
  }
  const phone = normalizePhone(value);
  return {
    indexCollections: ["phoneIndex", "registrationPhoneIndex"],
    indexId: phone,
    fields: [
      ["normalizedPhone", phone], ["phone", value], ["phones", value, true],
    ],
  };
};

const indexUid = (data) => ["uid", "userId", "ownerId", "profileId"]
  .map((key) => data[key]).find((value) => typeof value === "string" && value.trim()) || "";

async function identityInUse(db, {kind, value, currentUid}) {
  const query = identityQueries(kind, value);
  if (!query.indexId) return false;
  for (const collection of query.indexCollections) {
    const index = await db.collection(collection).doc(query.indexId).get();
    if (!index.exists || !activeAccount(index.data())) continue;
    const uid = indexUid(index.data());
    if (!uid || uid === currentUid) continue;
    const user = await db.collection("users").doc(uid).get();
    if (user.exists && activeAccount(user.data())) return true;
  }
  // Pre-auth registration only had access to exact public index documents.
  // Do not turn the fallback user queries into a broader account oracle.
  if (!currentUid) return false;
  for (const [field, target, array] of query.fields) {
    if (!target) continue;
    const users = await db.collection("users")
      .where(field, array ? "array-contains" : "==", target).limit(10).get();
    if (users.docs.some((user) => user.id !== currentUid &&
      activeAccount(user.data()))) return true;
  }
  return false;
}

module.exports = {identityInUse, normalizePhone, activeAccount, identityQueries};
