"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeTestEnvironment, assertFails, assertSucceeds} =
  require("@firebase/rules-unit-testing");

test("Phase 2 private profile and role cutover", async () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
    "Run via firebase emulators:exec --only firestore");
  const env = await initializeTestEnvironment({
    projectId: "stroyka-phase2-rules",
    firestore: {rules: fs.readFileSync(path.join(__dirname,
      "../../firestore.rules"), "utf8")},
  });
  try {
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc("users/worker").set({role: "worker", name: "Worker",
        profileComplete: true});
      await db.doc("users/employer").set({role: "employer", companyName: "Co",
        profileComplete: true});
      await db.doc("users/otherWorker").set({role: "worker", name: "Other",
        profileComplete: true});
      await db.doc("users/legacy").set({role: "worker", name: "Legacy"});
      await db.doc("users/draft").set({role: "worker", profileComplete: false,
        onboardingComplete: false});
      await db.doc("users/admin").set({role: "admin"});
      await db.doc("public_profiles/worker").set({displayName: "Worker"});
      await db.doc("worker_discovery/worker").set({availabilityStatus: "unknown"});
    });
    const worker = env.authenticatedContext("worker").firestore();
    const employer = env.authenticatedContext("employer").firestore();
    const outsider = env.authenticatedContext("outsider").firestore();
    const legacy = env.authenticatedContext("legacy").firestore();
    const draft = env.authenticatedContext("draft").firestore();
    const admin = env.authenticatedContext("admin").firestore();
    const guest = env.unauthenticatedContext().firestore();

    await assertSucceeds(worker.doc("users/worker").get());
    await assertSucceeds(worker.doc("users/worker").update({name: "Updated"}));
    await assertFails(worker.doc("users/employer").get());
    await assertFails(worker.doc("users/otherWorker").get());
    await assertFails(employer.doc("users/otherWorker").get());
    await assertFails(worker.collection("users").get());
    await assertSucceeds(admin.doc("users/worker").get());
    await assertSucceeds(admin.collection("users").get());
    await assertSucceeds(outsider.doc("users/outsider").set({role: "worker",
      profileComplete: false}));
    await assertSucceeds(outsider.doc("users/outsider").update({role: "employer"}));
    await assertSucceeds(worker.doc("public_profiles/employer").get());
    await assertFails(guest.doc("public_profiles/worker").get());
    await assertFails(worker.doc("public_profiles/worker").set({phone: "secret"}));
    await assertFails(employer.doc("worker_discovery/worker").set({phone: "secret"}));
    await assertFails(guest.doc("worker_discovery/worker").get());
    await assertSucceeds(worker.doc("worker_discovery/worker").get());
    await assertFails(employer.doc("worker_discovery/worker").get());
    await assertFails(worker.doc("users/worker").update({role: "admin"}));
    await assertFails(worker.doc("users/worker").update({role: "employer"}));
    await assertFails(employer.doc("users/employer").update({role: "worker"}));
    await assertFails(legacy.doc("users/legacy").update({role: "employer"}));
    await assertFails(worker.doc("users/worker").update({profileComplete: false}));
    await assertFails(worker.doc("users/worker").delete());
    await assertFails(worker.doc("users/worker").update({companyId: "other"}));
    await assertFails(worker.doc("users/worker").update({vacancySlotLimit: 99}));
    await assertFails(outsider.doc("users/outsider").set({role: "admin"}));
    await assertFails(outsider.doc("users/outsider").set({role: "worker", isAdmin: true}));
    await assertFails(outsider.doc("users/forged").set({role: "employer",
      billing: {currentPlanId: "pro"}}));
    await assertFails(outsider.doc("users/outsider").update({uid: "worker"}));
    await assertFails(worker.doc("users/worker").update({isAdmin: true}));
    await assertFails(worker.doc("users/worker").update({permissions: ["admin"]}));
    await assertSucceeds(draft.doc("users/draft").update({role: "employer"}));
    await assertFails(draft.doc("users/draft").update({profileComplete: true}));
    await assertFails(draft.doc("users/draft").update({emailVerified: true,
      verifiedEmail: "forged@example.com"}));
    await assertFails(draft.doc("users/draft").update({phoneVerified: true,
      verifiedNormalizedPhone: "+447700900123"}));
    await assertFails(draft.doc("users/draft").update({
      billingEmail: "forged@example.com", billingEmailVerified: true,
    }));
    await assertFails(draft.doc("users/draft").update({
      billing: {billingEmail: "forged@example.com", billingEmailVerified: true},
    }));

    const verified = env.authenticatedContext("verified", {
      email: "verified@example.com", email_verified: true,
    }).firestore();
    await assertSucceeds(verified.doc("users/verified").set({role: "worker",
      name: "Verified", emailVerified: true,
      verifiedEmail: "verified@example.com", profileComplete: true}));
    await assertFails(verified.doc("users/verified").update({role: "employer"}));
    await assertSucceeds(verified.doc("users/verified").update({name: "Edited"}));
    await assertSucceeds(verified.doc("users/verified").update({
      accountDeleted: true, deleted: true, profileComplete: false,
    }));
    await assertFails(verified.doc("users/verified").update({role: "employer"}));
    const verifiedEmployer = env.authenticatedContext("verifiedEmployer", {
      email: "employer@example.com", email_verified: true,
      phone_number: "+447700900123",
    }).firestore();
    await assertSucceeds(verifiedEmployer.doc("users/verifiedEmployer").set({
      role: "employer", companyName: "Verified Co", emailVerified: true,
      verifiedEmail: "employer@example.com", phoneVerified: true,
      verifiedNormalizedPhone: "+447700900123", profileComplete: true,
      billingEmail: "employer@example.com",
      billing: {billingEmail: "employer@example.com",
        billingEmailVerified: true, invoiceDetails: {vatNumber: ""}},
    }));
    await assertSucceeds(verifiedEmployer.doc("users/verifiedEmployer")
      .update({companyName: "Edited Co"}));
    await assertSucceeds(verifiedEmployer.doc("users/verifiedEmployer")
      .update({billingEmail: "employer@example.com",
        billingEmailVerified: true}));
    await assertSucceeds(verifiedEmployer.doc("users/verifiedEmployer")
      .update({billing: {billingEmail: "employer@example.com",
        billingEmailVerified: true, invoiceDetails: {vatNumber: ""}}}));
    await assertFails(verifiedEmployer.doc("users/verifiedEmployer")
      .update({role: "worker"}));
    const completing = env.authenticatedContext("completing", {
      email: "new@example.com", email_verified: true,
    }).firestore();
    await assertSucceeds(completing.doc("users/completing").set({
      role: "worker", profileComplete: false,
    }));
    await assertSucceeds(completing.doc("users/completing").update({
      role: "employer", profileComplete: false,
    }));
    await assertFails(completing.doc("users/completing").update({
      companyName: "New Co", emailVerified: true,
      verifiedEmail: "new@example.com", profileComplete: true,
    }));
    await assertSucceeds(completing.doc("users/completing").update({
      role: "worker", profileComplete: false,
    }));
    await assertSucceeds(completing.doc("users/completing").update({
      name: "New Worker", emailVerified: true,
      verifiedEmail: "new@example.com", profileComplete: true,
    }));
    await assertFails(completing.doc("users/completing")
      .update({role: "employer"}));
  } finally {
    await env.cleanup();
  }
});
