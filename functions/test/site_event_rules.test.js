"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("site events are employer-owned and linked only to owned sites", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  const env = await initializeTestEnvironment({
    projectId: "stroyka-site-event-rules-test",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/employerA").set({role: "employer",
        profileComplete: true});
      await db.doc("users/employerB").set({role: "employer",
        profileComplete: true});
      await db.doc("users/workerA").set({role: "worker",
        profileComplete: true});
      await db.doc("sites/siteA").set({employerContextId: "employerA"});
      await db.doc("sites/siteB").set({employerContextId: "employerB"});
    });
    const a = env.authenticatedContext("employerA").firestore();
    const b = env.authenticatedContext("employerB").firestore();
    const worker = env.authenticatedContext("workerA").firestore();
    const at = firebase.firestore.Timestamp.fromDate(
      new Date("2026-10-20T09:00:00Z"));
    const fields = {eventId: "eventA", employerContextId: "employerA",
      siteId: "siteA", title: "Inspection", eventType: "inspection",
      startDateTime: at, allDay: false, description: "Safety check",
      createdBy: "employerA",
      createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()};
    const ref = a.doc("site_events/eventA");
    await assertSucceeds(ref.set(fields));
    await assertSucceeds(ref.update({
      eventType: "reminder", reminderOffsetsMinutes: [0, 75, 1440],
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    await assertFails(ref.update({
      reminderOffsetsMinutes: [-1],
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    await assertFails(ref.update({
      reminderOffsetsMinutes: [0, 60, 120, 180, 240, 300],
      updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
    }));
    await assertFails(a.doc("event_reminders/private").set({status: "pending"}));
    await assertFails(a.doc("event_reminders/private").get());
    await assertFails(b.doc("event_reminders/private").get());
    await assertSucceeds(ref.get());
    await assertSucceeds(a.collection("site_events")
      .where("employerContextId", "==", "employerA")
      .where("startDateTime", ">=", at).get());
    await assertFails(b.doc("site_events/eventA").get());
    await assertFails(worker.doc("site_events/eventA").get());
    await assertFails(worker.collection("site_events").get());
    await assertFails(b.doc("site_events/eventA").update({title: "Changed"}));
    await assertFails(a.doc("site_events/foreignSite").set({
      ...fields, eventId: "foreignSite", siteId: "siteB"}));
    await assertFails(a.doc("site_events/badType").set({
      ...fields, eventId: "badType", eventType: "anything"}));
    await assertSucceeds(ref.update({title: "Updated",
      updatedAt: firebase.firestore.FieldValue.serverTimestamp()}));
    await assertSucceeds(ref.delete());
  } finally {
    await env.cleanup();
  }
});
