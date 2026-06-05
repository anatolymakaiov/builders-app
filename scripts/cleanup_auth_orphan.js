#!/usr/bin/env node

/*
 * Firebase Auth orphan cleanup helper.
 *
 * Dry-run by default:
 *   node scripts/cleanup_auth_orphan.js --email test@example.com
 *   node scripts/cleanup_auth_orphan.js --email=test@example.com --dry-run
 *
 * Delete orphan Auth user and mark stale identity indexes inactive:
 *   node scripts/cleanup_auth_orphan.js --email test@example.com --commit
 *
 * This script deletes Auth only when no active Firestore profile/index exists.
 */

const path = require("path");
const { createRequire } = require("module");

let admin;

try {
  const functionsRequire = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  admin = functionsRequire("firebase-admin");
} catch (_) {
  console.error(
    [
      "Missing firebase-admin dependency.",
      "Before running this script, install function dependencies:",
      "  cd functions && npm install",
      "Then run this script from the project root again.",
    ].join("\n"),
  );
  process.exit(1);
}

admin.initializeApp({
  projectId: "builder-jobs-app",
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const args = process.argv.slice(2);

function hasFlag(name) {
  return args.includes(name);
}

function argValue(name) {
  const equalArg = args.find((item) => item.startsWith(`${name}=`));
  if (equalArg) return equalArg.slice(name.length + 1);

  const index = args.indexOf(name);
  if (index === -1) return null;

  const value = args[index + 1];
  if (!value || value.startsWith("--")) return null;
  return value;
}

const commit = hasFlag("--commit");
const dryRun = hasFlag("--dry-run") || !commit;

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizePhone(value) {
  let digits = String(value || "").trim().replace(/[^0-9+]/g, "");
  if (digits.startsWith("00")) digits = `+${digits.slice(2)}`;
  if (digits.startsWith("+")) return digits;
  if (digits.startsWith("44")) return `+${digits}`;
  if (digits.startsWith("0") && digits.length > 1) {
    return `+44${digits.slice(1)}`;
  }
  return digits;
}

function isActiveAccount(data = {}) {
  const status = String(data.status || "").toLowerCase();
  return (
    data.accountDeleted !== true &&
    data.deleted !== true &&
    data.anonymised !== true &&
    data.active !== false &&
    status !== "deleted"
  );
}

function uidFromIndex(data = {}) {
  for (const key of ["uid", "userId", "ownerId", "profileId"]) {
    if (data[key]) return String(data[key]).trim();
  }
  return null;
}

function logAction(message) {
  console.log(`${commit ? "WRITE" : "DRY-RUN"}: ${message}`);
}

function printJson(label, value) {
  console.log(`${label}:`);
  console.log(JSON.stringify(value, null, 2));
}

async function queryCollection(collectionName, field, value) {
  if (!value) return [];
  const snap = await db.collection(collectionName).where(field, "==", value).get();
  return snap.docs.map((doc) => ({
    path: `${collectionName}/${doc.id}`,
    id: doc.id,
    collectionName,
    data: doc.data() || {},
  }));
}

async function collectProfiles({ email, rawPhone, normalizedPhone }) {
  const collections = ["users", "workers", "employers", "companies"];
  const fields = [
    ["email", email],
    ["normalizedEmail", email],
    ["billingEmail", email],
    ["phone", rawPhone],
    ["normalizedPhone", normalizedPhone],
  ];
  const results = [];

  for (const collectionName of collections) {
    for (const [field, value] of fields) {
      const docs = await queryCollection(collectionName, field, value);
      for (const doc of docs) {
        results.push({ ...doc, matchedField: field });
      }
    }
  }

  return Array.from(new Map(results.map((item) => [item.path, item])).values());
}

async function inspectArchiveCollections({ email, rawPhone, normalizedPhone }) {
  const collections = ["deletedUsers", "archivedUsers", "drafts"];
  const fields = [
    ["email", email],
    ["normalizedEmail", email],
    ["phone", rawPhone],
    ["normalizedPhone", normalizedPhone],
  ];
  const results = [];

  for (const collectionName of collections) {
    for (const [field, value] of fields) {
      try {
        const docs = await queryCollection(collectionName, field, value);
        for (const doc of docs) {
          results.push({ ...doc, matchedField: field });
        }
      } catch (error) {
        if (error.code !== 5 && error.code !== "not-found") {
          console.log(`Skipped ${collectionName}.${field}: ${error.message}`);
        }
      }
    }
  }

  return Array.from(new Map(results.map((item) => [item.path, item])).values());
}

async function markIndexInactive(collectionName, docId, reason, previousUserId) {
  if (!docId) return;
  const ref = db.collection(collectionName).doc(docId);
  const snap = await ref.get();
  if (!snap.exists) return;

  logAction(`mark ${collectionName}/${docId} inactive (${reason})`);
  if (commit) {
    await ref.set(
      {
        active: false,
        deleted: true,
        stale: true,
        cleanupReason: reason,
        ...(previousUserId ? { previousUserId } : {}),
        deletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function inspectIndexes(collections, identity) {
  const activeIndexProfiles = [];
  const staleIndexes = [];

  for (const collectionName of collections) {
    if (!identity) continue;
    const ref = db.collection(collectionName).doc(identity);
    const snap = await ref.get();
    if (!snap.exists) continue;

    const data = snap.data() || {};
    const uid = uidFromIndex(data);
    if (!isActiveAccount(data)) {
      staleIndexes.push({
        collectionName,
        id: identity,
        uid,
        reason: "inactive_index",
        data,
      });
      continue;
    }
    if (!uid) {
      staleIndexes.push({
        collectionName,
        id: identity,
        uid,
        reason: "missing_uid",
        data,
      });
      continue;
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    if (!userSnap.exists || !userData) {
      staleIndexes.push({
        collectionName,
        id: identity,
        uid,
        reason: "missing_user",
        data,
      });
      continue;
    }
    if (!isActiveAccount(userData)) {
      staleIndexes.push({
        collectionName,
        id: identity,
        uid,
        reason: "deleted_user",
        data: userData,
      });
      continue;
    }

    activeIndexProfiles.push({
      collectionName,
      id: identity,
      uid,
      active: userData.active,
      deleted: userData.deleted,
      accountDeleted: userData.accountDeleted,
      status: userData.status || null,
    });
  }

  return { activeIndexProfiles, staleIndexes };
}

async function getAuthUserByEmail(email) {
  if (!email) return null;
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

async function getAuthUserByPhone(phone) {
  if (!phone) return null;
  try {
    return await admin.auth().getUserByPhoneNumber(phone);
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

async function main() {
  const email = normalizeEmail(argValue("--email"));
  const rawPhone = String(argValue("--phone") || "").trim();
  const normalizedPhone = normalizePhone(rawPhone);

  console.log("Parsed arguments:");
  console.log(`email: ${email || "null"}`);
  console.log(`phone: ${normalizedPhone || "null"}`);
  console.log(`mode: ${commit ? "commit" : "dry-run"}`);

  if (!email && !normalizedPhone) {
    throw new Error("--email test@example.com or --phone '+447...' is required");
  }

  const profiles = await collectProfiles({ email, rawPhone, normalizedPhone });
  const archiveDocs = await inspectArchiveCollections({
    email,
    rawPhone,
    normalizedPhone,
  });
  const activeProfiles = [];
  const inactiveProfiles = [];

  for (const profile of profiles) {
    const item = {
      path: profile.path,
      matchedField: profile.matchedField,
      role: profile.data.role || null,
      uid: profile.data.uid || profile.data.userId || profile.id,
      active: profile.data.active,
      deleted: profile.data.deleted,
      accountDeleted: profile.data.accountDeleted,
      anonymised: profile.data.anonymised,
      status: profile.data.status || null,
    };
    if (isActiveAccount(profile.data)) activeProfiles.push(item);
    else inactiveProfiles.push(item);
  }

  const emailIndexState = await inspectIndexes(
    ["emailIndex", "registrationEmailIndex"],
    email,
  );
  const phoneIndexState = await inspectIndexes(
    ["phoneIndex", "registrationPhoneIndex"],
    normalizedPhone,
  );

  const activeIndexProfiles = [
    ...emailIndexState.activeIndexProfiles,
    ...phoneIndexState.activeIndexProfiles,
  ];
  const staleIndexes = [
    ...emailIndexState.staleIndexes,
    ...phoneIndexState.staleIndexes,
  ];

  const emailAuthUser = await getAuthUserByEmail(email);
  const phoneAuthUser = await getAuthUserByPhone(normalizedPhone);
  const authUsers = Array.from(
    new Map(
      [emailAuthUser, phoneAuthUser]
        .filter(Boolean)
        .map((user) => [user.uid, user]),
    ).values(),
  );

  console.log(`Firebase Auth users found: ${authUsers.length}`);
  for (const user of authUsers) {
    console.log(
      `Auth user: uid=${user.uid} email=${user.email || "null"} phone=${
        user.phoneNumber || "null"
      }`,
    );
  }

  console.log(`Active Firestore profiles: ${activeProfiles.length}`);
  if (activeProfiles.length > 0) printJson("Active profile details", activeProfiles);

  console.log(`Inactive/deleted Firestore profiles: ${inactiveProfiles.length}`);
  if (inactiveProfiles.length > 0) {
    printJson("Inactive/deleted profile details", inactiveProfiles);
  }

  console.log(`Archive/deleted docs found: ${archiveDocs.length}`);
  if (archiveDocs.length > 0) {
    printJson(
      "Archive/deleted docs",
      archiveDocs.map((doc) => ({
        path: doc.path,
        matchedField: doc.matchedField,
        active: doc.data.active,
        deleted: doc.data.deleted,
        status: doc.data.status || null,
      })),
    );
  }

  console.log(`Active index profiles: ${activeIndexProfiles.length}`);
  if (activeIndexProfiles.length > 0) {
    printJson("Active index details", activeIndexProfiles);
  }

  if (activeProfiles.length > 0 || activeIndexProfiles.length > 0) {
    console.log("Decision: active account/index exists. No Auth cleanup performed.");
    return;
  }

  for (const index of staleIndexes) {
    await markIndexInactive(index.collectionName, index.id, index.reason, index.uid);
  }

  for (const identity of [email, normalizedPhone]) {
    if (!identity) continue;
    for (const collectionName of [
      "emailIndex",
      "registrationEmailIndex",
      "phoneIndex",
      "registrationPhoneIndex",
    ]) {
      await markIndexInactive(collectionName, identity, "stale_orphan_cleanup");
    }
  }

  if (authUsers.length === 0) {
    console.log("Decision: no active profile and no Auth user. Identity is reusable.");
  } else {
    console.log(
      "Decision: AUTH ORPHAN. No active Firestore profile/index references this identity.",
    );
  }

  for (const user of authUsers) {
    logAction(`delete Firebase Auth user ${user.uid}`);
    if (commit) {
      await admin.auth().deleteUser(user.uid);
    }
  }

  if (dryRun) {
    console.log("Dry-run complete. Add --commit to apply cleanup.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    if (
      String(error.message || "").includes("Could not load the default credentials")
    ) {
      console.error(
        [
          "Could not load Firebase Admin credentials.",
          "Run this script with GOOGLE_APPLICATION_CREDENTIALS pointing to your service account JSON.",
          "Example:",
          "  GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/cleanup_auth_orphan.js --email test@example.com --commit",
        ].join("\n"),
      );
      process.exit(1);
    }
    console.error(error);
    process.exit(1);
  });
