#!/usr/bin/env node

/*
 * Firebase Auth orphan cleanup helper.
 *
 * Dry-run by default:
 *   node scripts/cleanup_auth_orphan.js --email test@example.com
 *
 * Delete orphan Auth user and mark stale identity indexes inactive:
 *   node scripts/cleanup_auth_orphan.js --email test@example.com --commit
 *
 * This script deletes Auth only when no active Firestore user/profile exists
 * for the email. It does not remove active accounts.
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
const commit = args.includes("--commit");

function argValue(prefix) {
  const arg = args.find((item) => item.startsWith(`${prefix}=`));
  return arg ? arg.slice(prefix.length + 1) : null;
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizePhone(value) {
  let digits = String(value || "").trim().replace(/[^0-9+]/g, "");
  if (digits.startsWith("00")) digits = `+${digits.slice(2)}`;
  if (digits.startsWith("+")) return digits;
  if (digits.startsWith("44")) return `+${digits}`;
  if (digits.startsWith("0") && digits.length > 1) return `+44${digits.slice(1)}`;
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

async function queryUsers(field, value) {
  if (!value) return [];
  const snap = await db.collection("users").where(field, "==", value).get();
  return snap.docs;
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
      staleIndexes.push({ collectionName, id: identity, uid, reason: "inactive_index" });
      continue;
    }
    if (!uid) {
      staleIndexes.push({ collectionName, id: identity, uid, reason: "missing_uid" });
      continue;
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data();
    if (!userSnap.exists || !userData) {
      staleIndexes.push({ collectionName, id: identity, uid, reason: "missing_user" });
      continue;
    }
    if (!isActiveAccount(userData)) {
      staleIndexes.push({ collectionName, id: identity, uid, reason: "deleted_user" });
      continue;
    }

    activeIndexProfiles.push({ collectionName, id: identity, uid });
  }

  return { activeIndexProfiles, staleIndexes };
}

async function main() {
  const email = normalizeEmail(argValue("--email"));
  const phone = argValue("--phone") || "";
  const normalizedPhone = normalizePhone(phone);

  if (!email && !normalizedPhone) {
    throw new Error("--email test@example.com or --phone '+447...' is required");
  }

  console.log(`Checking identity orphan: ${email || normalizedPhone}`);

  const userDocs = [
    ...(await queryUsers("email", email)),
    ...(await queryUsers("normalizedEmail", email)),
    ...(await queryUsers("phone", phone)),
    ...(await queryUsers("normalizedPhone", normalizedPhone)),
  ];
  const uniqueUserDocs = Array.from(
    new Map(userDocs.map((doc) => [doc.id, doc])).values(),
  );

  const activeProfiles = [];
  const inactiveProfiles = [];
  for (const doc of uniqueUserDocs) {
    const data = doc.data();
    const item = {
      id: doc.id,
      role: data.role || null,
      active: data.active,
      deleted: data.deleted,
      accountDeleted: data.accountDeleted,
      anonymised: data.anonymised,
      status: data.status || null,
    };
    if (isActiveAccount(data)) activeProfiles.push(item);
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

  console.log(`Active Firestore profiles: ${activeProfiles.length}`);
  if (activeProfiles.length > 0) {
    console.log(JSON.stringify(activeProfiles, null, 2));
  }
  console.log(`Inactive/deleted Firestore profiles: ${inactiveProfiles.length}`);
  if (inactiveProfiles.length > 0) {
    console.log(JSON.stringify(inactiveProfiles, null, 2));
  }
  console.log(
    `Active index profiles: ${
      emailIndexState.activeIndexProfiles.length +
      phoneIndexState.activeIndexProfiles.length
    }`,
  );

  if (
    activeProfiles.length > 0 ||
    emailIndexState.activeIndexProfiles.length > 0 ||
    phoneIndexState.activeIndexProfiles.length > 0
  ) {
    console.log("Active account/index exists. No Auth cleanup will be performed.");
    return;
  }

  for (const index of [...emailIndexState.staleIndexes, ...phoneIndexState.staleIndexes]) {
    await markIndexInactive(index.collectionName, index.id, index.reason, index.uid);
  }

  let authUser = null;
  if (email) {
    try {
      authUser = await admin.auth().getUserByEmail(email);
      console.log(`Firebase Auth user exists: ${authUser.uid}`);
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        console.log("Firebase Auth user: not found");
      } else {
        throw error;
      }
    }
  }

  if (authUser) {
    console.log(
      "Firebase Auth orphan detected. No active Firestore profile/index references this email.",
    );
    logAction(`delete Firebase Auth user ${authUser.uid}`);
    if (commit) {
      await admin.auth().deleteUser(authUser.uid);
    }
  }

  if (!commit) {
    console.log("Dry-run complete. Add --commit to apply cleanup.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
