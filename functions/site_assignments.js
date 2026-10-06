"use strict";

const {day} = require("./effective_worker_availability");

const ACCEPTED = new Set(["offer_accepted", "accepted", "hired"]);

function assignmentWorkers(application) {
  const selected = application.offer?.selectedWorkerIds ||
    application.selectedWorkerIds;
  if (Array.isArray(selected) && selected.length) {
    return [...new Set(selected.filter((id) => typeof id === "string" && id))];
  }
  // A team offer without an explicit selection is ambiguous; never assign all members.
  if (application.teamId) return [];
  return typeof application.workerId === "string" && application.workerId
    ? [application.workerId] : [];
}

function eligibleForAssignment(before, after) {
  if (!after || !ACCEPTED.has(String(after.status || "").toLowerCase()) ||
      !after.slotDecrementApplied || !after.offerAcceptedAt ||
      !after.acceptedByWorkerId || !after.jobId || !after.employerId) return false;
  return !before || !ACCEPTED.has(String(before.status || "").toLowerCase()) ||
    !before.slotDecrementApplied;
}

function assignmentId(applicationId, workerId) {
  return `${applicationId}_${workerId}`;
}

async function createAcceptedAssignments(db, applicationId, before, after,
  fieldValue) {
  if (!eligibleForAssignment(before, after)) return 0;
  const workers = assignmentWorkers(after);
  if (!workers.length) return 0;
  const job = await db.collection("jobs").doc(after.jobId).get();
  if (!job.exists) return 0;
  const vacancy = job.data() || {};
  const employer = vacancy.ownerId || vacancy.employerId;
  if (employer !== after.employerId ||
      !Array.isArray(vacancy.slotDecrementApplicationIds) ||
      !vacancy.slotDecrementApplicationIds.includes(applicationId)) return 0;
  const site = vacancy.siteId
    ? await db.collection("sites").doc(vacancy.siteId).get() : null;
  const siteData = site?.exists && site.data()?.employerContextId === employer
    ? site.data() : {};
  const profiles = await db.getAll(...workers.map((workerId) =>
    db.collection("public_profiles").doc(workerId)));
  const displayNames = new Map(profiles.map((profile) => [profile.id,
    typeof profile.data()?.displayName === "string"
      ? profile.data().displayName : "Worker"]));
  let created = 0;
  for (const workerId of workers) {
    const ref = db.collection("assignments")
      .doc(assignmentId(applicationId, workerId));
    const start = day(vacancy.startDate || siteData.startDate);
    const end = day(siteData.expectedEndDate) ?? Infinity;
    let hasAvailabilityConflict = false;
    if (start != null) {
      const [periods, assignments] = await Promise.all([
        db.collection("worker_unavailability")
          .where("workerId", "==", workerId)
          .where("endDate", ">=", new Date(start)).get(),
        db.collection("assignments")
          .where("workerId", "==", workerId)
          .where("status", "in", ["scheduled", "active"]).get(),
      ]);
      hasAvailabilityConflict = periods.docs.some((doc) =>
        day(doc.data().startDate) <= end) || assignments.docs.some((doc) => {
        const data = doc.data();
        const existingStart = day(data.startDate);
        const existingEnd = day(data.actualEndDate || data.expectedEndDate) ?? Infinity;
        return existingStart != null && existingStart <= end &&
          existingEnd >= start;
      });
    }
    await db.runTransaction(async (transaction) => {
      if ((await transaction.get(ref)).exists) return;
      transaction.create(ref, {
        assignmentId: ref.id,
        employerContextId: employer,
        siteId: vacancy.siteId || "",
        siteName: siteData.name || vacancy.site || "",
        employerName: vacancy.companyName || "",
        vacancyId: after.jobId,
        workerId,
        workerDisplayName: displayNames.get(workerId) || "Worker",
        applicationId,
        offerId: after.offerId || after.offer?.id || "",
        tradeId: vacancy.canonicalRoleId || "",
        tradeName: vacancy.canonicalRoleName || vacancy.trade ||
          vacancy.title || "",
        status: "scheduled",
        hasAvailabilityConflict,
        ...(vacancy.startDate || siteData.startDate
          ? {startDate: vacancy.startDate || siteData.startDate} : {}),
        ...(siteData.expectedEndDate
          ? {expectedEndDate: siteData.expectedEndDate} : {}),
        createdAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });
      created++;
    });
  }
  return created;
}

module.exports = {assignmentWorkers, eligibleForAssignment,
  assignmentId, createAcceptedAssignments};
