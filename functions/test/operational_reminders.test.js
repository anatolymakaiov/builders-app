"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const admin = require("firebase-admin");
const {reminderSpecs, validOffsets, syncReminders,
  deliverDueReminders, notificationFor} = require("../operational_reminders");

const start = new Date("2026-11-02T09:00:00Z");
const assignment = {
  employerContextId: "employer-reminders", workerDisplayName: "John M.",
  tradeName: "Dryliner", siteId: "site-a", siteName: "Manchester Tower",
  status: "scheduled", startDate: start,
};

test("assignment defaults are two and one day before start", () => {
  const reminders = reminderSpecs("assignment", "assignment-a", assignment);
  assert.deepEqual(reminders.map((item) => item.offset), [2880, 1440]);
  assert.equal(reminders[0].scheduledFor.toISOString(),
    "2026-10-31T09:00:00.000Z");
  assert.equal(reminders[1].scheduledFor.toISOString(),
    "2026-11-01T09:00:00.000Z");
  assert.equal(notificationFor(reminders[0]).targetType, "calendar");
  assert.equal(notificationFor(reminders[0]).eventAt.toISOString(),
    start.toISOString());
  assert.equal(JSON.stringify(reminders).includes("homeAddress"), false);
});

test("manual custom reminders, cancellation and rescheduling are deterministic", () => {
  const event = {employerContextId: "employer-reminders", title: "Phase 1",
    eventType: "deadline", startDateTime: start,
    reminderOffsetsMinutes: [2880, 1440, 0]};
  const original = reminderSpecs("site_event", "event-a", event);
  assert.equal(original.length, 3);
  assert.deepEqual(original.map((item) => item.id),
    reminderSpecs("site_event", "event-a", event).map((item) => item.id));
  assert.notEqual(original[0].id, reminderSpecs("site_event", "event-a",
    {...event, startDateTime: new Date("2026-11-03T09:00:00Z")})[0].id);
  assert.deepEqual(reminderSpecs("site_event", "event-a", null), []);
  assert.deepEqual(reminderSpecs("assignment", "assignment-a",
    {...assignment, status: "cancelled"}), []);
  assert.equal(notificationFor(original[0]).title, "Site deadline");
  assert.equal(validOffsets([0, 1440, 2880]), true);
  assert.equal(validOffsets([0, 0]), false);
  assert.equal(validOffsets([-1]), false);
});

test("past offsets are not scheduled for a late-created event", async () => {
  const writes = [];
  const db = {collection: () => ({
    where: () => ({get: async () => ({docs: []})}),
    doc: (id) => ({id}),
  }), batch: () => ({
    set: (ref) => writes.push(ref.id),
    commit: async () => {},
  })};
  const now = new Date("2026-11-01T08:00:00Z");
  const future = {...assignment, startDate: new Date("2026-11-02T09:00:00Z")};
  await syncReminders(db, "assignment", "assignment-late", future,
    {serverTimestamp: () => now}, now);
  assert.deepEqual(writes, [reminderSpecs("assignment", "assignment-late", future)[1].id]);
});

test("reconciliation and delivery are idempotent in Firestore emulator", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const app = admin.initializeApp({projectId: "stroyka-reminder-tests"},
    "operational-reminder-tests");
  const db = app.firestore();
  try {
    const ref = db.collection("assignments").doc("assignment-a");
    await ref.set(assignment);
    const fieldValue = admin.firestore.FieldValue;
    assert.equal(await syncReminders(db, "assignment", ref.id,
      assignment, fieldValue), 2);
    assert.equal(await syncReminders(db, "assignment", ref.id,
      assignment, fieldValue), 0);
    const now = new Date("2026-11-01T12:00:00Z");
    assert.equal(await deliverDueReminders(db, now, fieldValue), 2);
    assert.equal(await deliverDueReminders(db, now, fieldValue), 0);
    const first = reminderSpecs("assignment", ref.id, assignment)[0];
    const notice = db.collection("users").doc(assignment.employerContextId)
      .collection("notifications").doc(`reminder_${first.id}`);
    assert.equal((await notice.get()).exists, true);
    const shifted = {...assignment, startDate: new Date("2026-11-05T09:00:00Z")};
    await ref.set(shifted);
    assert.equal(await syncReminders(db, "assignment", ref.id,
      shifted, fieldValue), 2);
    await ref.delete();
    await syncReminders(db, "assignment", ref.id, null, fieldValue);
    const pending = await db.collection("event_reminders")
      .where("status", "==", "pending").get();
    assert.equal(pending.empty, true);
  } finally {
    await app.delete();
  }
});
