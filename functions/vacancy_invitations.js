"use strict";

const admin = require("firebase-admin");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  invitationId, closureStatus, eligibleWorker, displayFields,
  ACTIVE_STATUSES,
} = require("./vacancy_invitation_policy");
const {PLANS, resolveEmployerEntitlements} = require("./employer_entitlements");

const MAX_BATCH = Math.max(...Object.values(PLANS)
  .map((plan) => plan.invitationBatchLimit));
const timestamp = () => admin.firestore.FieldValue.serverTimestamp();

function isActiveAccount(data, role) {
  return data && (role === "employer" ?
    ["employer", "company"].includes(data.role) : data.role === role) &&
    (data.profileComplete === true || data.onboardingComplete === true ||
      data.profileCreated === true || data.registrationFinalizedAt != null) &&
    data.accountDeleted !== true && data.deleted !== true &&
    data.active !== false && data.suspended !== true;
}

function validIds(value) {
  return Array.isArray(value) && value.length > 0 && value.length <= MAX_BATCH &&
    value.every((id) => typeof id === "string" &&
      /^[A-Za-z0-9_-]{10,150}$/.test(id)) &&
    new Set(value).size === value.length;
}

async function inviteWorkers(db, uid, input, now = new Date()) {
  const vacancyId = input?.vacancyId;
  const workerIds = input?.workerIds;
  if (typeof vacancyId !== "string" ||
      !/^[A-Za-z0-9_-]{10,150}$/.test(vacancyId) ||
      !validIds(workerIds) || Object.keys(input).some((key) =>
        !["vacancyId", "workerIds"].includes(key))) {
    throw new HttpsError("invalid-argument", "Choose a vacancy and up to 20 workers.");
  }
  const employerRef = db.collection("users").doc(uid);
  const jobRef = db.collection("jobs").doc(vacancyId);
  const quotaRef = db.collection("vacancy_invitation_quotas")
    .doc(`${uid}_${now.toISOString().slice(0, 10)}`);
  const month = now.toISOString().slice(0, 7).replace("-", "");
  const usageRef = db.collection("employer_usage").doc(`${uid}_${month}`);
  const invitationRefs = workerIds.map((workerId) =>
    db.collection("vacancy_invitations").doc(invitationId(vacancyId, workerId)));
  const discoveryRefs = workerIds.map((workerId) =>
    db.collection("worker_discovery").doc(workerId));
  return db.runTransaction(async (tx) => {
    const appliedQueries = workerIds.map((workerId) => db.collection("applications")
      .where("jobId", "==", vacancyId).where("workerId", "==", workerId)
      .limit(20));
    const teamQueries = workerIds.map((workerId) => db.collection("applications")
      .where("jobId", "==", vacancyId).where("members", "array-contains", workerId)
      .limit(20));
    const [employer, job, quota, usage, ...rest] = await Promise.all([
      tx.get(employerRef), tx.get(jobRef), tx.get(quotaRef), tx.get(usageRef),
      ...discoveryRefs.map((ref) => tx.get(ref)),
      ...invitationRefs.map((ref) => tx.get(ref)),
      ...appliedQueries.map((query) => tx.get(query)),
      ...teamQueries.map((query) => tx.get(query)),
    ]);
    if (!isActiveAccount(employer.data(), "employer")) {
      throw new HttpsError("permission-denied", "Active employer account required.");
    }
    const entitlement = resolveEmployerEntitlements(employer.data(), now);
    if (!entitlement.canInviteToVacancy) {
      throw new HttpsError("permission-denied", "Your plan does not include vacancy invitations.");
    }
    if (workerIds.length > entitlement.vacancyInviteBatchLimit) {
      throw new HttpsError("invalid-argument", "Too many workers in one invitation batch.");
    }
    const vacancy = job.data();
    if (!job.exists || vacancy.ownerId !== uid) {
      throw new HttpsError("permission-denied", "Vacancy owner access required.");
    }
    if (closureStatus(vacancy)) {
      throw new HttpsError("failed-precondition", "Vacancy is not open for invitations.");
    }
    const used = Number(quota.data()?.count || 0);
    const results = [];
    let created = 0;
    for (let index = 0; index < workerIds.length; index++) {
      const workerId = workerIds[index];
      const discovery = rest[index].data();
      const existing = rest[workerIds.length + index];
      const individual = rest[workerIds.length * 2 + index];
      const team = rest[workerIds.length * 3 + index];
      const reason = eligibleWorker(discovery, vacancy, now);
      if (existing.exists) {
        results.push({workerId, result: "already_invited"});
      } else if ([...individual.docs, ...team.docs].some((doc) =>
        !["withdrawn", "cancelled", "canceled", "deleted", "removed", "inactive"]
          .includes(String(doc.data().status || "").toLowerCase()))) {
        results.push({workerId, result: "already_applied"});
      } else if (reason) {
        results.push({workerId, result: reason});
      } else {
        results.push({workerId, result: "invited"});
        created++;
      }
    }
    if (used + created > entitlement.vacancyInviteDailyLimit) {
      throw new HttpsError("resource-exhausted", "Daily invitation limit reached.");
    }
    const monthUsed = Number(usage.data()?.vacancyInvitations || 0);
    if (monthUsed + created > entitlement.vacancyInviteMonthlyLimit) {
      throw new HttpsError("resource-exhausted", "Monthly invitation allowance reached.");
    }
    for (let index = 0; index < results.length; index++) {
      if (results[index].result !== "invited") continue;
      const workerId = workerIds[index];
      const ref = invitationRefs[index];
      tx.create(ref, {
        invitationId: ref.id, vacancyId, employerId: uid, workerId,
        ...displayFields(vacancy, employer.data()),
        status: "pending", createdAt: timestamp(), updatedAt: timestamp(),
      });
      tx.create(db.collection("users").doc(workerId)
        .collection("notifications").doc(ref.id), {
        type: "vacancy_invitation", targetType: "vacancy_invitation",
        targetId: ref.id, invitationId: ref.id, jobId: vacancyId,
        title: "New vacancy invitation",
        body: "A relevant construction opportunity is available.",
        read: false, pushEligible: true, createdAt: timestamp(),
      });
    }
    if (created) tx.set(quotaRef, {
      employerId: uid, date: now.toISOString().slice(0, 10),
      count: used + created, updatedAt: timestamp(),
    });
    if (created) tx.set(usageRef, {
      employerId: uid, month, vacancyInvitations: monthUsed + created,
      updatedAt: timestamp(),
    }, {merge: true});
    return {created, results};
  });
}

