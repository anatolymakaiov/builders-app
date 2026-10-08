"use strict";

const crypto = require("node:crypto");
const {safeArea} = require("./profile_projections");

const ACTIVE_STATUSES = new Set(["pending", "viewed"]);
const FINAL_STATUSES = new Set([
  "applied", "not_interested", "vacancy_closed", "vacancy_filled",
]);

function invitationId(vacancyId, workerId) {
  return crypto.createHash("sha256")
    .update(`${vacancyId}\0${workerId}`).digest("hex");
}

function asDate(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === "function") return value.toDate();
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function dateOnly(date) {
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function vacancyTradeId(job) {
  const id = String(job.canonicalRoleId || job.roleCanonicalId ||
    job.roleId || "").trim();
  return /^[a-z][a-z0-9_-]{1,63}$/.test(id) ? id : "";
}

function positionCounts(job) {
  const positive = (value) => {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(0, Math.trunc(number)) : 0;
  };
  const positions = positive(job.positions || job.totalPositions ||
    job.totalSlots || job.workersNeeded || job.requiredWorkers);
  const filled = positive(job.filledPositions || job.acceptedCount ||
    job.hiredCount);
  const remainingFields = ["remainingPositions", "openSlots",
    "availablePositions", "availableSlots", "remainingSlots",
    "positionsAvailable"];
  const stored = remainingFields.find((key) =>
    Object.hasOwn(job, key) && job[key] != null);
  const remaining = stored ? positive(job[stored]) :
    Math.max(positions - filled, 0);
  return {positions, remaining};
}

function closureStatus(job) {
  if (!job || job.deleted === true || job.isDeleted === true ||
      job.companyDeleted === true || job.employerDeleted === true ||
      job.active === false || job.billingSuspended === true ||
      job.moderationHold === true || job.vacancyHold === true ||
      job.jobSuspended === true ||
      String(job.moderationStatus || "").trim() !== "approved" ||
      !["active", "published", "open"].includes(
        String(job.status || "active").trim().toLowerCase())) {
    return "vacancy_closed";
  }
  const counts = positionCounts(job);
  if (counts.positions < 1 || counts.remaining < 1) return "vacancy_filled";
  return null;
}

function availabilityFresh(worker, now) {
  const status = String(worker.effectiveAvailabilityStatus || "unknown");
  const confirmed = asDate(worker.availabilityConfirmedAt);
  if (!confirmed || confirmed.getTime() > now.getTime()) return false;
  const elapsedDays = (now.getTime() - confirmed.getTime()) / 86400000;
  if (status === "available_now") return elapsedDays < 7;
  if (["busy", "unavailable"].includes(status) &&
      ["assignment", "unavailability"].includes(
        worker.effectiveAvailabilityReason)) {
    return elapsedDays < 10 && asDate(worker.effectiveAvailableFrom) != null;
  }
  if (status !== "available_from") return false;
  const from = asDate(worker.effectiveAvailableFrom || worker.availableFrom);
  if (!from) return false;
  if (dateOnly(from) > dateOnly(now)) {
    return dateOnly(from) - dateOnly(now) > 3 * 86400000 ||
      elapsedDays < 3;
  }
  return elapsedDays < 1;
}

function eligibleWorker(worker, job, now, options = {}) {
  if (!worker || worker.discoveryVisible !== true) return "not_discoverable";
  if (worker.allowVacancyInvites !== true) return "invites_disabled";
  const status = String(worker.effectiveAvailabilityStatus || "unknown");
  if (status === "not_looking") return "not_looking";
  if (!["available_now", "available_from", "busy", "unavailable"]
    .includes(status) || !asDate(worker.availabilityConfirmedAt)) {
    return "availability_unconfirmed";
  }
  const tradeId = vacancyTradeId(job);
  if (!tradeId && !options.allowRelevanceMismatch) {
    return "vacancy_trade_missing";
  }
  if (!Array.isArray(worker.tradeIds) ||
      !worker.tradeIds.includes(tradeId)) {
    if (!options.allowRelevanceMismatch) return "trade_mismatch";
  }
  if (!availabilityFresh(worker, now) && !options.allowRelevanceMismatch) {
    return "availability_unconfirmed";
  }
  const nextBlock = asDate(worker.nextUnavailableFrom);
  const nextBlockEnd = asDate(worker.nextUnavailableUntil);
  const startDate = asDate(job.startDate);
  if (nextBlock && startDate && dateOnly(nextBlock) <= dateOnly(startDate) &&
      (!nextBlockEnd || dateOnly(startDate) <= dateOnly(nextBlockEnd))) {
    if (!options.allowRelevanceMismatch) return "start_date_mismatch";
  }
  if (status !== "available_now") {
    const from = asDate(worker.effectiveAvailableFrom || worker.availableFrom);
    const start = asDate(job.startDate);
    if (!from || (!start && dateOnly(from) > dateOnly(now)) ||
        (start && dateOnly(from) > dateOnly(start))) {
      if (!options.allowRelevanceMismatch) return "start_date_mismatch";
    }
  }
  return null;
}

function safeTitle(job) {
  const value = String(job.canonicalRoleName || job.trade || job.title || "")
    .trim().slice(0, 80);
  return value && /^[\p{L}\s&/()+-]{1,80}$/u.test(value)
    ? value : "Construction vacancy";
}

function safeCompanyName(profile) {
  const value = String(profile?.companyName || profile?.displayName || "")
    .trim().slice(0, 80);
  return value && !/@|\d|\b(street|road|lane|avenue)\b/i.test(value)
    ? value : "Employer";
}

function displayFields(job, profile) {
  return {
    vacancyTitle: safeTitle(job),
    tradeId: vacancyTradeId(job),
    companyName: safeCompanyName(profile),
    generalLocation: safeArea(job.city || job.siteCity || job.county || ""),
  };
}

module.exports = {
  ACTIVE_STATUSES, FINAL_STATUSES, invitationId, vacancyTradeId,
  positionCounts, closureStatus, availabilityFresh, eligibleWorker,
  displayFields, asDate,
};
