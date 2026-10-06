"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("sites and assignments remain scoped to their participants", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: "stroyka-sites-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      for (const id of ["employerA", "employerB"]) {
        await db.doc(`users/${id}`).set({role: "employer",
          profileComplete: true});
      }
      for (const id of ["workerA", "workerB"]) {
        await db.doc(`users/${id}`).set({role: "worker",
          profileComplete: true});
      }
      await db.doc("assignments/assignmentA").set({
        employerContextId: "employerA", workerId: "workerA",
        vacancyId: "jobA", status: "scheduled",
        startDate: firebase.firestore.Timestamp.fromDate(
          new Date("2026-10-15T12:00:00Z")),
        expectedEndDate: firebase.firestore.Timestamp.fromDate(
          new Date("2026-10-25T12:00:00Z"))});
      await db.doc("jobs/jobA").set({ownerId: "employerA",
        moderationStatus: "pending_review", status: "active",
        startDate: firebase.firestore.Timestamp.fromDate(
          new Date("2026-10-15T12:00:00Z"))});
    });
    const a = env.authenticatedContext("employerA").firestore();
    const b = env.authenticatedContext("employerB").firestore();
    const workerA = env.authenticatedContext("workerA").firestore();
    const workerB = env.authenticatedContext("workerB").firestore();
    const site = a.doc("sites/siteA");
    const data = {siteId: "siteA", employerContextId: "employerA",
      ownerUid: "employerA", status: "active", name: "Site A",
      addressLine1: "10 Tower Road", city: "Manchester",
      region: "Greater Manchester", postcode: "M1 1AA",
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()};
    await assertSucceeds(site.set(data));
    await assertSucceeds(site.get());
    await assertSucceeds(a.collection("sites")
      .where("employerContextId", "==", "employerA").get());
    await assertFails(b.doc("sites/siteA").get());
    await assertFails(b.doc("sites/siteA").update({name: "Stolen"}));
    await assertFails(workerA.collection("sites").get());
    await assertFails(workerA.doc("sites/siteA").get());
    await assertSucceeds(a.doc("jobs/linkedJob").set({ownerId: "employerA",
      siteId: "siteA", status: "active", moderationStatus: "pending_review"}));
    await assertSucceeds(a.doc("jobs/legacyJob").set({ownerId: "employerA",
      status: "active", moderationStatus: "pending_review"}));
    await assertFails(a.doc("jobs/foreignSiteJob").set({ownerId: "employerA",
      siteId: "missingSite", status: "active",
      moderationStatus: "pending_review"}));
    await assertSucceeds(site.update({status: "archived",
      archivedAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()}));
    assert.ok((await a.doc("jobs/jobA").get()).exists);
    await assertFails(site.delete());
    await assertSucceeds(a.doc("assignments/assignmentA").get());
    await assertSucceeds(a.collection("assignments")
      .where("employerContextId", "==", "employerA").get());
    const start = firebase.firestore.Timestamp.fromDate(
      new Date("2026-10-01T00:00:00Z"));
    const end = firebase.firestore.Timestamp.fromDate(
      new Date("2026-11-01T00:00:00Z"));
    await assertSucceeds(a.collection("assignments")
      .where("employerContextId", "==", "employerA")
      .where("startDate", ">=", start).where("startDate", "<", end).get());
    await assertSucceeds(a.collection("assignments")
      .where("employerContextId", "==", "employerA")
      .where("expectedEndDate", ">=", start)
      .where("startDate", "<", end)
      .orderBy("expectedEndDate").orderBy("startDate").get());
    await assertFails(b.collection("assignments")
      .where("employerContextId", "==", "employerA")
      .where("startDate", ">=", start).get());
    await assertSucceeds(a.collection("jobs")
      .where("ownerId", "==", "employerA")
      .where("startDate", ">=", start).where("startDate", "<", end).get());
    await assertFails(b.doc("assignments/assignmentA").get());
    await assertSucceeds(workerA.doc("assignments/assignmentA").get());
    await assertSucceeds(workerA.collection("assignments")
      .where("workerId", "==", "workerA").get());
    await assertSucceeds(workerA.collection("assignments")
      .where("workerId", "==", "workerA")
      .where("startDate", ">=", start).where("startDate", "<", end).get());
    await assertFails(workerB.collection("assignments")
      .where("workerId", "==", "workerA")
      .where("startDate", ">=", start).get());
    await assertFails(workerA.doc("users/workerB").get());
    await assertFails(workerA.collection("assignments").get());
    await assertFails(workerB.doc("assignments/assignmentA").get());
    await assertFails(workerA.doc("assignments/assignmentA")
      .update({status: "active"}));
  } finally {
    await env.cleanup();
  }
});
