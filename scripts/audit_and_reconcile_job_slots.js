#!/usr/bin/env node

/*
 * Audit and optionally reconcile vacancy slot counters from accepted/hired
 * offers and applications.
 *
 * Dry-run:
 *   node scripts/audit_and_reconcile_job_slots.js --job <jobId> --dry-run
 *
 * Commit:
 *   node scripts/audit_and_reconcile_job_slots.js --job <jobId> --commit
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
const dryRun = args.includes("--dry-run") || !commit;
const jobArgIndex = args.indexOf("--job");
const targetJobId =
  jobArgIndex >= 0 && args[jobArgIndex + 1] ? args[jobArgIndex + 1] : "";

if (!targetJobId) {
  console.error("Usage: node scripts/audit_and_reconcile_job_slots.js --job <jobId> [--dry-run|--commit]");
  process.exit(1);
}

function readInt(value) {
  if (typeof value === "number") return Math.trunc(value);
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function uniqueCount(value) {
  return Array.isArray(value)
    ? new Set(value.map((item) => String(item)).filter(Boolean)).size
    : 0;
}

function isAcceptedStatus(status) {
  return ["accepted", "offer_accepted", "hired", "offeraccepted", "confirmed"].includes(
    String(status ?? "").trim().toLowerCase().replace(/[_\s-]/g, ""),
  );
}

function applicationSlotCount(data) {
  const offer = data.offer && typeof data.offer === "object" ? data.offer : {};
  const selectedCount = uniqueCount(offer.selectedWorkerIds);
  if (selectedCount > 0) return selectedCount;

  const acceptedCount =
    uniqueCount(offer.acceptedWorkerIds) ||
    uniqueCount(data.acceptedWorkerIds) ||
    uniqueCount(data.selectedWorkerIds);
  if (acceptedCount > 0) return acceptedCount;

  const workersCount = readInt(data.workersCount);
  if (workersCount > 0) return workersCount;

  const membersCount = uniqueCount(data.members);
  if (membersCount > 0) return membersCount;

  return 1;
}

async function collectAcceptedDocs(jobId) {
  const docs = [];
  const seen = new Set();

  async function addSnapshot(label, snap) {
    for (const doc of snap.docs) {
      const key = `${doc.ref.path}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const data = doc.data();
      if (!isAcceptedStatus(data.status ?? data.offerStatus)) continue;
      docs.push({
        id: doc.id,
        path: doc.ref.path,
        ref: doc.ref,
        collection: label,
        data,
        count: applicationSlotCount(data),
      });
    }
  }

  await addSnapshot(
    "applications",
    await db.collection("applications").where("jobId", "==", jobId).get(),
  );
  await addSnapshot(
    "jobApplications",
    await db.collection("jobApplications").where("jobId", "==", jobId).get(),
  );
  await addSnapshot(
    "teamApplications",
    await db.collection("teamApplications").where("jobId", "==", jobId).get(),
  );
  await addSnapshot(
    "offers",
    await db.collection("offers").where("jobId", "==", jobId).get(),
  );
  await addSnapshot(
    `jobs/${jobId}/applications`,
    await db.collection("jobs").doc(jobId).collection("applications").get(),
  );
  await addSnapshot(
    `jobs/${jobId}/offers`,
    await db.collection("jobs").doc(jobId).collection("offers").get(),
  );

  return docs;
}

async function main() {
  const jobRef = db.collection("jobs").doc(targetJobId);
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) {
    console.log(`JOB SLOT AUDIT jobId=${targetJobId} jobPath=jobs/${targetJobId} exists=false`);
    return;
  }

  const job = jobSnap.data();
  const totalSlots = Math.max(readInt(job.positions) || 1, 1);
  const storedFilled = readInt(job.filledPositions ?? job.acceptedSlotTotal ?? job.hiredCount);
  const storedAvailable = readInt(
    job.remainingPositions ??
      job.openSlots ??
      job.availableSlots ??
      job.availablePositions ??
      job.positionsAvailable,
  );
  const acceptedDocs = await collectAcceptedDocs(targetJobId);
  const acceptedWorkerCount = acceptedDocs.reduce((sum, doc) => sum + doc.count, 0);
  const expectedFilled = Math.min(acceptedWorkerCount, totalSlots);
  const expectedAvailableSlots = Math.max(totalSlots - expectedFilled, 0);
  const mismatch =
    storedFilled !== expectedFilled || storedAvailable !== expectedAvailableSlots;

  console.log(
    [
      "JOB SLOT AUDIT",
      `jobId=${targetJobId}`,
      `jobPath=jobs/${targetJobId}`,
      "totalSlotsField=positions",
      `totalSlotsValue=${totalSlots}`,
      "availableSlotsField=remainingPositions/openSlots/availableSlots",
      `availableSlotsValue=${storedAvailable}`,
      `storedFilledSlots=${storedFilled}`,
      `acceptedOfferDocsFound=${acceptedDocs.length}`,
      `acceptedWorkerCount=${acceptedWorkerCount}`,
      `expectedAvailableSlots=${expectedAvailableSlots}`,
      `mismatch=${mismatch}`,
      `mode=${commit ? "commit" : dryRun ? "dry-run" : "audit"}`,
    ].join(" "),
  );

  for (const doc of acceptedDocs) {
    console.log(
      [
        "ACCEPTED_DOC",
        `path=${doc.path}`,
        `collection=${doc.collection}`,
        `status=${doc.data.status ?? doc.data.offerStatus ?? ""}`,
        `count=${doc.count}`,
        `slotDecrementApplied=${doc.data.slotDecrementApplied === true}`,
      ].join(" "),
    );
  }

  if (!commit || !mismatch) return;

  const batch = db.batch();
  batch.update(jobRef, {
    filledPositions: expectedFilled,
    remainingPositions: expectedAvailableSlots,
    openSlots: expectedAvailableSlots,
    availablePositions: expectedAvailableSlots,
    availableSlots: expectedAvailableSlots,
    remainingSlots: expectedAvailableSlots,
    positionsAvailable: expectedAvailableSlots,
    hiredCount: expectedFilled,
    acceptedSlotTotal: expectedFilled,
    slotDecrementApplicationIds: acceptedDocs.map((doc) => doc.id),
    lastSlotAuditReconcileAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  for (const doc of acceptedDocs) {
    batch.update(doc.ref, {
      acceptedSlotCount: doc.count,
      slotDecrementApplied: true,
      slotDecrementJobId: targetJobId,
      slotDecrementReconciledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  console.log(
    `JOB SLOT AUDIT COMMIT COMPLETE jobId=${targetJobId} expectedAvailableSlots=${expectedAvailableSlots}`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
