"use strict";

const PLANS = Object.freeze({
  starter: Object.freeze({id: "starter", name: "Starter", amountPence: 4900,
    currency: "GBP", interval: "monthly", vacancySlotLimit: 3,
    candidateSearch: false, talentPool: false, invitationBatchLimit: 0,
    invitationDailyLimit: 0, invitationMonthlyLimit: 0,
    advancedEmployerTools: false}),
  growth: Object.freeze({id: "growth", name: "Growth", amountPence: 9900,
    currency: "GBP", interval: "monthly", vacancySlotLimit: 10,
    candidateSearch: true, talentPool: true, invitationBatchLimit: 20,
    invitationDailyLimit: 100, invitationMonthlyLimit: 200,
    advancedEmployerTools: false}),
  pro: Object.freeze({id: "pro", name: "Pro", amountPence: 19900,
    currency: "GBP", interval: "monthly", vacancySlotLimit: 25,
    candidateSearch: true, talentPool: true, invitationBatchLimit: 20,
    invitationDailyLimit: 100, invitationMonthlyLimit: 1000,
    advancedEmployerTools: true}),
});

function asDate(value) {
  if (!value) return null;
  const date = typeof value.toDate === "function" ? value.toDate() :
    value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function planForBilling(billing) {
  const id = String(billing.planId || billing.currentPlanId ||
    billing.activePlanId || billing.currentPlan || "").toLowerCase();
  if (PLANS[id]) return PLANS[id];
  if (id) return null;
  // Older paid records sometimes have only the protected slot entitlement.
  const slots = Number(billing.vacancySlotLimit || billing.includedJobSlots || 0);
  if (slots >= 25) return PLANS.pro;
  if (slots >= 10) return PLANS.growth;
  if (slots >= 3) return PLANS.starter;
  return null;
}

function resolveEmployerEntitlements(user, now = new Date()) {
  const billing = user?.billing && typeof user.billing === "object" ? user.billing : {};
  const plan = planForBilling(billing);
  const legacyTrial = !billing.subscriptionStatus &&
    (billing.trialActive === true || billing.trialStatus === "active");
  const status = legacyTrial ? "trial" : String(
    billing.subscriptionStatus || billing.billingStatus || "inactive")
    .toLowerCase();
  const billingStatus = String(billing.billingStatus || "").toLowerCase();
  const trialEnd = asDate(billing.trialEndsAt || billing.trialEndDate);
  const periodEnd = asDate(billing.currentPeriodEnd || billing.activeUntil);
  const blocked = ["past_due", "payment_method_required", "suspended", "failed",
    "expired", "inactive"].includes(status) ||
    ["past_due", "payment_method_required", "suspended", "failed"].includes(billingStatus);
  const trial = ["trial", "trialing"].includes(status) &&
    trialEnd != null && trialEnd > now;
  const paid = status === "active" ||
    (status === "cancelled" && periodEnd != null && periodEnd > now);
  const active = Boolean(plan && !blocked && (trial || paid) &&
    ["employer", "company"].includes(user?.role) &&
    user?.active !== false && user?.suspended !== true &&
    user?.accountDeleted !== true && user?.deleted !== true);
  const addonEnd = asDate(billing.talentOutreachAddonEndsAt);
  const registered = user?.profileComplete === true ||
    user?.onboardingComplete === true || user?.profileCreated === true ||
    user?.registrationFinalizedAt != null ||
    (user?.profileComplete == null && user?.onboardingComplete == null &&
      user?.profileCreated == null && user?.draft !== true &&
      user?.pendingRegistration !== true &&
      typeof user?.companyName === "string" && user.companyName.length > 0);
  const entitled = active && registered;
  const addon = entitled && billing.talentOutreachAddonStatus === "active" &&
    (!addonEnd || addonEnd > now);
  return {
    planId: plan?.id || "", planName: plan?.name || "No plan",
    subscriptionStatus: trial ? "trial" : status,
    subscriptionEndsAt: periodEnd, trialEndsAt: trialEnd,
    canPostVacancies: entitled && status !== "cancelled",
    maxActiveVacancies: entitled ? plan.vacancySlotLimit : 0,
    canUseCandidateSearch: entitled && plan.candidateSearch,
    canUseTalentPool: entitled && plan.talentPool,
    canInviteToVacancy: entitled && plan.invitationMonthlyLimit > 0,
    vacancyInviteBatchLimit: entitled ? plan.invitationBatchLimit : 0,
    vacancyInviteDailyLimit: entitled ? plan.invitationDailyLimit : 0,
    vacancyInviteMonthlyLimit: entitled ? plan.invitationMonthlyLimit : 0,
    canUseTalentOutreach: addon,
    talentOutreachDailyLimit: addon ? 5 : 0,
    talentOutreachMonthlyLimit: addon ? 50 : 0,
    canUseAdvancedEmployerTools: entitled && plan.advancedEmployerTools,
    talentOutreachAddonStatus: addon ? "active" : "locked",
  };
}

module.exports = {PLANS, planForBilling, resolveEmployerEntitlements};
