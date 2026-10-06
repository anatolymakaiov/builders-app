"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {resolveEmployerEntitlements, planForBilling} =
  require("../employer_entitlements");

const now = new Date("2026-10-06T12:00:00Z");
const employer = (billing) => ({role: "employer", profileComplete: true, billing});

test("Starter locks paid discovery; Growth and Pro include it", () => {
  const active = {subscriptionStatus: "active", billingStatus: "active"};
  const starter = resolveEmployerEntitlements(employer({...active,
    planId: "starter"}), now);
  const growth = resolveEmployerEntitlements(employer({...active,
    planId: "growth"}), now);
  const pro = resolveEmployerEntitlements(employer({...active,
    planId: "pro"}), now);
  assert.equal(starter.canPostVacancies, true);
  assert.equal(starter.canUseCandidateSearch, false);
  assert.equal(starter.canInviteToVacancy, false);
  assert.equal(growth.canUseCandidateSearch, true);
  assert.equal(growth.canUseTalentPool, true);
  assert.equal(growth.vacancyInviteMonthlyLimit, 200);
  assert.equal(pro.canUseAdvancedEmployerTools, true);
  assert.equal(pro.vacancyInviteMonthlyLimit, 1000);
});

test("trial, expiry, cancellation and paid grace are explicit", () => {
  const trial = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "trial", trialEndsAt: new Date("2026-10-07")}), now);
  const expiredTrial = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "trial", trialEndsAt: new Date("2026-10-05")}), now);
  const cancelled = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "cancelled", currentPeriodEnd: new Date("2026-10-07")}), now);
  const ended = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "cancelled", currentPeriodEnd: new Date("2026-10-05")}), now);
  const pastDue = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "active", billingStatus: "past_due"}), now);
  assert.equal(trial.canUseCandidateSearch, true);
  assert.equal(expiredTrial.canUseCandidateSearch, false);
  assert.equal(cancelled.canUseCandidateSearch, true);
  assert.equal(cancelled.canPostVacancies, false);
  assert.equal(ended.canUseCandidateSearch, false);
  assert.equal(pastDue.canUseCandidateSearch, false);
});

test("legacy paid slot mapping and additive outreach add-on", () => {
  assert.equal(planForBilling({vacancySlotLimit: 10}).id, "growth");
  const legacy = resolveEmployerEntitlements(employer({vacancySlotLimit: 10,
    subscriptionStatus: "active"}), now);
  assert.equal(legacy.canUseTalentPool, true);
  const addon = resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "active", talentOutreachAddonStatus: "active"}), now);
  assert.equal(addon.canUseTalentOutreach, true);
  assert.equal(addon.talentOutreachMonthlyLimit, 50);
  assert.equal(resolveEmployerEntitlements(employer({planId: "growth",
    subscriptionStatus: "expired", talentOutreachAddonStatus: "active"}), now)
    .canUseTalentOutreach, false);
});