async function respondToInvitation(db, uid, input) {
  const id = input?.invitationId;
  const action = input?.action;
  if (typeof id !== "string" || !/^[a-f0-9]{64}$/.test(id) ||
      !["viewed", "not_interested"].includes(action)) {
    throw new HttpsError("invalid-argument", "Invalid invitation response.");
  }
  const ref = db.collection("vacancy_invitations").doc(id);
  return db.runTransaction(async (tx) => {
    const inviteSnap = await tx.get(ref);
    const invite = inviteSnap.data();
    if (!invite || invite.workerId !== uid) {
      throw new HttpsError("permission-denied", "Invitation access denied.");
    }
    const worker = await tx.get(db.collection("users").doc(uid));
    if (!isActiveAccount(worker.data(), "worker")) {
      throw new HttpsError("permission-denied", "Active worker account required.");
    }
    const jobSnap = await tx.get(db.collection("jobs").doc(invite.vacancyId));
    const closed = closureStatus(jobSnap.data());
    if (closed && ACTIVE_STATUSES.has(invite.status)) {
      tx.update(ref, {status: closed, updatedAt: timestamp()});
      return {status: closed};
    }
    if (!ACTIVE_STATUSES.has(invite.status)) return {status: invite.status};
    if (action === "viewed" && invite.status === "viewed") {
      return {status: "viewed"};
    }
    tx.update(ref, {status: action, updatedAt: timestamp()});
    return {status: action};
  });
}

async function closeInvitations(db, vacancyId, after) {
  const closed = closureStatus(after);
  if (!closed) return 0;
  let updated = 0;
  for (;;) {
    const page = await db.collection("vacancy_invitations")
      .where("vacancyId", "==", vacancyId)
      .where("status", "in", ["pending", "viewed"]).limit(200).get();
    if (page.empty) break;
    const batch = db.batch();
    for (const doc of page.docs) {
      batch.update(doc.ref, {status: closed, updatedAt: timestamp()});
    }
    await batch.commit();
    updated += page.size;
  }
  return updated;
}

async function markApplicationInvitations(db, application) {
  if (!application || !application.jobId) return 0;
  const status = String(application.status || "").toLowerCase();
  if (["withdrawn", "cancelled", "canceled", "deleted", "removed"]
    .includes(status)) return 0;
  const ids = new Set();
  if (typeof application.workerId === "string") ids.add(application.workerId);
  for (const member of application.members || []) {
    const id = typeof member === "string" ? member :
      member?.workerId || member?.userId || member?.uid;
    if (typeof id === "string") ids.add(id);
  }
  let updated = 0;
  for (const workerId of [...ids].slice(0, 40)) {
    const ref = db.collection("vacancy_invitations")
      .doc(invitationId(application.jobId, workerId));
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists && snap.data().status !== "applied") {
        tx.update(ref, {status: "applied", updatedAt: timestamp()});
        updated++;
      }
    });
  }
  return updated;
}

module.exports = {
  inviteWorkers, respondToInvitation, closeInvitations,
  markApplicationInvitations,
};
