"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {adminSubscriptionSummary} = require("../admin_subscription_summary");

test("Admin subscription summary reuses entitlements and omits payment secrets", () => {
  const now = new Date("2026-10-09T12:00:00Z");
  const user = {role: "employer", companyName: "Build Co", active: true,
    profileComplete: true, billing: {
      activePlanId: "growth", subscriptionStatus: "active",
      vacancySlotLimit: 10, usedJobPosts: 2,
      directDebitMandateId: "secret-mandate",
    }};
  const summary = adminSubscriptionSummary("employer-1", user,
    {vacancyInvitations: 12, talentOutreach: 3}, now);
  assert.equal(summary.data.planName, "Growth");
  assert.equal(summary.data.invitationLimit, 200);
  assert.equal(summary.data.invitationUsed, 12);
  assert.equal(summary.data.usedJobPosts, 2);
  assert.equal(JSON.stringify(summary).includes("secret-mandate"), false);
});
