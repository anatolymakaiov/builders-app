"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");
const {assignmentWorkers, eligibleForAssignment, createAcceptedAssignments} =
  require("../site_assignments");

test("only confirmed accepted offers produce worker IDs", () => {
  const accepted = {status: "offer_accepted", slotDecrementApplied: true,
    offerAcceptedAt: new Date(), acceptedByWorkerId: "workerA",
    jobId: "jobA", employerId: "employerA", workerId: "workerA"};
  assert.equal(eligibleForAssignment({status: "offer_sent"}, accepted), true);
  assert.equal(eligibleForAssignment(accepted, accepted), false);
  assert.equal(eligibleForAssignment(null,
    {...accepted, status: "offer_sent"}), false);
  assert.equal(eligibleForAssignment(null,
    {...accepted, slotDecrementApplied: false}), false);
  assert.deepEqual(assignmentWorkers(accepted), ["workerA"]);
  assert.deepEqual(assignmentWorkers({...accepted, teamId: "teamA",
    workerId: "leaderA"}), []);
  assert.deepEqual(assignmentWorkers({...accepted, teamId: "teamA",
    offer: {selectedWorkerIds: ["workerA", "workerB", "workerA"]}}),
  ["workerA", "workerB"]);
});

test("accepted assignment is idempotent and copies safe site context", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = admin.initializeApp({projectId: "stroyka-site-assignment-test"},
    "site-assignment-test");
  const db = app.firestore();
  const application = {status: "offer_accepted", slotDecrementApplied: true,
    offerAcceptedAt: admin.firestore.Timestamp.now(),
    acceptedByWorkerId: "workerA", workerId: "workerA",
    jobId: "jobA", employerId: "employerA", offerId: "offerA"};
  try {
    await db.collection("jobs").doc("jobA").set({ownerId: "employerA",
      siteId: "siteA", site: "Old site", canonicalRoleId: "dryliner",
      canonicalRoleName: "Dryliner",
      slotDecrementApplicationIds: ["applicationA"]});
    await db.collection("sites").doc("siteA").set({
      employerContextId: "employerA", name: "New site"});
    await db.collection("public_profiles").doc("workerA")
      .set({displayName: "Alex W."});
    assert.equal(await createAcceptedAssignments(db, "applicationA",
      {status: "offer_sent"}, application, admin.firestore.FieldValue), 1);
    assert.equal(await createAcceptedAssignments(db, "applicationA",
      {status: "offer_sent"}, application, admin.firestore.FieldValue), 0);
    const all = await db.collection("assignments").get();
    assert.equal(all.size, 1);
    const data = all.docs[0].data();
    assert.equal(data.workerId, "workerA");
    assert.equal(data.workerDisplayName, "Alex W.");
    assert.equal(data.employerContextId, "employerA");
    assert.equal(data.vacancyId, "jobA");
    assert.equal(data.siteId, "siteA");
    assert.equal(data.siteName, "New site");
    assert.equal(data.tradeId, "dryliner");
    assert.equal(data.tradeName, "Dryliner");
    assert.equal(data.status, "scheduled");
    assert.equal(await createAcceptedAssignments(db, "applicationB", null,
      {...application, status: "offer_sent"}, admin.firestore.FieldValue), 0);
    await db.collection("jobs").doc("jobTeam").set({ownerId: "employerA",
      canonicalRoleId: "electrician", slotDecrementApplicationIds: ["teamApp"]});
    await db.collection("public_profiles").doc("workerB")
      .set({displayName: "Sam B."});
    const team = {...application, jobId: "jobTeam", teamId: "teamA",
      offer: {selectedWorkerIds: ["workerA", "workerB"]}};
    assert.equal(await createAcceptedAssignments(db, "teamApp",
      {status: "offer_sent"}, team, admin.firestore.FieldValue), 2);
    assert.equal((await db.collection("assignments").get()).size, 3);
    assert.equal((await db.collection("assignments")
      .doc("teamApp_workerB").get()).data().workerDisplayName, "Sam B.");
  } finally {
    await app.delete();
  }
});
