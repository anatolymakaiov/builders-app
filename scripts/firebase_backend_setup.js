#!/usr/bin/env node

/*
 * Safe Firebase backend setup helper.
 *
 * Default mode is dry-run. Add --commit to write changes.
 *
 * Examples:
 *   node scripts/firebase_backend_setup.js --seed-plans
 *   node scripts/firebase_backend_setup.js --set-admin=USER_UID --commit
 *   node scripts/firebase_backend_setup.js --backfill-jobs --commit
 *   node scripts/firebase_backend_setup.js --trial-billing-all --commit
 *   node scripts/firebase_backend_setup.js --trial-billing=EMPLOYER_UID --commit
 *   node scripts/firebase_backend_setup.js --normalize-payment-requests --commit
 *   node scripts/firebase_backend_setup.js --ensure-admin-login=UID,email,password --commit
 *   node scripts/firebase_backend_setup.js --backfill-chats --commit
 *   node scripts/firebase_backend_setup.js --find-duplicate-teams
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
const Timestamp = admin.firestore.Timestamp;

const args = process.argv.slice(2);
const commit = args.includes("--commit");

function argValue(prefix) {
  const arg = args.find((item) => item.startsWith(`${prefix}=`));
  return arg ? arg.slice(prefix.length + 1) : null;
}

function logAction(message) {
  console.log(`${commit ? "WRITE" : "DRY-RUN"}: ${message}`);
}

async function maybeSet(ref, data, options = { merge: true }) {
  logAction(`set ${ref.path} ${JSON.stringify(data)}`);
  if (commit) await ref.set(data, options);
}

async function maybeUpdate(ref, data) {
  logAction(`update ${ref.path} ${JSON.stringify(data)}`);
  if (commit) await ref.update(data);
}

async function seedPlans() {
  const plans = {
    starter: {
      name: "Starter",
      price: 49,
      currency: "GBP",
      jobPosts: 3,
      durationDays: 30,
      active: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
    growth: {
      name: "Growth",
      price: 99,
      currency: "GBP",
      jobPosts: 10,
      durationDays: 30,
      active: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
    pro: {
      name: "Pro",
      price: 199,
      currency: "GBP",
      jobPosts: 25,
      durationDays: 30,
      active: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
  };

  for (const [planId, data] of Object.entries(plans)) {
    await maybeSet(db.collection("plans").doc(planId), {
      ...data,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
}

async function setAdmin(uid) {
  if (!uid) throw new Error("--set-admin requires a UID");
  await maybeSet(db.collection("users").doc(uid), {
    role: "admin",
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function backfillJobsModeration() {
  const snap = await db.collection("jobs").get();
  let count = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.moderationStatus) continue;

    count += 1;
    await maybeSet(doc.ref, {
      moderationStatus: "approved",
      moderationReason: "",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  console.log(`Jobs needing moderation backfill: ${count}`);
}

function trialBillingData() {
  const activeUntil = Timestamp.fromDate(
    new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
  );

  return {
    billing: {
      planId: "starter",
      planName: "Starter",
      paymentMode: "manual_invoice",
      directDebitEnabled: false,
      availableJobPosts: 10,
      usedJobPosts: 0,
      activeUntil,
      status: "active",
      trialActive: true,
      planRequestStatus: "pending",
      updatedAt: FieldValue.serverTimestamp(),
    },
  };
}

async function trialBillingForEmployer(uid) {
  if (!uid) throw new Error("--trial-billing requires an employer UID");
  await maybeSet(db.collection("users").doc(uid), trialBillingData());
}

async function trialBillingAllEmployers() {
  const snap = await db.collection("users").where("role", "==", "employer").get();
  let count = 0;

  for (const doc of snap.docs) {
    count += 1;
    await maybeSet(doc.ref, trialBillingData());
  }

  console.log(`Employers receiving trial billing: ${count}`);
}

async function normalizePaymentRequests() {
  const snap = await db
    .collection("payment_requests")
    .where("status", "==", "open")
    .get();
  let count = 0;

  for (const doc of snap.docs) {
    count += 1;
    await maybeUpdate(doc.ref, {
      status: "pending",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  console.log(`Payment requests needing normalization: ${count}`);
}

async function ensureAdminLogin(value) {
  if (!value) {
    throw new Error("--ensure-admin-login requires UID,email,password");
  }

  const [uid, email, password] = value.split(",");
  if (!uid || !email || !password) {
    throw new Error("--ensure-admin-login requires UID,email,password");
  }

  logAction(`upsert auth admin user ${uid} (${email})`);
  if (commit) {
    try {
      await admin.auth().updateUser(uid, {
        email,
        password,
        emailVerified: true,
        disabled: false,
      });
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
      await admin.auth().createUser({
        uid,
        email,
        password,
        emailVerified: true,
        disabled: false,
      });
    }
  }

  await setAdmin(uid);
}

async function backfillChats() {
  const snap = await db.collection("chats").get();
  let count = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const participants = new Set();

    if (Array.isArray(data.participants)) {
      for (const id of data.participants) {
        if (id) participants.add(String(id));
      }
    }
    if (Array.isArray(data.members)) {
      for (const id of data.members) {
        if (id) participants.add(String(id));
      }
    }
    if (data.workerId) participants.add(String(data.workerId));
    if (data.employerId) participants.add(String(data.employerId));

    if (participants.size === 0) continue;

    count += 1;
    await maybeSet(doc.ref, {
      participants: Array.from(participants),
      members: Array.from(participants),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  console.log(`Chats normalized: ${count}`);
}

function normalizedTeamMembers(value) {
  if (!Array.isArray(value)) return [];

  return Array.from(
    new Set(
      value
        .map((item) => {
          if (typeof item === "string") return item;
          if (item && typeof item === "object") return item.userId;
          return null;
        })
        .filter(Boolean)
        .map(String),
    ),
  ).sort();
}

async function findDuplicateTeams() {
  const snap = await db.collection("teams").get();
  const groups = new Map();

  for (const doc of snap.docs) {
    const data = doc.data();
    const ownerId = data.ownerId || data.createdBy || "";
    const name = String(data.nameLower || data.name || "").trim().toLowerCase();
    const members = normalizedTeamMembers(data.members);
    const key = [ownerId, name, members.join("|")].join("::");

    if (!ownerId || !name || members.length === 0) continue;

    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({
      id: doc.id,
      ownerId,
      name: data.name || name,
      members,
      createdAt: data.createdAt || null,
    });
  }

  const duplicates = Array.from(groups.values()).filter(
    (items) => items.length > 1,
  );

  if (duplicates.length === 0) {
    console.log("No duplicate identical teams found.");
    return;
  }

  console.log(`Duplicate identical team groups found: ${duplicates.length}`);
  for (const group of duplicates) {
    console.log(JSON.stringify(group, null, 2));
  }

  console.log(
    "No data was deleted. Review these IDs manually before deleting anything.",
  );
}

async function main() {
  if (args.includes("--seed-plans")) await seedPlans();

  const adminUid = argValue("--set-admin");
  if (adminUid) await setAdmin(adminUid);

  if (args.includes("--backfill-jobs")) await backfillJobsModeration();

  const trialBillingUid = argValue("--trial-billing");
  if (trialBillingUid) await trialBillingForEmployer(trialBillingUid);

  if (args.includes("--trial-billing-all")) await trialBillingAllEmployers();

  if (args.includes("--normalize-payment-requests")) {
    await normalizePaymentRequests();
  }

  const adminLogin = argValue("--ensure-admin-login");
  if (adminLogin) await ensureAdminLogin(adminLogin);

  if (args.includes("--backfill-chats")) await backfillChats();

  if (args.includes("--find-duplicate-teams")) await findDuplicateTeams();

  if (!commit) {
    console.log("Dry-run complete. Add --commit to apply these changes.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
