"use strict";

const DAY = 86400000;
const VALID_MANUAL = new Set(["available_now", "available_from", "busy", "not_looking"]);

function day(value) {
  const date = value instanceof Date ? value : value?.toDate?.() ||
    (typeof value === "string" ? new Date(value) : null);
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}

function asDate(value) {
  return value == null ? null : new Date(value);
}

function intervals(assignments, periods, today) {
  const result = [];
  for (const assignment of assignments) {
    if (!["scheduled", "active"].includes(assignment.status)) continue;
    const start = day(assignment.startDate);
    const end = day(assignment.actualEndDate || assignment.expectedEndDate);
    if (start == null || (end != null && end < today)) continue;
    result.push({start, end: end ?? Infinity, source: "assignment"});
  }
  for (const period of periods) {
    const start = day(period.startDate);
    const end = day(period.endDate);
    if (start == null || end == null || end < today || end < start) continue;
    result.push({start, end, source: "unavailability"});
  }
  return result.sort((a, b) => a.start - b.start || a.end - b.end);
}

function firstSafeDate(candidate, spans) {
  for (const span of spans) {
    if (span.start <= candidate && span.end >= candidate) {
      candidate = span.end + DAY;
    }
  }
  return candidate;
}

function mergedEnd(first, spans) {
  let end = first.end;
  for (const span of spans) {
    if (span.start >= first.start && span.start <= end + DAY) {
      end = Math.max(end, span.end);
    }
  }
  return end;
}

function deriveEffectiveAvailability(manual, assignments, periods, now = new Date()) {
  const today = day(now);
  const status = VALID_MANUAL.has(manual.availabilityStatus) &&
    day(manual.availabilityConfirmedAt) != null
    ? manual.availabilityStatus : "unknown";
  const confirmed = manual.availabilityConfirmedAt?.toDate?.() ||
    (manual.availabilityConfirmedAt instanceof Date
      ? manual.availabilityConfirmedAt : null);
  const elapsed = confirmed ? now.getTime() - confirmed.getTime() : Infinity;
  const manualFrom = day(manual.availableFrom);
  const stale = elapsed < 0 ||
    (status === "available_now" ? elapsed >= 7 * DAY :
    status === "available_from" ? (manualFrom == null ||
      (manualFrom > today ? manualFrom - today <= 3 * DAY && elapsed >= 3 * DAY :
        elapsed >= DAY)) : false);
  const spans = intervals(assignments, periods, today);
  const current = spans.filter((span) => span.start <= today && span.end >= today);
  let blockEnd = current.reduce((max, span) => Math.max(max, span.end), -Infinity);
  if (current.length) {
    for (const span of spans) {
      if (span.start > today && span.start <= blockEnd + DAY) {
        blockEnd = Math.max(blockEnd, span.end);
      }
    }
  }
  const next = spans.find((span) => span.start > today);
  const nextEnd = next ? mergedEnd(next, spans) : null;
  const nextTransition = current.length
    ? (Number.isFinite(blockEnd) ? blockEnd + DAY : null)
    : next?.start ?? null;
  const confirmationExpiry = confirmed && !stale
    ? status === "available_now" ? confirmed.getTime() + 7 * DAY
      : status === "available_from" ? (manualFrom > today
        ? manualFrom - 3 * DAY > today
          ? manualFrom - 3 * DAY : Math.min(manualFrom,
            confirmed.getTime() + 3 * DAY)
        : confirmed.getTime() + DAY)
        : null
    : null;
  const refreshCandidates = [nextTransition, confirmationExpiry]
    .filter((value) => value != null && value > now.getTime());
  const base = {
    manualAvailabilityStatus: status,
    effectiveAvailabilityStatus: "unknown",
    effectiveAvailableFrom: null,
    effectiveAvailabilityReason: "unconfirmed",
    nextUnavailableFrom: null,
    nextUnavailableUntil: null,
    nextAvailabilityRefreshAt: refreshCandidates.length
      ? asDate(Math.min(...refreshCandidates)) : null,
  };
  if (status === "not_looking") {
    return {...base, effectiveAvailabilityStatus: status,
      effectiveAvailabilityReason: "preference"};
  }
  if (current.length) {
    const source = current.some((span) => span.source === "assignment")
      ? "assignment" : "unavailability";
    const available = Number.isFinite(blockEnd) ? blockEnd + DAY : null;
    return {...base, effectiveAvailabilityStatus: source === "assignment"
      ? "busy" : "unavailable", effectiveAvailabilityReason: source,
    effectiveAvailableFrom: available == null ? null :
      asDate(firstSafeDate(Math.max(available, manualFrom ?? available), spans))};
  }
  if (status === "busy") {
    return {...base, effectiveAvailabilityStatus: "busy",
      effectiveAvailabilityReason: "preference"};
  }
  if (stale || status === "unknown") return base;
  if (status === "available_from" && manualFrom != null && manualFrom > today) {
    const safeFrom = firstSafeDate(manualFrom, spans);
    return {...base, effectiveAvailabilityStatus: "available_from",
      effectiveAvailableFrom: Number.isFinite(safeFrom)
        ? asDate(safeFrom) : null,
      effectiveAvailabilityReason: "preference",
      nextUnavailableFrom: next ? asDate(next.start) : null,
      nextUnavailableUntil: Number.isFinite(nextEnd)
        ? asDate(nextEnd) : null};
  }
  return {...base, effectiveAvailabilityStatus: "available_now",
    effectiveAvailabilityReason: "preference",
    nextUnavailableFrom: next ? asDate(next.start) : null,
    nextUnavailableUntil: Number.isFinite(nextEnd)
      ? asDate(nextEnd) : null};
}

module.exports = {day, intervals, firstSafeDate, deriveEffectiveAvailability};
