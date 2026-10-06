"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");
const {invitationId, eligibleWorker, closureStatus, displayFields} =
  require("../vacancy_invitation_policy");
const {inviteWorkers, respondToInvitation, closeInvitations,
  markApplicationInvitations} = require("../vacancy_invitations");

const now = new Date("2026-10-06T12:00:00Z");
const employerId = "employerTest001";
const vacancyId = "vacancyTest001";
const workerId = "workerTest001";
const job = {ownerId: employerId, moderationStatus: "approved", status: "active",
  canonicalRoleId: "dryliner", title: "Dryliner", city: "Manchester",
  positions: 3, filledPositions: 0};
const worker = {discoveryVisible: true, allowVacancyInvites: true,
  tradeIds: ["dryliner", "fixer"], availabilityStatus: "available_now",
  availabilityConfirmedAt: now};

test("eligibility, closure and safe invitation display fields", () => {
  assert.equal(eligibleWorker(worker, job, now), null);
  assert.equal(eligibleWorker({...worker, allowVacancyInvites: false}, job, now),
    "invites_disabled");
  assert.equal(eligibleWorker({...worker, availabilityStatus: "not_looking"}, job, now),
    "availability_unconfirmed");
  assert.equal(eligibleWorker({...worker, tradeIds: ["plasterer"]}, job, now),
    "trade_mismatch");
  assert.equal(eligibleWorker({...worker,
    availabilityConfirmedAt: new Date("2026-09-01")}, job, now),
  "availability_unconfirmed");
  assert.equal(closureStatus({...job, status: "closed"}), "vacancy_closed");
  assert.equal(closureStatus({...job, filledPositions: 3}), "vacancy_filled");
  const display = displayFields({...job, city: "12 Manchester Road"},
    {companyName: "Construction Ltd", phone: "+441234567890"});
  assert.equal(display.generalLocation, "");
  assert.equal(JSON.stringify(display).includes("+44"), false);
  assert.equal(JSON.stringify(display).includes("Road"), false);
  assert.equal(invitationId(vacancyId, workerId), invitationId(vacancyId, workerId));
});

test("invitation lifecycle in Firestore emulator", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = admin.initializeApp({projectId: "stroyka-invitation-tests"},
    "vacancy-invitation-tests");
  const db = app.firestore();
  const employer = db.collection("users").doc(employerId);
  const jobRef = db.collection("jobs").doc(vacancyId);
  const discovery = db.collection("worker_discovery");
  const invitationRef = db.collection("vacancy_invitations")
    .doc(invitationId(vacancyId, workerId));
  try {
    await employer.set({role: "employer", profileComplete: true,
      companyName: "Construction Ltd", billing: {planId: "growth",
        subscriptionStatus: "active", billingStatus: "active"}});
    await db.collection("users").doc(workerId)
      .set({role: "worker", profileComplete: true});
    await jobRef.set(job);
    await discovery.doc(workerId).set(worker);
    await discovery.doc("workerTest002").set(worker);
    await discovery.doc("workerTest003").set({...worker,
      allowVacancyInvites: false});
    await discovery.doc("workerTest004").set({...worker,
      availabilityStatus: "not_looking"});
    await discovery.doc("workerTest005").set(worker);
    await discovery.doc("workerTest006").set(worker);
    await discovery.doc("workerTest007").set(worker);
    await db.collection("applications").doc("existingApplication001").set({
      jobId: vacancyId, workerId: "workerTest006", status: "pending",
    });

    const first = await inviteWorkers(db, employerId,
      {vacancyId, workerIds: [workerId, "workerTest002",
        "workerTest003", "workerTest004"]}, now);
    assert.equal(first.created, 2);
    assert.deepEqual(first.results.map((result) => result.result),
      ["invited", "invited", "invites_disabled", "availability_unconfirmed"]);
    const stored = (await invitationRef.get()).data();
    assert.equal(stored.status, "pending");
    assert.equal(stored.workerId, workerId);
    assert.equal(stored.phone, undefined);
    assert.equal(stored.email, undefined);
    assert.equal(stored.address, undefined);
    assert.ok((await db.collection("users").doc(workerId)
      .collection("notifications").doc(invitationRef.id).get()).exists);
    const duplicate = await inviteWorkers(db, employerId,
      {vacancyId, workerIds: [workerId]}, now);
    assert.equal(duplicate.created, 0);
    assert.equal(duplicate.results[0].result, "already_invited");
    const usageRef = db.collection("employer_usage").doc(`${employerId}_202610`);
    assert.equal((await usageRef.get()).data().vacancyInvitations, 2);
    const alreadyApplied = await inviteWorkers(db, employerId,
      {vacancyId, workerIds: ["workerTest006"]}, now);
    assert.equal(alreadyApplied.created, 0);
    assert.equal(alreadyApplied.results[0].result, "already_applied");
    await assert.rejects(inviteWorkers(db, "employerOther01",
      {vacancyId, workerIds: [workerId]}, now),
    {code: "permission-denied"});
    await assert.rejects(respondToInvitation(db, "workerOther001",
      {invitationId: invitationRef.id, action: "viewed"}),
    {code: "permission-denied"});
    assert.deepEqual(await respondToInvitation(db, workerId,
      {invitationId: invitationRef.id, action: "viewed"}), {status: "viewed"});
    assert.deepEqual(await respondToInvitation(db, workerId,
      {invitationId: invitationRef.id, action: "not_interested"}),
    {status: "not_interested"});
    assert.equal((await invitationRef.get()).data().status, "not_interested");

    const appliedRef = db.collection("vacancy_invitations")
      .doc(invitationId(vacancyId, "workerTest002"));
    await markApplicationInvitations(db,
      {jobId: vacancyId, workerId: "workerTest002", status: "pending"});
    assert.equal((await appliedRef.get()).data().status, "applied");
    const pending = await inviteWorkers(db, employerId,
      {vacancyId, workerIds: ["workerTest005"]}, now);
    assert.equal(pending.created, 1);
    assert.equal((await usageRef.get()).data().vacancyInvitations, 3);
    await employer.update({"billing.planId": "starter"});
    await assert.rejects(inviteWorkers(db, employerId,
      {vacancyId, workerIds: ["workerTest007"]}, now),
    {code: "permission-denied"});
    await employer.update({"billing.planId": "growth"});
    await usageRef.update({vacancyInvitations: 200});
    await assert.rejects(inviteWorkers(db, employerId,
      {vacancyId, workerIds: ["workerTest007"]}, now),
    {code: "resource-exhausted"});
    await jobRef.update({status: "closed"});
    await closeInvitations(db, vacancyId, (await jobRef.get()).data());
    assert.equal((await appliedRef.get()).data().status, "applied");
    assert.equal((await invitationRef.get()).data().status, "not_interested");
    assert.equal((await db.collection("vacancy_invitations")
      .doc(invitationId(vacancyId, "workerTest005")).get()).data().status,
    "vacancy_closed");
  } finally {
    await app.delete();
  }
});
