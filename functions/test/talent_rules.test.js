"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("employer candidate discovery and private Talent Pool", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const env = await initializeTestEnvironment({
    projectId: "stroyka-talent-rules",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/employerA").set({role: "employer",
        companyName: "A", profileComplete: true});
      await db.doc("users/employerB").set({role: "employer",
        companyName: "B", profileComplete: true});
      await db.doc("users/worker").set({role: "worker",
        name: "Worker", profileComplete: true, phone: "+447700900123"});
      await db.doc("worker_discovery/worker").set({workerId: "worker",
        discoveryVisible: true, tradeIds: ["dryliner"],
        displayNameShort: "Worker W."});
      await db.doc("worker_discovery/hidden").set({workerId: "hidden",
        discoveryVisible: false, tradeIds: ["dryliner"]});
    });
    const a = env.authenticatedContext("employerA").firestore();
    const b = env.authenticatedContext("employerB").firestore();
    const worker = env.authenticatedContext("worker").firestore();
    const guest = env.unauthenticatedContext().firestore();
    const visibleQuery = (db) => db.collection("worker_discovery")
      .where("discoveryVisible", "==", true)
      .where("tradeIds", "array-contains", "dryliner").limit(25);

    await assertSucceeds(a.doc("worker_discovery/worker").get());
    await assertSucceeds(visibleQuery(a).get());
    await assertSucceeds(a.collection("worker_discovery")
      .where("discoveryVisible", "==", true)
      .where(firebase.firestore.FieldPath.documentId(),
        "in", ["worker"]).limit(25).get());
    await assertFails(a.doc("worker_discovery/hidden").get());
    await assertFails(a.collection("worker_discovery").get());
    await assertFails(a.collection("worker_discovery").limit(26).get());
    await assertFails(worker.collection("worker_discovery").limit(25).get());
    await assertSucceeds(worker.doc("worker_discovery/worker").get());
    await assertFails(guest.doc("worker_discovery/worker").get());
    await assertFails(a.doc("worker_discovery/worker").set({phone: "secret"}));

    const pool = a.doc("employer_talent_pools/employerA/workers/worker");
    await assertSucceeds(pool.set({workerId: "worker",
      savedAt: firebase.firestore.FieldValue.serverTimestamp()}));
    await assertSucceeds(pool.get());
    await assertSucceeds(a.collection("employer_talent_pools/employerA/workers")
      .limit(25).get());
    await assertSucceeds(a.collection("employer_talent_pools/employerA/workers")
      .where(firebase.firestore.FieldPath.documentId(), "in", ["worker"])
      .limit(10).get());
    await assertFails(pool.set({workerId: "worker", phone: "secret"}));
    await assertFails(a.doc("employer_talent_pools/employerA/workers/hidden")
      .set({workerId: "hidden", savedAt: new Date()}));
    await assertFails(b.doc("employer_talent_pools/employerA/workers/worker").get());
    await assertFails(worker.doc("employer_talent_pools/employerA/workers/worker").get());
    await assertFails(a.doc("users/worker").get());
    await assertSucceeds(pool.delete());
  } finally {
    await env.cleanup();
  }
});
