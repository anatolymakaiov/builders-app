"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("Phase 1 profile rules preserve old clients and protect projections", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "Run via firebase emulators:exec --only firestore");
  const env = await initializeTestEnvironment({
    projectId: "stroyka-phase1-rules",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/worker").set({role: "worker", name: "Worker"});
      await db.doc("users/employer").set({role: "employer", companyName: "Co"});
      await db.doc("public_profiles/worker").set({displayName: "Worker"});
      await db.doc("worker_discovery/worker").set({availabilityStatus: "unknown"});
    });
    const worker = env.authenticatedContext("worker").firestore();
    const employer = env.authenticatedContext("employer").firestore();
    const outsider = env.authenticatedContext("outsider").firestore();
    const guest = env.unauthenticatedContext().firestore();

    await assertSucceeds(worker.doc("users/worker").get());
    await assertSucceeds(worker.doc("users/worker").update({name: "Updated"}));
    await assertSucceeds(outsider.doc("users/outsider").set({role: "worker", name: "New"}));
    await assertSucceeds(outsider.doc("users/outsider").update({role: "employer"}));
    await assertSucceeds(worker.doc("public_profiles/employer").get());
    await assertFails(guest.doc("public_profiles/worker").get());
    await assertFails(worker.doc("public_profiles/worker").set({phone: "secret"}));
    await assertFails(employer.doc("worker_discovery/worker").set({phone: "secret"}));
    await assertFails(guest.doc("worker_discovery/worker").get());
    await assertSucceeds(worker.doc("worker_discovery/worker").get());
    await assertFails(employer.doc("worker_discovery/worker").get());
    await assertFails(worker.doc("users/worker").update({role: "admin"}));
    await assertFails(outsider.doc("users/outsider").set({role: "admin"}));
    await assertFails(outsider.doc("users/outsider").set({role: "worker", isAdmin: true}));
    await assertFails(worker.doc("users/worker").update({isAdmin: true}));
    // Explicit compatibility debt until the published mobile clients migrate.
    await assertSucceeds(worker.doc("users/employer").get());
  } finally {
    await env.cleanup();
  }
});
