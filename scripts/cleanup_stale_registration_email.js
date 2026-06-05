#!/usr/bin/env node

/*
 * Safe stale registration email cleanup helper.
 *
 * Dry-run by default:
 *   node scripts/cleanup_stale_registration_email.js --email user@example.com
 *
 * Mark stale Firestore indexes inactive:
 *   node scripts/cleanup_stale_registration_email.js --email user@example.com --commit
 *
 * Delete an orphan Firebase Auth user only when there is no active Firestore
 * profile and the explicit --delete-auth flag is present:
 *   node scripts/cleanup_stale_registration_email.js --email user@example.com --commit --delete-auth
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
const deleteAuth = args.includes("--delete-auth");

function argValue(prefix) {
  const arg = args.find((item) => item.startsWith(`${prefix}=`));
  return arg ? arg.slice(prefix.length + 1) : null;
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function isActiveAccount(data) {
  const status = String(data.status || "").toLowerCase();
  return (
    data.accountDeleted !== true &&
    data.deleted !== true &&
    data.anonymised !== true &&
    data.active !== false &&
    status !== "deleted"
  );
}

function logAction(message) {
  console.log(`${commit ? "WRITE" : "DRY-RUN"}: ${message}`);
}

async function queryUsers(field, value) {
  const snap = await db.collection("users").where(field, "==", value).get();
  return snap.docs;
}

async function markIndexInactive(collectionName, docId, reason) {
  const ref = db.collection(collectionName).doc(docId);
  const snap = await ref.get();
  if (!snap.exists) return;

  logAction(`mark ${collectionName}/${docId} inactive (${reason})`);
  if (commit) {
    await ref.set(
      {
        active: false,
        deleted: true,
        deletedAt: FieldValue.serverTimestamp(),
        cleanupReason: reason,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

async function main() {
  const email = normalizeEmail(argValue("--email"));
  if (!email) {
    throw new Error("--email user@example.com is required");
  }

  console.log(`Checking stale registration email: ${email}`);

  const userDocs = [
    ...(await queryUsers("email", email)),
    ...(await queryUsers("normalizedEmail", email)),
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
    if (isActiveAccount(data)) {
      activeProfiles.push(item);
    } else {
      inactiveProfiles.push(item);
    }
  }

  console.log(`Active Firestore profiles: ${activeProfiles.length}`);
  if (activeProfiles.length > 0) {
    console.log(JSON.stringify(activeProfiles, null, 2));
  }
  console.log(`Inactive/deleted Firestore profiles: ${inactiveProfiles.length}`);
  if (inactiveProfiles.length > 0) {
    console.log(JSON.stringify(inactiveProfiles, null, 2));
  }

  await markIndexInactive("emailIndex", email, "stale_registration_email");
  await markIndexInactive("registrationEmailIndex", email, "stale_registration_email");

  let authUser = null;
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

  if (authUser && activeProfiles.length === 0) {
    console.log(
      "Auth orphan detected: Firebase Auth has this email, but no active Firestore profile exists.",
    );
    if (commit && deleteAuth) {
      logAction(`delete Firebase Auth user ${authUser.uid}`);
      await admin.auth().deleteUser(authUser.uid);
    } else {
      console.log(
        "No Auth user was deleted. Add --commit --delete-auth to remove this orphan Auth record.",
      );
    }
  }

  if (!commit) {
    console.log("Dry-run complete. Add --commit to apply Firestore index cleanup.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
