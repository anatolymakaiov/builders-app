"use strict";

const ACCEPTED_WORK_STATUSES = new Set([
  "offer_accepted",
  "accepted",
  "hired",
  "completed",
]);

function cleanStatus(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function cleanId(value) {
  return typeof value === "string" ? value.trim() : "";
}

function applicationWorkerIds(data) {
  const ids = new Set();
  for (const value of [data.workerId, data.applicantId, data.userId]) {
    const id = cleanId(value);
    if (id) ids.add(id);
  }
  if (Array.isArray(data.members)) {
    for (const member of data.members) {
      if (typeof member === "string") {
        const id = cleanId(member);
        if (id) ids.add(id);
      } else if (member && typeof member === "object") {
        const id = cleanId(
          member.uid || member.userId || member.workerId || member.id,
        );
        if (id) ids.add(id);
      }
    }
  }
  for (const map of [data.membersStatus, data.memberStatuses]) {
    if (map && typeof map === "object" && !Array.isArray(map)) {
      for (const id of Object.keys(map)) {
        const clean = cleanId(id);
        if (clean) ids.add(clean);
      }
    }
  }
  return ids;
}

function isTeamApplication(data) {
  return cleanStatus(data.type || data.applicationType) === "team" ||
    Boolean(cleanId(data.teamId)) ||
    Array.isArray(data.members) ||
    (data.membersStatus && typeof data.membersStatus === "object") ||
    (data.memberStatuses && typeof data.memberStatuses === "object");
}

function effectiveApplicationStatusForWorker(data, workerId) {
  const cleanWorkerId = cleanId(workerId);
  if (!cleanWorkerId || !applicationWorkerIds(data).has(cleanWorkerId)) {
    return "";
  }
  if (isTeamApplication(data)) {
    for (const map of [data.membersStatus, data.memberStatuses]) {
      if (map && typeof map === "object" && !Array.isArray(map)) {
        const memberStatus = cleanStatus(map[cleanWorkerId]);
        if (memberStatus) return memberStatus;
      }
    }
  }
  return cleanStatus(data.status);
}

function hasAcceptedWorkRelationship(data, workerId) {
  return ACCEPTED_WORK_STATUSES.has(
    effectiveApplicationStatusForWorker(data, workerId),
  );
}

module.exports = {
  ACCEPTED_WORK_STATUSES,
  applicationWorkerIds,
  effectiveApplicationStatusForWorker,
  hasAcceptedWorkRelationship,
};
