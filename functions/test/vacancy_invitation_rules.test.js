"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("vacancy invitations are readable only by participants and server-written", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
  const env = await initializeTestEnvironment({
    projectId: "stroyka-invitation-rules",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/workerA").set({role: "worker",
        profileComplete: true, name: "A"});
      await db.doc("users/workerB").set({role: "worker",
        profileComplete: true, name: "B"});
      await db.doc("users/employerA").set({role: "employer",
        profileComplete: true, companyName: "A"});
      await db.doc("users/employerB").set({role: "employer",
        profileComplete: true, companyName: "B"});
      await db.doc("vacancy_invitations/inviteA").set({
        workerId: "workerA", employerId: "employerA", vacancyId: "jobA",
        status: "pending", createdAt: new Date(),
      });
    });
    const workerA = env.authenticatedContext("workerA").firestore();
    const workerB = env.authenticatedContext("workerB").firestore();
    const employerA = env.authenticatedContext("employerA").firestore();
    const employerB = env.authenticatedContext("employerB").firestore();
    const ref = (db) => db.doc("vacancy_invitations/inviteA");
    await assertSucceeds(ref(workerA).get());
    await assertSucceeds(ref(employerA).get());
    await assertFails(ref(workerB).get());
    await assertFails(ref(employerB).get());
    await assertSucceeds(workerA.collection("vacancy_invitations")
      .where("workerId", "==", "workerA").limit(25).get());
    await assertFails(workerB.collection("vacancy_invitations").get());
    await assertFails(ref(workerA).update({status: "applied"}));
    await assertFails(ref(employerA).update({status: "vacancy_closed"}));
    await assertFails(employerA.doc("vacancy_invitations/forged")
      .set({workerId: "workerA", employerId: "employerA"}));
    await assertFails(workerA.doc("users/workerA/notifications/forged")
      .set({type: "vacancy_invitation", targetType: "vacancy_invitation"}));
  } finally {
    await env.cleanup();
  }
});
