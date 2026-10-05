"use strict";

const {isDeepStrictEqual} = require("node:util");
const admin = require("firebase-admin");
const {publicProfile, workerDiscovery} = require("./profile_projections");

async function run({commit = false, pageSize = 200} = {}) {
  if (!admin.apps.length) admin.initializeApp();
  const db = admin.firestore();
  const counts = {scanned: 0, publicCreated: 0, discoveryCreated: 0,
    unchanged: 0, skipped: 0, errors: 0};
  let last = null;
  while (true) {
    let query = db.collection("users")
      .orderBy(admin.firestore.FieldPath.documentId()).limit(pageSize);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    const writes = [];
    for (const user of page.docs) {
      counts.scanned++;
      try {
        const projections = [
          ["public_profiles", publicProfile(user.id, user.data()), "publicCreated"],
          ["worker_discovery", workerDiscovery(user.id, user.data()), "discoveryCreated"],
        ];
        for (const [collection, value, counter] of projections) {
          if (!value) {
            counts.skipped++;
            continue;
          }
          const ref = db.collection(collection).doc(user.id);
          const existing = await ref.get();
          if (existing.exists && isDeepStrictEqual(existing.data(), value)) {
            counts.unchanged++;
            continue;
          }
          counts[counter]++;
          if (commit) writes.push({ref, value});
        }
      } catch (_) {
        counts.errors++;
      }
    }
    if (commit && writes.length) {
      for (let offset = 0; offset < writes.length; offset += 400) {
        const batch = db.batch();
        for (const {ref, value} of writes.slice(offset, offset + 400)) {
          batch.set(ref, value);
        }
        await batch.commit();
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
