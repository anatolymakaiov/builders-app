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
    "billing.planId": "starter",
    "billing.paymentMode": "manual_invoice",
    "billing.directDebitEnabled": false,
    "billing.availableJobPosts": 10,
    "billing.usedJobPosts": 0,
    "billing.activeUntil": activeUntil,
    "billing.status": "active",
    "billing.updatedAt": FieldValue.serverTimestamp(),
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
