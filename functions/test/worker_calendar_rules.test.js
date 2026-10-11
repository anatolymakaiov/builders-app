"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("worker personal events are owner-only and not unavailability", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: "stroyka-worker-calendar-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("users/workerA").set({
        role: "worker", profileComplete: true});
      await context.firestore().doc("users/workerB").set({
        role: "worker", profileComplete: true});
      await context.firestore().doc("users/employerA").set({
        role: "employer", profileComplete: true});
    });
    const worker = env.authenticatedContext("workerA").firestore();
    const other = env.authenticatedContext("workerB").firestore();
    const employer = env.authenticatedContext("employerA").firestore();
    const at = firebase.firestore.Timestamp.fromDate(
      new Date("2026-10-20T09:00:00Z"));
    const ref = worker.doc("users/workerA/calendar_events/eventA");
    await assertSucceeds(ref.set({
      eventId: "eventA", workerId: "workerA", title: "Private appointment",
      eventType: "event", startDateTime: at, endDateTime: at,
      description: "", reminderOffsetsMinutes: [15],
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    await assertSucceeds(ref.get());
    await assertFails(other.doc(ref.path).get());
    await assertFails(employer.doc(ref.path).get());
    await assertFails(employer.collection(
      "users/workerA/calendar_events").get());
    await assertFails(worker.doc(
      "users/workerB/calendar_events/eventB").set({workerId: "workerB"}));
    await assertFails(worker.doc("users/workerA/calendar_events/bad").set({
      eventId: "bad", workerId: "workerA", title: "Bad alert",
      eventType: "event", startDateTime: at, endDateTime: at,
      description: "", reminderOffsetsMinutes: [999999],
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }));
  } finally {
    await env.cleanup();
  }
});
