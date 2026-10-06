"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("only the worker can manage private unavailable periods", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const env = await initializeTestEnvironment({
    projectId: "stroyka-worker-unavailability-rules",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/workerA").set({role: "worker",
        profileComplete: true});
      await db.doc("users/workerB").set({role: "worker",
        profileComplete: true});
      await db.doc("users/employer").set({role: "employer",
        profileComplete: true, billing: {planId: "growth",
          subscriptionStatus: "active"}});
      await db.doc("worker_discovery/workerA").set({workerId: "workerA",
        discoveryVisible: true, tradeIds: ["dryliner"],
        effectiveAvailabilityStatus: "unavailable",
        effectiveAvailabilityReason: "unavailability"});
    });
    const a = env.authenticatedContext("workerA").firestore();
    const b = env.authenticatedContext("workerB").firestore();
    const employer = env.authenticatedContext("employer").firestore();
    const ref = a.doc("worker_unavailability/periodA");
    const data = {workerId: "workerA", startDate: new Date("2026-10-15"),
      endDate: new Date("2026-10-16"), type: "personal", note: "Private",
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()};
    await assertSucceeds(ref.set(data));
    await assertSucceeds(ref.get());
    await assertSucceeds(a.collection("worker_unavailability")
      .where("workerId", "==", "workerA").get());
    await assertFails(b.doc(ref.path).get());
    await assertFails(employer.doc(ref.path).get());
    await assertFails(employer.collection("worker_unavailability")
      .where("workerId", "==", "workerA").get());
    await assertSucceeds(employer.doc("worker_discovery/workerA").get());
    await assertFails(ref.update({workerId: "workerB"}));
    await assertSucceeds(ref.update({note: "Updated",
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()}));
    await assertSucceeds(ref.delete());
  } finally {
    await env.cleanup();
  }
});
