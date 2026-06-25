#!/usr/bin/env node

/*
 * Reconcile vacancy slot counters from accepted/hired applications.
 *
 * Dry-run:
 *   node scripts/reconcile_job_slots.js --dry-run
 *
 * Commit:
 *   node scripts/reconcile_job_slots.js --commit
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
const commit = process.argv.includes("--commit");

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

function isAcceptedStatus(status) {
  return ["accepted", "offer_accepted", "hired"].includes(
    String(status ?? "").trim().toLowerCase(),
  );
}

async function main() {
  const [jobsSnap, appsSnap] = await Promise.all([
    db.collection("jobs").get(),
    db.collection("applications").get(),
  ]);

  const acceptedByJob = new Map();
  const warnings = [];

  for (const appDoc of appsSnap.docs) {
    const data = appDoc.data();
    if (!isAcceptedStatus(data.status)) continue;
    const jobId = String(data.jobId ?? "").trim();
    if (!jobId) continue;

    const count = applicationSlotCount(data);
    if ((data.applicationType === "team" || data.type === "team") && count <= 1) {
      warnings.push(
        `WARN team application ${appDoc.id} has no clear selected/accepted worker count; using ${count}`,
      );
    }

    const current = acceptedByJob.get(jobId) || {
      filled: 0,
      applications: [],
    };
    current.filled += count;
    current.applications.push({ id: appDoc.id, count });
    acceptedByJob.set(jobId, current);
  }

  let mismatches = 0;
  let writes = 0;

  for (const jobDoc of jobsSnap.docs) {
    const data = jobDoc.data();
    const positions = Math.max(readInt(data.positions) || 1, 1);
    const actual = acceptedByJob.get(jobDoc.id) || {
      filled: 0,
      applications: [],
    };
    const expectedFilled = Math.min(actual.filled, positions);
    const expectedRemaining = Math.max(positions - expectedFilled, 0);
    const currentFilled = readInt(data.filledPositions);
    const currentRemaining = readInt(
      data.remainingPositions ?? data.openSlots ?? data.availablePositions,
    );

    const mismatch =
      currentFilled !== expectedFilled || currentRemaining !== expectedRemaining;
    if (!mismatch) continue;

    mismatches += 1;
    console.log(
      [
        commit ? "WRITE" : "DRY-RUN",
        `job=${jobDoc.id}`,
        `positions=${positions}`,
        `filled ${currentFilled}->${expectedFilled}`,
        `remaining ${currentRemaining}->${expectedRemaining}`,
        `acceptedApps=${actual.applications
          .map((item) => `${item.id}:${item.count}`)
          .join(",")}`,
      ].join(" "),
    );

    if (commit) {
      await jobDoc.ref.update({
        filledPositions: expectedFilled,
        remainingPositions: expectedRemaining,
        openSlots: expectedRemaining,
        availablePositions: expectedRemaining,
        lastSlotReconcileAt: FieldValue.serverTimestamp(),
      });
      writes += 1;
    }
  }

  for (const warning of warnings) console.log(warning);
  console.log(
    `${commit ? "COMMIT" : "DRY-RUN"} complete: ${mismatches} mismatched jobs, ${writes} updated.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
