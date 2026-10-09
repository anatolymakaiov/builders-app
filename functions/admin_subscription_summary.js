"use strict";

const {resolveEmployerEntitlements} = require("./employer_entitlements");

function adminSubscriptionSummary(id, user, usage, now = new Date()) {
  const billing = user.billing || {};
  const entitlement = resolveEmployerEntitlements(user, now);
  return {id, data: {
    role: user.role,
    companyName: String(user.companyName || user.businessName || "Company"),
    active: user.active !== false,
    moderationHold: user.moderationHold === true,
    planId: entitlement.planId,
    planName: entitlement.planName,
    subscriptionStatus: entitlement.subscriptionStatus,
    subscriptionEndsAt: entitlement.subscriptionEndsAt,
    trialEndsAt: entitlement.trialEndsAt,
    vacancySlotLimit: Number(billing.vacancySlotLimit ||
      entitlement.maxActiveVacancies || 0),
    usedJobPosts: Number(billing.usedJobPosts || 0),
    invitationUsed: Number(usage?.vacancyInvitations || 0),
    invitationLimit: entitlement.vacancyInviteMonthlyLimit,
    outreachUsed: Number(usage?.talentOutreach || 0),
    outreachLimit: entitlement.talentOutreachMonthlyLimit,
    addonStatus: entitlement.talentOutreachAddonStatus,
  }};
}

module.exports = {adminSubscriptionSummary};
