"use strict";

const crypto = require("crypto");
const DEFAULT_ASSIGNMENT_START_OFFSETS = Object.freeze([2880, 1440]);
const DEFAULT_ASSIGNMENT_FINISH_OFFSETS = Object.freeze([1440]);

function asDate(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === "function") return value.toDate();
  return null;
}

function validOffsets(value) {
  return Array.isArray(value) && value.length <= 5 &&
    new Set(value).size === value.length && value.every((offset) =>
      Number.isInteger(offset) && offset >= 0 && offset <= 43200);
}

function reminderId(sourceKey, kind, date, offset) {
  return crypto.createHash("sha256")
    .update(`${sourceKey}|${kind}|${date.toISOString()}|${offset}`)
    .digest("hex");
}

function reminderSpecs(sourceType, sourceId, data) {
  if (!data || !data.employerContextId) return [];
  if (sourceType === "assignment" &&
      !["scheduled", "active"].includes(String(data.status || ""))) return [];
  const sourceKey = `${sourceType}:${sourceId}`;
  const kinds = sourceType === "assignment" ? [
    ["start", asDate(data.startDate), data.startReminderOffsetsMinutes ??
      DEFAULT_ASSIGNMENT_START_OFFSETS],
    ["finish", asDate(data.actualEndDate || data.expectedEndDate),
      data.finishReminderOffsetsMinutes ?? DEFAULT_ASSIGNMENT_FINISH_OFFSETS],
  ] : [["event", asDate(data.startDateTime),
    data.reminderOffsetsMinutes ?? []]];
  const specs = [];
  for (const [kind, date, offsets] of kinds) {
    if (!date || !validOffsets(offsets)) continue;
    for (const offset of offsets) {
      const scheduledFor = new Date(date.getTime() - offset * 60000);
      specs.push({
        id: reminderId(sourceKey, kind, date, offset),
        sourceKey, sourceType, sourceId, kind, offset,
        employerId: data.employerContextId,
        scheduledFor,
        eventAt: date,
        siteId: data.siteId || "",
        title: sourceType === "assignment" ?
          `${data.workerDisplayName || "Worker"} · ${data.tradeName || "Work"}` :
          String(data.title || "Event"),
        siteName: data.siteName || "",
        eventType: data.eventType || "",
      });
    }
  }
  return specs;
}

async function syncReminders(db, sourceType, sourceId, data, fieldValue,
  now = new Date()) {
  const sourceKey = `${sourceType}:${sourceId}`;
  const existing = await db.collection("event_reminders")
    .where("sourceKey", "==", sourceKey).get();
  const desired = new Map(reminderSpecs(sourceType, sourceId, data)
    .map((spec) => [spec.id, spec]));
  const known = new Map(existing.docs.map((doc) => [doc.id, doc]));
  const batch = db.batch();
  let writes = 0;
  for (const doc of existing.docs) {
    if (!desired.has(doc.id) && doc.data().status === "pending") {
      batch.update(doc.ref, {status: "cancelled", updatedAt: fieldValue.serverTimestamp()});
      writes++;
    }
  }
  for (const spec of desired.values()) {
    if (spec.scheduledFor < now) continue;
    const prior = known.get(spec.id);
    if (prior?.data().status === "pending" || prior?.data().status === "sent") continue;
    const ref = db.collection("event_reminders").doc(spec.id);
    batch.set(ref, {...spec, status: "pending",
      updatedAt: fieldValue.serverTimestamp()}, {merge: true});
    writes++;
  }
  if (writes) await batch.commit();
  return writes;
}

function notificationFor(spec) {
  const kind = spec.kind;
  const title = kind === "start" ? "Worker starting soon" :
    kind === "finish" ? "Worker finishing soon" :
      spec.eventType === "deadline" ? "Site deadline" : "Calendar reminder";
  return {
    type: "operational_reminder", category: "application",
    targetType: "calendar", targetId: spec.sourceId,
    siteId: spec.siteId, sourceType: spec.sourceType, eventAt: spec.eventAt,
    title, body: [spec.title, spec.siteName].filter(Boolean).join(" · "),
    read: false, pushEligible: true,
  };
}

async function deliverReminder(db, reminderRef, now, fieldValue) {
  return db.runTransaction(async (tx) => {
    const reminder = await tx.get(reminderRef);
    const data = reminder.data();
    if (!data || data.status !== "pending" ||
        !asDate(data.scheduledFor) || asDate(data.scheduledFor) > now) return false;
    const collection = data.sourceType === "assignment" ? "assignments" : "site_events";
    const source = await tx.get(db.collection(collection).doc(data.sourceId));
    const specs = reminderSpecs(data.sourceType, data.sourceId, source.data());
    if (!specs.some((spec) => spec.id === reminderRef.id &&
        spec.employerId === data.employerId)) {
      tx.update(reminderRef, {status: "cancelled", updatedAt: fieldValue.serverTimestamp()});
      return false;
    }
    const notificationRef = db.collection("users").doc(data.employerId)
      .collection("notifications").doc(`reminder_${reminderRef.id}`);
    tx.create(notificationRef, {
      ...notificationFor(data), notificationId: notificationRef.id,
      createdAt: fieldValue.serverTimestamp(),
    });
    tx.update(reminderRef, {status: "sent", sentAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp()});
    return true;
  });
}

async function deliverDueReminders(db, now, fieldValue, limit = 100) {
  const due = await db.collection("event_reminders")
    .where("status", "==", "pending")
    .where("scheduledFor", "<=", now)
    .orderBy("scheduledFor").limit(limit).get();
  let delivered = 0;
  for (const doc of due.docs) {
    if (await deliverReminder(db, doc.ref, now, fieldValue)) delivered++;
  }
  return delivered;
}

module.exports = {DEFAULT_ASSIGNMENT_START_OFFSETS,
  DEFAULT_ASSIGNMENT_FINISH_OFFSETS, validOffsets, reminderId,
  reminderSpecs, syncReminders, notificationFor, deliverReminder,
  deliverDueReminders};
