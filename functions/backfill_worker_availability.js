"use strict";

const admin = require("firebase-admin");
const {recomputeWorkerAvailability} =
  require("./recompute_worker_availability");

async function run({commit = false, pageSize = 100} = {}) {
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const counts = {scanned: 0, changed: 0, errors: 0};
  let last = null;
  while (true) {
    let query = db.collection("users").where("role", "==", "worker")
      .orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    for (const worker of page.docs) {
      counts.scanned++;
      try {
        const result = await recomputeWorkerAvailability(db, worker.id,
          new Date(), {commit});
        if (result?.changed) counts.changed++;
      } catch (_) {
        counts.errors++;
      }
    }
    last = page.docs.at(-1);
    if (page.size < pageSize) break;
  }
  return counts;
}

if (require.main === module) {
  run({commit: process.argv.includes("--commit")}).then((counts) => {
    process.stdout.write(`${JSON.stringify(counts)}\n`);
    if (counts.errors) process.exitCode = 1;
  }).catch((error) => {
    process.stderr.write(`Backfill failed: ${error.code || error.name}\n`);
    process.exitCode = 1;
  });
}

module.exports = {run};
