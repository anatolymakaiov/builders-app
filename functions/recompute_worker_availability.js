"use strict";

const {isDeepStrictEqual} = require("node:util");
const admin = require("firebase-admin");
const {workerDiscovery} = require("./profile_projections");
const {deriveEffectiveAvailability} = require("./effective_worker_availability");

async function recomputeWorkerAvailability(db, workerId, now = new Date(),
  {commit = true} = {}) {
  const user = await db.collection("users").doc(workerId).get();
  const base = user.exists ? workerDiscovery(workerId, user.data()) : null;
  const ref = db.collection("worker_discovery").doc(workerId);
  if (!base) {
    if (commit && (await ref.get()).exists) await ref.delete();
    return null;
  }
  const lower = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const [active, scheduled, periods] = await Promise.all([
    db.collection("assignments").where("workerId", "==", workerId)
      .where("status", "==", "active").get(),
    db.collection("assignments").where("workerId", "==", workerId)
      .where("status", "==", "scheduled").get(),
    db.collection("worker_unavailability").where("workerId", "==", workerId)
      .where("endDate", ">=", lower).get(),
  ]);
  const assignments = new Map([...active.docs, ...scheduled.docs]
    .map((doc) => [doc.id, doc.data()]));
  const effective = deriveEffectiveAvailability(user.data(),
    [...assignments.values()],
    periods.docs.map((doc) => doc.data()), now);
  const timestamp = (value) => value == null ? null :
    admin.firestore.Timestamp.fromDate(value);
  const {manualAvailabilityStatus: _manual, ...safeEffective} = effective;
  const value = {...base, ...safeEffective,
    effectiveAvailableFrom: timestamp(effective.effectiveAvailableFrom),
    nextUnavailableFrom: timestamp(effective.nextUnavailableFrom),
    nextUnavailableUntil: timestamp(effective.nextUnavailableUntil),
    nextAvailabilityRefreshAt: timestamp(effective.nextAvailabilityRefreshAt),
    availabilityStatus: effective.effectiveAvailabilityStatus,
    availableFrom: timestamp(effective.effectiveAvailableFrom)};
  const previous = await ref.get();
  if (commit && (!previous.exists || !isDeepStrictEqual(previous.data(), value))) {
    await ref.set(value);
  }
  const publicRef = db.collection("public_profiles").doc(workerId);
  const publicDoc = await publicRef.get();
  if (commit && publicDoc.exists && (
    publicDoc.data().availabilityStatus !== value.availabilityStatus ||
    !isDeepStrictEqual(publicDoc.data().availableFrom, value.availableFrom))) {
    await publicRef.update({availabilityStatus: value.availabilityStatus,
      availableFrom: value.availableFrom});
  }
  return {effective, changed: !previous.exists ||
    !isDeepStrictEqual(previous.data(), value)};
}

module.exports = {recomputeWorkerAvailability};
