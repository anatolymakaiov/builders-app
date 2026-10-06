"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {deriveEffectiveAvailability} = require("../effective_worker_availability");
const admin = require("firebase-admin");
const {recomputeWorkerAvailability} =
  require("../recompute_worker_availability");

const now = new Date("2026-10-10T12:00:00Z");
const manual = {availabilityStatus: "available_now",
  availabilityConfirmedAt: new Date("2026-10-09T12:00:00Z")};
const assignment = (start, end, status = "active") => ({
  status, startDate: new Date(start),
  expectedEndDate: end ? new Date(end) : null,
});
const period = (start, end) => ({startDate: new Date(start),
  endDate: new Date(end), type: "personal", note: "Private reason"});
const derive = (preference, assignments = [], periods = []) =>
  deriveEffectiveAvailability(preference, assignments, periods, now);

test("fresh manual availability stays available without blocks", () => {
  assert.equal(derive(manual).effectiveAvailabilityStatus, "available_now");
});

test("assignment blocks and returns first safe day", () => {
  const result = derive(manual,
    [assignment("2026-10-09", "2026-10-11")]);
  assert.equal(result.effectiveAvailabilityStatus, "busy");
  assert.equal(result.effectiveAvailabilityReason, "assignment");
  assert.equal(result.effectiveAvailableFrom.toISOString().slice(0, 10),
    "2026-10-12");
});

test("active or undated scheduled work never leaves worker available now", () => {
  const active = derive(manual, [{status: "active",
    startDate: new Date("2026-10-01"),
    expectedEndDate: new Date("2026-10-05")}]);
  assert.equal(active.effectiveAvailabilityStatus, "busy");
  assert.equal(active.effectiveAvailableFrom, null);
  const undated = derive(manual, [{status: "scheduled"}]);
  assert.equal(undated.effectiveAvailabilityStatus, "busy");
});

test("later manual date wins after assignment", () => {
  const result = derive({...manual, availabilityStatus: "available_from",
    availableFrom: new Date("2026-10-20")},
  [assignment("2026-10-09", "2026-10-11")]);
  assert.equal(result.effectiveAvailableFrom.toISOString().slice(0, 10),
    "2026-10-20");
});

test("not looking overrides work and manual busy remains busy", () => {
  assert.equal(derive({...manual, availabilityStatus: "not_looking"},
    [assignment("2026-10-09", "2026-10-11")]).effectiveAvailabilityStatus,
  "not_looking");
  assert.equal(derive({...manual, availabilityStatus: "busy"})
    .effectiveAvailabilityStatus, "busy");
});

test("cancelled and completed historical assignments do not block", () => {
  const result = derive(manual, [
    assignment("2026-10-09", "2026-10-11", "cancelled"),
    assignment("2026-10-01", "2026-10-03", "completed"),
  ]);
  assert.equal(result.effectiveAvailabilityStatus, "available_now");
});

test("overlapping assignments and unavailable periods merge", () => {
  const result = derive(manual, [
    assignment("2026-10-09", "2026-10-11"),
    assignment("2026-10-12", "2026-10-14", "scheduled"),
  ], [period("2026-10-13", "2026-10-18"),
    period("2026-10-17", "2026-10-20")]);
  assert.equal(result.effectiveAvailabilityStatus, "busy");
  assert.equal(result.effectiveAvailableFrom.toISOString().slice(0, 10),
    "2026-10-21");
});

test("manual unavailable period is private in derived projection", () => {
  const result = derive(manual, [],
    [period("2026-10-09", "2026-10-11")]);
  assert.equal(result.effectiveAvailabilityStatus, "unavailable");
  assert.equal(JSON.stringify(result).includes("Private reason"), false);
});

test("stale manual preference is never promoted to available now", () => {
  const result = derive({...manual,
    availabilityConfirmedAt: new Date("2026-09-01")});
  assert.equal(result.effectiveAvailabilityStatus, "unknown");
});

test("future work leaves worker available only until assignment starts", () => {
  const result = derive(manual,
    [assignment("2026-10-15", "2026-10-20", "scheduled")]);
  assert.equal(result.effectiveAvailabilityStatus, "available_now");
  assert.equal(result.nextUnavailableFrom.toISOString().slice(0, 10),
    "2026-10-15");
  assert.equal(result.nextUnavailableUntil.toISOString().slice(0, 10),
    "2026-10-20");
});

test("available-from date inside future assignment shifts to first safe day", () => {
  const result = derive({...manual, availabilityStatus: "available_from",
    availableFrom: new Date("2026-10-15")},
  [assignment("2026-10-12", "2026-10-20", "scheduled")]);
  assert.equal(result.effectiveAvailableFrom.toISOString().slice(0, 10),
    "2026-10-21");
  assert.equal(result.nextUnavailableFrom.toISOString().slice(0, 10),
    "2026-10-12");
});

test("recompute writes a PII-free, idempotent discovery projection", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = admin.initializeApp({projectId: "stroyka-availability-recompute"},
    "availability-recompute-test");
  const db = app.firestore();
  const workerId = "availabilityWorker001";
  try {
    await db.collection("users").doc(workerId).set({
      role: "worker", profileComplete: true, name: "Test Worker",
      tradeIds: ["dryliner"], availabilityStatus: "available_now",
      availabilityConfirmedAt: new Date("2026-10-09T12:00:00Z"),
      allowVacancyInvites: true,
    });
    await db.collection("worker_unavailability").doc("period001").set({
      workerId, startDate: new Date("2026-10-10"),
      endDate: new Date("2026-10-11"), type: "personal",
      note: "Private medical appointment",
    });
    const first = await recomputeWorkerAvailability(db, workerId, now);
    const second = await recomputeWorkerAvailability(db, workerId, now);
    assert.equal(first.changed, true);
    assert.equal(second.changed, false);
    const projection = (await db.collection("worker_discovery")
      .doc(workerId).get()).data();
    assert.equal(projection.effectiveAvailabilityStatus, "unavailable");
    assert.equal(projection.availabilityStatus, "unavailable");
    assert.equal(JSON.stringify(projection).includes("Private medical"), false);
    await db.collection("worker_unavailability").doc("period001").delete();
    const afterDelete = await recomputeWorkerAvailability(db, workerId, now);
    assert.equal(afterDelete.effective.effectiveAvailabilityStatus,
      "available_now");
  } finally {
    await app.delete();
  }
});
