const crypto = require("crypto");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

admin.initializeApp();

const idealPostcodesApiKey = defineSecret("IDEAL_POSTCODES_API_KEY");
const goCardlessAccessToken = defineSecret("GOCARDLESS_ACCESS_TOKEN");
const goCardlessWebhookSecret = defineSecret("GOCARDLESS_WEBHOOK_SECRET");
const GOCARDLESS_SANDBOX_API_BASE = "https://api-sandbox.gocardless.com";
const GOCARDLESS_API_VERSION = "2015-07-06";
const DEFAULT_FUNCTION_REGION = "us-central1";
const PAYMENT_GRACE_DAYS = 3;
const STROYKA_COMMERCIAL_PLANS = {
  starter: {
    id: "starter",
    name: "Starter",
    amountPence: 4900,
    currency: "GBP",
    interval: "monthly",
    vacancySlotLimit: 3,
  },
  growth: {
    id: "growth",
    name: "Growth",
    amountPence: 9900,
    currency: "GBP",
    interval: "monthly",
    vacancySlotLimit: 10,
  },
  pro: {
    id: "pro",
    name: "Pro",
    amountPence: 19900,
    currency: "GBP",
    interval: "monthly",
    vacancySlotLimit: 25,
  },
};

const DEFAULT_NOTIFICATION_PREFERENCES = {
  enabled: true,
  jobAlerts: true,
  applicationUpdates: true,
  offers: true,
  messages: true,
  adminMessages: true,
  billing: true,
  supportReplies: true,
  policyUpdates: true,
  sound: true,
  badges: true,
};

function normalizeUkPostcode(value) {
  const clean = String(value || "")
    .replace(/[^A-Za-z0-9]/g, "")
    .toUpperCase();
  if (clean.length <= 3) return clean;
  return `${clean.slice(0, -3)} ${clean.slice(-3)}`;
}

function isValidUkPostcode(value) {
  return /^[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}$/i.test(
    normalizeUkPostcode(value),
  );
}

function cleanText(value) {
  return typeof value === "string" ? value.trim() : "";
}

function planForId(planId) {
  const id = cleanText(planId).toLowerCase();
  return STROYKA_COMMERCIAL_PLANS[id] || null;
}

function publicPlanList() {
  return Object.values(STROYKA_COMMERCIAL_PLANS).map((plan) => ({ ...plan }));
}

function safeNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function mapIdealAddress(address) {
  return {
    line1: cleanText(address.line_1),
    line2: cleanText(address.line_2),
    line3: cleanText(address.line_3),
    town: cleanText(address.post_town),
    county: cleanText(address.county),
    postcode: normalizeUkPostcode(address.postcode),
    country: cleanText(address.country) || "United Kingdom",
    latitude: safeNumber(address.latitude),
    longitude: safeNumber(address.longitude),
    uprn: cleanText(address.uprn),
  };
}

exports.lookupIdealPostcodeAddresses = onCall(
  {
    secrets: [idealPostcodesApiKey],
    timeoutSeconds: 12,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to search for an address.",
      );
    }

    const postcode = normalizeUkPostcode(request.data && request.data.postcode);
    if (!postcode || !isValidUkPostcode(postcode)) {
      throw new HttpsError(
        "invalid-argument",
        "Enter a valid UK postcode.",
      );
    }

    const apiKey = idealPostcodesApiKey.value();
    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Address lookup is not configured.",
      );
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);

    try {
      const url = new URL(
        `https://api.ideal-postcodes.co.uk/v1/postcodes/${encodeURIComponent(postcode)}`,
      );
      url.searchParams.set("api_key", apiKey);

      const response = await fetch(url, {
        method: "GET",
        signal: controller.signal,
        headers: {
          Accept: "application/json",
        },
      });

      if (response.status === 404) {
        throw new HttpsError("not-found", "No addresses found.");
      }

      if (response.status === 402 || response.status === 429) {
        throw new HttpsError(
          "resource-exhausted",
          "Address lookup is temporarily unavailable.",
        );
      }

      if (!response.ok) {
        throw new HttpsError(
          "unavailable",
          "Address lookup is temporarily unavailable.",
        );
      }

      const body = await response.json();
      const result = Array.isArray(body.result) ? body.result : [];
      const addresses = result.map(mapIdealAddress).filter((address) => {
        return address.line1 || address.town || address.postcode;
      });

      if (addresses.length === 0) {
        throw new HttpsError("not-found", "No addresses found.");
      }

      return {
        postcode,
        addresses,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      if (error && error.name === "AbortError") {
        throw new HttpsError(
          "deadline-exceeded",
          "Address lookup timed out.",
        );
      }
      throw new HttpsError(
        "unavailable",
        "Address lookup is temporarily unavailable.",
      );
    } finally {
      clearTimeout(timeout);
    }
  },
);

function functionBaseUrl(functionName) {
  const projectId =
    process.env.GCLOUD_PROJECT ||
    process.env.GCP_PROJECT ||
    "builder-jobs-app";
  const region = process.env.FUNCTION_REGION || DEFAULT_FUNCTION_REGION;
  return `https://${region}-${projectId}.cloudfunctions.net/${functionName}`;
}

function htmlResponse(title, message) {
  const safeTitle = String(title || "STROYKA").replace(/[<>&"]/g, "");
  const safeMessage = String(message || "").replace(/[<>&"]/g, "");
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${safeTitle}</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #111827;
        color: #f9fafb;
      }
      main {
        max-width: 520px;
        padding: 32px;
        text-align: center;
      }
      h1 {
        margin: 0 0 12px;
        font-size: 28px;
      }
      p {
        margin: 0;
        color: #d1d5db;
        line-height: 1.5;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>${safeTitle}</h1>
      <p>${safeMessage}</p>
    </main>
  </body>
</html>`;
}

function gocardlessHeaders(accessToken, idempotencyKey) {
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    Accept: "application/json",
    "GoCardless-Version": GOCARDLESS_API_VERSION,
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  return headers;
}

async function goCardlessPost(path, payload, accessToken, idempotencyKey) {
  const response = await fetch(`${GOCARDLESS_SANDBOX_API_BASE}${path}`, {
    method: "POST",
    headers: gocardlessHeaders(accessToken, idempotencyKey),
    body: JSON.stringify(payload),
  });

  const text = await response.text();
  let body = {};
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (error) {
      body = { raw: text };
    }
  }

  if (!response.ok) {
    console.error(
      "GOCARDLESS SANDBOX API ERROR",
      JSON.stringify({
        path,
        status: response.status,
        errorCode: body.error && body.error.code,
        errorType: body.error && body.error.type,
      }),
    );
    throw new HttpsError(
      "unavailable",
      "Direct Debit setup is temporarily unavailable.",
    );
  }

  return body;
}

async function goCardlessGet(path, accessToken) {
  const response = await fetch(`${GOCARDLESS_SANDBOX_API_BASE}${path}`, {
    method: "GET",
    headers: gocardlessHeaders(accessToken),
  });

  const text = await response.text();
  let body = {};
  if (text) {
    try {
      body = JSON.parse(text);
    } catch (error) {
      body = { raw: text };
    }
  }

  if (!response.ok) {
    console.error(
      "GOCARDLESS SANDBOX API ERROR",
      JSON.stringify({
        path,
        status: response.status,
        errorCode: body.error && body.error.code,
        errorType: body.error && body.error.type,
      }),
    );
    throw new HttpsError(
      "unavailable",
      "Could not refresh Direct Debit status.",
    );
  }

  return body;
}

function isSlotOccupyingJob(job) {
  const status = cleanText(job.status).toLowerCase();
  const moderationStatus = cleanText(job.moderationStatus);
  return moderationStatus === "approved" &&
    ["active", "published", "open"].includes(status || "active") &&
    job.deleted !== true &&
    job.isDeleted !== true &&
    job.active !== false &&
    job.billingSuspended !== true &&
    job.employerDeleted !== true &&
    job.companyDeleted !== true;
}

async function countOccupiedVacancySlots(employerId) {
  const snapshot = await admin
    .firestore()
    .collection("jobs")
    .where("ownerId", "==", employerId)
    .where("moderationStatus", "==", "approved")
    .get();
  return snapshot.docs.filter((doc) => isSlotOccupyingJob(doc.data() || {}))
    .length;
}

function activeTrialEntitlement(billing) {
  const trialActive = billing.trialActive === true ||
    cleanText(billing.trialStatus).toLowerCase() === "active" ||
    cleanText(billing.subscriptionStatus).toLowerCase() === "trial";
  const trialEndsAt = billing.trialEndsAt || billing.trialEndDate;
  return trialActive &&
    trialEndsAt &&
    typeof trialEndsAt.toDate === "function" &&
    trialEndsAt.toDate().getTime() > Date.now();
}

function activePaidEntitlement(billing) {
  return cleanText(billing.billingStatus).toLowerCase() === "active" ||
    cleanText(billing.subscriptionStatus).toLowerCase() === "active";
}

function billingBlocksNewVacancy(billing) {
  return ["past_due", "suspended", "cancelled", "failed"].includes(
    cleanText(billing.billingStatus || billing.subscriptionStatus)
      .toLowerCase(),
  );
}

function billingPlan(billing) {
  return planForId(
    billing.planId ||
      billing.activePlanId ||
      billing.currentPlan ||
      billing.pendingPlan,
  );
}

async function safeBillingStatus(data, employerId) {
  const billing = data.billing && typeof data.billing === "object"
    ? data.billing
    : {};
  const plan = billingPlan(billing);
  const occupiedVacancySlots = employerId
    ? await countOccupiedVacancySlots(employerId)
    : 0;
  const vacancySlotLimit = plan ? plan.vacancySlotLimit : 0;
  return {
    provider: billing.provider || "",
    environment: billing.environment || "",
    plans: publicPlanList(),
    planId: plan ? plan.id : cleanText(billing.planId),
    planName: plan ? plan.name : cleanText(billing.planName),
    monthlyPrice: plan ? plan.amountPence / 100 : null,
    planAmountPence: plan ? plan.amountPence : null,
    currency: plan ? plan.currency : cleanText(billing.currency),
    billingInterval: plan ? plan.interval : cleanText(billing.billingInterval),
    vacancySlotLimit,
    occupiedVacancySlots,
    availableVacancySlots: Math.max(vacancySlotLimit - occupiedVacancySlots, 0),
    billingStatus: billing.billingStatus || billing.subscriptionStatus || "",
    subscriptionStatus: billing.subscriptionStatus || "",
    paymentStatus: billing.paymentStatus || "",
    trialStartedAt: billing.trialStartedAt || billing.trialStartDate || null,
    trialEndsAt: billing.trialEndsAt || billing.trialEndDate || null,
    goCardlessBillingRequestId: billing.goCardlessBillingRequestId || "",
    goCardlessBillingRequestFlowId: billing.goCardlessBillingRequestFlowId || "",
    goCardlessMandateId: billing.goCardlessMandateId || "",
    goCardlessSubscriptionId: billing.goCardlessSubscriptionId || "",
    currentPeriodStart: billing.currentPeriodStart || null,
    currentPeriodEnd: billing.currentPeriodEnd || null,
    nextChargeDate: billing.nextChargeDate || billing.nextBillingDate || null,
    lastPaymentStatus: billing.lastPaymentStatus || "",
    lastPaymentAt: billing.lastPaymentAt || null,
    paymentActionRequired: billing.paymentActionRequired === true,
    paymentGraceStartedAt: billing.paymentGraceStartedAt || null,
    paymentGraceEndsAt: billing.paymentGraceEndsAt || null,
    updatedAt: billing.updatedAt || null,
  };
}

function verifyGoCardlessWebhookSignature(rawBody, signature, secret) {
  if (!rawBody || !signature || !secret) return false;
  const computed = crypto
    .createHmac("sha256", secret)
    .update(rawBody)
    .digest("hex");
  const received = Buffer.from(String(signature), "utf8");
  const expected = Buffer.from(computed, "utf8");
  return received.length === expected.length &&
    crypto.timingSafeEqual(received, expected);
}

async function employerRefByBillingField(field, value) {
  const clean = cleanText(value);
  if (!clean) return null;
  const snapshot = await admin
    .firestore()
    .collection("users")
    .where(`billing.${field}`, "==", clean)
    .limit(1)
    .get();
  if (snapshot.empty) return null;
  return snapshot.docs[0].ref;
}

async function updateEmployerBilling(employerRef, updates) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  await employerRef.set(
    {
      billing: {
        ...updates,
        provider: "gocardless",
        environment: "sandbox",
        updatedAt: now,
      },
      directDebit: {
        ...updates,
        provider: "gocardless",
        environment: "sandbox",
        updatedAt: now,
      },
    },
    { merge: true },
  );
  await employerRef
    .collection("billing")
    .doc("gocardlessSandboxDirectDebit")
    .set(
      {
        ...updates,
        provider: "gocardless",
        environment: "sandbox",
        updatedAt: now,
      },
      { merge: true },
    );
}

async function createBillingNotificationOnce(employerId, notificationId, payload) {
  if (!employerId || !notificationId) return;
  const ref = admin
    .firestore()
    .collection("users")
    .doc(employerId)
    .collection("notifications")
    .doc(notificationId);
  const snap = await ref.get();
  if (snap.exists) return;
  await ref.set({
    notificationId,
    userId: employerId,
    type: "billing",
    category: "billing",
    read: false,
    badgeEligible: true,
    pushEligible: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...payload,
  });
}

async function startPaymentGrace(employerRef, reason, eventId) {
  const snap = await employerRef.get();
  const data = snap.data() || {};
  const billing = data.billing || {};
  if (billing.paymentGraceStartedAt && billing.paymentGraceEndsAt) {
    await updateEmployerBilling(employerRef, {
      billingStatus: "past_due",
      subscriptionStatus: "past_due",
      paymentStatus: "failed",
      paymentActionRequired: true,
      paymentFailureReason: reason,
    });
    return;
  }

  const startedAt = new Date();
  const endsAt = new Date(
    startedAt.getTime() + PAYMENT_GRACE_DAYS * 24 * 60 * 60 * 1000,
  );
  await updateEmployerBilling(employerRef, {
    billingStatus: "past_due",
    subscriptionStatus: "past_due",
    paymentStatus: "failed",
    paymentActionRequired: true,
    paymentFailureReason: reason,
    paymentGraceStartedAt: admin.firestore.Timestamp.fromDate(startedAt),
    paymentGraceEndsAt: admin.firestore.Timestamp.fromDate(endsAt),
  });
  await createBillingNotificationOnce(
    employerRef.id,
    `billing_grace_started_${eventId || startedAt.getTime()}`,
    {
      title: "Direct Debit payment needs attention",
      message:
        "Your Direct Debit payment could not be completed. Please update your Direct Debit within 3 days to keep your vacancies active.",
      body:
        "Your Direct Debit payment could not be completed. Please update your Direct Debit within 3 days to keep your vacancies active.",
      targetType: "billing",
      targetId: employerRef.id,
    },
  );
}

async function clearPaymentGrace(employerRef) {
  await updateEmployerBilling(employerRef, {
    billingStatus: "active",
    subscriptionStatus: "active",
    paymentStatus: "paid",
    paymentActionRequired: false,
    paymentFailureReason: "",
    paymentGraceStartedAt: admin.firestore.FieldValue.delete(),
    paymentGraceEndsAt: admin.firestore.FieldValue.delete(),
  });
  await restoreBillingSuspendedVacancies(employerRef);
}

async function restoreBillingSuspendedVacancies(employerRef) {
  const employerSnap = await employerRef.get();
  const employer = employerSnap.data() || {};
  const plan = billingPlan(employer.billing || {});
  if (!plan) return { restored: 0, skipped: 0 };

  const occupied = await countOccupiedVacancySlots(employerRef.id);
  let available = Math.max(plan.vacancySlotLimit - occupied, 0);
  if (available <= 0) return { restored: 0, skipped: 0 };

  const snapshot = await admin
    .firestore()
    .collection("jobs")
    .where("ownerId", "==", employerRef.id)
    .where("billingSuspended", "==", true)
    .get();
  const batch = admin.firestore().batch();
  let restored = 0;
  let skipped = 0;
  for (const doc of snapshot.docs) {
    const job = doc.data() || {};
    if (available <= 0) {
      skipped += 1;
      continue;
    }
    if (job.deleted === true || job.companyDeleted === true || job.employerDeleted === true) {
      skipped += 1;
      continue;
    }
    batch.set(doc.ref, {
      active: true,
      status: cleanText(job.preBillingSuspensionStatus) || "active",
      billingSuspended: false,
      billingRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    restored += 1;
    available -= 1;
  }
  if (restored > 0) await batch.commit();
  return { restored, skipped };
}

function isActiveBillingEntitlement(billing) {
  return activeTrialEntitlement(billing) || activePaidEntitlement(billing);
}

function safeJobPayload(data) {
  const payload = data && typeof data === "object" && !Array.isArray(data)
    ? { ...data }
    : {};
  delete payload.id;
  delete payload.createdAt;
  delete payload.updatedAt;
  delete payload.moderatedAt;
  delete payload.billingSuspended;
  delete payload.billingSuspendedAt;
  delete payload.preBillingSuspensionStatus;
  delete payload.slotCountedAt;
  delete payload.approvedAt;
  return payload;
}

function materialJobEditFields(data) {
  const payload = safeJobPayload(data);
  const blocked = new Set([
    "ownerId",
    "employerId",
    "createdBy",
    "moderationStatus",
    "status",
    "visibility",
    "filledPositions",
    "remainingPositions",
    "slotDecrementApplicationIds",
  ]);
  return Object.fromEntries(
    Object.entries(payload).filter(([key]) => !blocked.has(key)),
  );
}

async function assertEmployerCanUseVacancySlot(employerId, transaction) {
  const firestore = admin.firestore();
  const userRef = firestore.collection("users").doc(employerId);
  const userSnap = transaction
    ? await transaction.get(userRef)
    : await userRef.get();
  const user = userSnap.data() || {};
  if (!userSnap.exists || cleanText(user.role).toLowerCase() !== "employer") {
    throw new HttpsError("permission-denied", "Only employers can publish vacancies.");
  }
  if (!isActiveUserDocument(user)) {
    throw new HttpsError("permission-denied", "Your profile is temporarily suspended.");
  }

  const billing = user.billing || {};
  const plan = billingPlan(billing);
  if (!plan) {
    throw new HttpsError("failed-precondition", "Choose a STROYKA billing plan before publishing vacancies.");
  }
  if (billingBlocksNewVacancy(billing) || !isActiveBillingEntitlement(billing)) {
    throw new HttpsError("failed-precondition", "Billing must be active before publishing a new vacancy.");
  }

  const occupiedVacancySlots = await countOccupiedVacancySlots(employerId);
  if (occupiedVacancySlots >= plan.vacancySlotLimit) {
    throw new HttpsError("resource-exhausted", "You have reached your active vacancy slot limit.");
  }

  return { user, billing, plan, occupiedVacancySlots };
}

async function ensureGoCardlessSubscription(employerRef, mandateId, accessToken) {
  const employerSnap = await employerRef.get();
  const employer = employerSnap.data() || {};
  const billing = employer.billing || {};
  const existingSubscriptionId = cleanText(billing.goCardlessSubscriptionId);
  if (existingSubscriptionId) return existingSubscriptionId;

  const plan = billingPlan(billing);
  if (!plan) {
    throw new HttpsError(
      "failed-precondition",
      "A valid STROYKA billing plan is required before subscription creation.",
    );
  }

  const response = await goCardlessPost(
    "/subscriptions",
    {
      subscriptions: {
        amount: plan.amountPence,
        currency: plan.currency,
        name: `${plan.name} STROYKA company subscription`,
        interval_unit: "monthly",
        interval: 1,
        metadata: {
          employer_id: employerRef.id,
          plan_id: plan.id,
          environment: "sandbox",
        },
        links: {
          mandate: mandateId,
        },
      },
    },
    accessToken,
    `stroyka-subscription-${employerRef.id}-${mandateId}`,
  );
  const subscription = response.subscriptions || response.subscription || {};
  const subscriptionId = cleanText(subscription.id);
  if (!subscriptionId) {
    throw new HttpsError(
      "unavailable",
      "GoCardless did not return a subscription.",
    );
  }

  await updateEmployerBilling(employerRef, {
    billingStatus: "active",
    subscriptionStatus: "active",
    paymentStatus: "pending",
    directDebitEnabled: true,
    mandateStatus: "active",
    directDebitMandateId: mandateId,
    goCardlessMandateId: mandateId,
    goCardlessSubscriptionId: subscriptionId,
    subscriptionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    currentPeriodStart: admin.firestore.FieldValue.serverTimestamp(),
    nextChargeDate: subscription.upcoming_payments &&
        subscription.upcoming_payments[0] &&
        subscription.upcoming_payments[0].charge_date ||
      null,
    planId: plan.id,
    planName: plan.name,
    activePlanId: plan.id,
    activePlanName: plan.name,
    currentPlan: plan.id,
    planAmountPence: plan.amountPence,
    monthlyPrice: plan.amountPence / 100,
    currency: plan.currency,
    billingInterval: plan.interval,
    vacancySlotLimit: plan.vacancySlotLimit,
  });

  return subscriptionId;
}

async function reconcileBillingRequest(employerRef, billingRequestId, accessToken) {
  const response = await goCardlessGet(
    `/billing_requests/${encodeURIComponent(billingRequestId)}`,
    accessToken,
  );
  const billingRequest = response.billing_requests || response.billing_request || {};
  const links = billingRequest.links || {};
  const mandateId = cleanText(
    links.mandate ||
      (billingRequest.mandate_request &&
        billingRequest.mandate_request.links &&
        billingRequest.mandate_request.links.mandate),
  );
  const customerId = cleanText(
    links.customer ||
      (billingRequest.resources && billingRequest.resources.customer),
  );
  const status = cleanText(billingRequest.status);

  const updates = {
    billingStatus: status === "fulfilled" ? "mandate_pending" : "setup_pending",
    goCardlessBillingRequestId: billingRequestId,
    goCardlessBillingRequestStatus: status,
  };
  if (customerId) updates.goCardlessCustomerId = customerId;
  if (mandateId) {
    updates.goCardlessMandateId = mandateId;
    updates.directDebitMandateId = mandateId;
    updates.mandateStatus = "pending";
  }
  await updateEmployerBilling(employerRef, updates);

  if (status === "fulfilled" && mandateId) {
    const mandateResponse = await goCardlessGet(
      `/mandates/${encodeURIComponent(mandateId)}`,
      accessToken,
    );
    const mandate = mandateResponse.mandates || mandateResponse.mandate || {};
    const mandateStatus = cleanText(mandate.status);
    if (mandateStatus === "active") {
      await ensureGoCardlessSubscription(employerRef, mandateId, accessToken);
    }
  }
}

async function processGoCardlessEvent(event, accessToken) {
  const resourceType = cleanText(event.resource_type);
  const action = cleanText(event.action);
  const links = event.links || {};

  if (resourceType === "billing_requests") {
    const billingRequestId = cleanText(links.billing_request);
    const employerRef = await employerRefByBillingField(
      "goCardlessBillingRequestId",
      billingRequestId,
    );
    if (!employerRef) return "billing_request_unmatched";
    if (action === "fulfilled") {
      await reconcileBillingRequest(employerRef, billingRequestId, accessToken);
      return "billing_request_fulfilled";
    }
    if (["cancelled", "failed"].includes(action)) {
      await updateEmployerBilling(employerRef, {
        billingStatus: "failed",
        subscriptionStatus: "setup_required",
        paymentStatus: "failed",
      });
      return "billing_request_failed";
    }
  }

  if (resourceType === "mandates") {
    const mandateId = cleanText(links.mandate);
    const employerRef = await employerRefByBillingField(
      "goCardlessMandateId",
      mandateId,
    );
    if (!employerRef) return "mandate_unmatched";
    if (["created", "submitted"].includes(action)) {
      await updateEmployerBilling(employerRef, {
        billingStatus: "mandate_pending",
        mandateStatus: action,
        goCardlessMandateId: mandateId,
        directDebitMandateId: mandateId,
      });
      return "mandate_pending";
    }
	    if (["active", "reinstated"].includes(action)) {
	      await ensureGoCardlessSubscription(employerRef, mandateId, accessToken);
	      await clearPaymentGrace(employerRef);
	      return "mandate_active_subscription_ensured";
	    }
	    if (["cancelled", "failed", "expired", "blocked"].includes(action)) {
	      await startPaymentGrace(employerRef, `mandate_${action}`, event.id);
	      return "mandate_inactive";
	    }
  }

  if (resourceType === "subscriptions") {
    const subscriptionId = cleanText(links.subscription);
    const employerRef = await employerRefByBillingField(
      "goCardlessSubscriptionId",
      subscriptionId,
    );
    if (!employerRef) return "subscription_unmatched";
	    if (["created", "customer_approval_granted"].includes(action)) {
	      await updateEmployerBilling(employerRef, {
	        billingStatus: "active",
	        subscriptionStatus: "active",
	        goCardlessSubscriptionId: subscriptionId,
	      });
	      await clearPaymentGrace(employerRef);
	      return "subscription_active";
	    }
	    if (["cancelled", "finished"].includes(action)) {
	      await startPaymentGrace(employerRef, `subscription_${action}`, event.id);
	      return "subscription_cancelled";
	    }
  }

  if (resourceType === "payments") {
    const paymentId = cleanText(links.payment);
    const subscriptionId = cleanText(links.subscription);
    const employerRef = await employerRefByBillingField(
      "goCardlessSubscriptionId",
      subscriptionId,
    );
    if (!employerRef) return "payment_unmatched";
	    if (["failed", "cancelled"].includes(action)) {
	      await startPaymentGrace(employerRef, `payment_${action}`, event.id);
	    } else {
	      await updateEmployerBilling(employerRef, {
	        billingStatus: "active",
	        subscriptionStatus: "active",
	        lastPaymentStatus: action,
	        lastPaymentId: paymentId,
	        lastPaymentAt: admin.firestore.FieldValue.serverTimestamp(),
	      });
	      await clearPaymentGrace(employerRef);
	    }
	    return "payment_recorded";
	  }

  return "ignored";
}

function isEmployerBillingManager(user, uid) {
  const role = String(user.role || "").trim().toLowerCase();
  return role === "employer" &&
    isActiveUserDocument(user) &&
    (
      !user.ownerId ||
      String(user.ownerId) === uid
    );
}

function goCardlessPrefilledCustomer(user) {
  const customer = {
    email: cleanText(user.billingEmail || user.email),
    country_code: "GB",
    postal_code: cleanText(
      user.billingPostcode ||
        (user.billing && user.billing.billingPostcode) ||
        user.postcode,
    ),
  };
  const companyName = cleanText(user.companyName || user.name);
  if (companyName) customer.company_name = companyName;

  return Object.fromEntries(
    Object.entries(customer).filter(([, value]) => {
      return value !== undefined && value !== null && String(value).trim();
    }),
  );
}

exports.createGoCardlessDirectDebitSetup = onCall(
  {
    secrets: [goCardlessAccessToken],
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to set up Direct Debit.",
	);

exports.createVacancyWithEntitlement = onCall(
  {
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in to post a vacancy.");
    }
    const uid = request.auth.uid;
    const firestore = admin.firestore();
    const jobData = safeJobPayload(request.data && request.data.jobData);
    const lockRef = firestore.collection("billing_entitlement_locks").doc(uid);
    const jobRef = firestore.collection("jobs").doc();

    await firestore.runTransaction(async (transaction) => {
      await transaction.get(lockRef);
      await assertEmployerCanUseVacancySlot(uid, transaction);
      transaction.set(lockRef, {
        employerId: uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      transaction.set(jobRef, {
        ...jobData,
        ownerId: uid,
        employerId: uid,
        status: "active",
        visibility: "public",
        moderationStatus: "pending_review",
        moderationReason: "",
        viewedByAdmin: false,
        billingSlotCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { jobId: jobRef.id };
  },
);

exports.submitVacancyEditReview = onCall(
  {
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in to edit a vacancy.");
    }
    const uid = request.auth.uid;
    const jobId = cleanText(request.data && request.data.jobId);
    const proposedChanges = materialJobEditFields(
      request.data && request.data.proposedChanges,
    );
    if (!jobId) {
      throw new HttpsError("invalid-argument", "Vacancy id is required.");
    }
    if (Object.keys(proposedChanges).length === 0) {
      throw new HttpsError("invalid-argument", "No vacancy changes were provided.");
    }

    const firestore = admin.firestore();
    const jobRef = firestore.collection("jobs").doc(jobId);
    const reviewRef = firestore.collection("vacancy_edit_reviews").doc();
    await firestore.runTransaction(async (transaction) => {
      const jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) {
        throw new HttpsError("not-found", "Vacancy is no longer available.");
      }
      const job = jobSnap.data() || {};
      const isOwner = job.ownerId === uid ||
        job.employerId === uid ||
        job.createdBy === uid ||
        job.userId === uid;
      if (!isOwner) {
        throw new HttpsError("permission-denied", "You cannot edit this vacancy.");
      }

      transaction.set(reviewRef, {
        originalVacancyId: jobId,
        companyId: job.ownerId || job.employerId || uid,
        employerId: job.employerId || job.ownerId || uid,
        submittedBy: uid,
        currentSnapshot: job,
        proposedChanges,
        changedFields: Object.keys(proposedChanges),
        reviewStatus: "pending",
        adminDecision: "",
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      transaction.set(jobRef, {
        pendingEditReview: true,
        latestEditReviewId: reviewRef.id,
        editReviewStatus: "pending",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return { reviewId: reviewRef.id };
  },
);

exports.reviewVacancyEdit = onCall(
  {
    timeoutSeconds: 20,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Please sign in as admin.");
    }
    const uid = request.auth.uid;
    const firestore = admin.firestore();
    const adminSnap = await firestore.collection("users").doc(uid).get();
    if (cleanText((adminSnap.data() || {}).role).toLowerCase() !== "admin") {
      throw new HttpsError("permission-denied", "Only admins can review vacancy edits.");
    }

    const reviewId = cleanText(request.data && request.data.reviewId);
    const decision = cleanText(request.data && request.data.decision).toLowerCase();
    const note = cleanText(request.data && request.data.note);
    if (!reviewId || !["approve", "reject", "treat_as_new"].includes(decision)) {
      throw new HttpsError("invalid-argument", "Choose a valid review decision.");
    }

    const reviewRef = firestore.collection("vacancy_edit_reviews").doc(reviewId);
    await firestore.runTransaction(async (transaction) => {
      const reviewSnap = await transaction.get(reviewRef);
      if (!reviewSnap.exists) {
        throw new HttpsError("not-found", "Vacancy edit review was not found.");
      }
      const review = reviewSnap.data() || {};
      if (review.reviewStatus !== "pending") {
        throw new HttpsError("failed-precondition", "This vacancy edit has already been reviewed.");
      }
      const jobId = cleanText(review.originalVacancyId);
      const jobRef = firestore.collection("jobs").doc(jobId);
      const jobSnap = await transaction.get(jobRef);
      if (!jobSnap.exists) {
        throw new HttpsError("not-found", "Original vacancy was not found.");
      }

      const jobUpdate = {
        pendingEditReview: false,
        editReviewStatus: decision,
        latestEditReviewId: reviewId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (decision === "approve") {
        Object.assign(jobUpdate, materialJobEditFields(review.proposedChanges));
        jobUpdate.editApprovedAt = admin.firestore.FieldValue.serverTimestamp();
        jobUpdate.editApprovedBy = uid;
      }

      transaction.set(jobRef, jobUpdate, { merge: true });
      transaction.set(reviewRef, {
        reviewStatus: "reviewed",
        adminDecision: decision,
        adminNote: note,
        reviewedBy: uid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    return { reviewId, decision };
  },
);
    }

    const uid = request.auth.uid;
    const userRef = admin.firestore().collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};

    if (!userSnap.exists || !isEmployerBillingManager(user, uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only the company account owner can set up Direct Debit.",
      );
    }

    const accessToken = goCardlessAccessToken.value();
    if (!accessToken) {
      throw new HttpsError(
        "failed-precondition",
        "GoCardless Sandbox is not configured.",
      );
    }
    const planId = cleanText(request.data && request.data.planId).toLowerCase();
    const plan = planForId(planId);
    if (!plan) {
      throw new HttpsError(
        "invalid-argument",
        "Choose a valid STROYKA subscription plan.",
      );
    }

    const billingRequestResponse = await goCardlessPost(
      "/billing_requests",
      {
        billing_requests: {
          mandate_request: {
            scheme: "bacs",
            currency: "GBP",
          },
          metadata: {
            employer_id: uid,
            plan_id: plan.id,
            environment: "sandbox",
          },
        },
      },
      accessToken,
      `stroyka-dd-request-${uid}-${Date.now()}`,
    );

    const billingRequest =
      billingRequestResponse.billing_requests ||
      billingRequestResponse.billing_request ||
      {};
    const billingRequestId = cleanText(billingRequest.id);

    if (!billingRequestId) {
      throw new HttpsError(
        "unavailable",
        "GoCardless did not return a billing request.",
      );
    }

    const returnUri = functionBaseUrl("goCardlessReturn");
    const exitUri = functionBaseUrl("goCardlessExit");
    const billingFlowResponse = await goCardlessPost(
      "/billing_request_flows",
      {
        billing_request_flows: {
          redirect_uri: returnUri,
          exit_uri: exitUri,
          show_success_redirect_button: true,
          prefilled_customer: goCardlessPrefilledCustomer(user),
          links: {
            billing_request: billingRequestId,
          },
        },
      },
      accessToken,
      `stroyka-dd-flow-${uid}-${billingRequestId}`,
    );

    const billingFlow =
      billingFlowResponse.billing_request_flows ||
      billingFlowResponse.billing_request_flow ||
      {};
    const billingRequestFlowId = cleanText(billingFlow.id);
    const authorisationUrl = cleanText(billingFlow.authorisation_url);

    if (!billingRequestFlowId || !authorisationUrl) {
      throw new HttpsError(
        "unavailable",
        "GoCardless did not return an authorisation URL.",
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const setupPayload = {
      provider: "gocardless",
      environment: "sandbox",
      planId: plan.id,
      planName: plan.name,
      activePlanId: plan.id,
      activePlanName: plan.name,
      currentPlan: plan.id,
      planAmountPence: plan.amountPence,
      monthlyPrice: plan.amountPence / 100,
      currency: plan.currency,
      billingInterval: plan.interval,
      vacancySlotLimit: plan.vacancySlotLimit,
      billingStatus: "setup_pending",
      subscriptionStatus: "setup_required",
      paymentStatus: "pending",
      paymentMethod: "direct_debit",
      currentPaymentMethod: "direct_debit",
      goCardlessBillingRequestId: billingRequestId,
      goCardlessBillingRequestFlowId: billingRequestFlowId,
      directDebitEnabled: false,
      mandateStatus: "setup_pending",
      updatedAt: now,
    };

    await userRef.set(
      {
        billing: setupPayload,
        directDebit: setupPayload,
      },
      { merge: true },
    );
    await userRef
      .collection("billing")
      .doc("gocardlessSandboxDirectDebit")
      .set(
        {
          ...setupPayload,
          createdAt: now,
        },
        { merge: true },
      );

    return {
      authorisationUrl,
      billingRequestId,
      billingRequestFlowId,
      planId: plan.id,
    };
  },
);

exports.getCompanyBillingStatus = onCall(
  {
    secrets: [goCardlessAccessToken],
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to view billing status.",
      );
    }

    const uid = request.auth.uid;
    const userRef = admin.firestore().collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    if (!userSnap.exists || !isEmployerBillingManager(user, uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only the company account owner can view billing status.",
      );
    }

    const billing = user.billing || {};
    const billingRequestId = cleanText(billing.goCardlessBillingRequestId);
    const pending = [
      "setup_pending",
      "mandate_pending",
      "setup_required",
    ].includes(cleanText(billing.billingStatus || billing.subscriptionStatus));

    if (pending && billingRequestId) {
      const accessToken = goCardlessAccessToken.value();
      if (accessToken) {
        await reconcileBillingRequest(userRef, billingRequestId, accessToken);
      }
    }

	    const refreshed = await userRef.get();
	    return await safeBillingStatus(refreshed.data() || {}, uid);
  },
);

exports.cancelGoCardlessSubscription = onCall(
  {
    secrets: [goCardlessAccessToken],
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to cancel Direct Debit.",
      );
    }

    const uid = request.auth.uid;
    const userRef = admin.firestore().collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    if (!userSnap.exists || !isEmployerBillingManager(user, uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only the company account owner can cancel Direct Debit.",
      );
    }

    const billing = user.billing || {};
    const subscriptionId = cleanText(billing.goCardlessSubscriptionId);
    if (subscriptionId) {
      const accessToken = goCardlessAccessToken.value();
      if (!accessToken) {
        throw new HttpsError(
          "failed-precondition",
          "GoCardless Sandbox is not configured.",
        );
      }
      await goCardlessPost(
        `/subscriptions/${encodeURIComponent(subscriptionId)}/actions/cancel`,
        {},
        accessToken,
        `stroyka-cancel-subscription-${uid}-${subscriptionId}`,
      );
    }

    await updateEmployerBilling(userRef, {
      billingStatus: "cancelled",
      subscriptionStatus: "cancelled",
      paymentStatus: "cancelled",
      directDebitEnabled: false,
      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    });

	    const refreshed = await userRef.get();
	    return await safeBillingStatus(refreshed.data() || {}, uid);
	  },
	);

exports.enforceBillingGraceExpiry = onSchedule(
  {
    schedule: "every 60 minutes",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async () => {
    const firestore = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const employers = await firestore
      .collection("users")
      .where("billing.billingStatus", "==", "past_due")
      .get();

    let suspendedEmployers = 0;
    let suspendedVacancies = 0;
    for (const employerDoc of employers.docs) {
      const employer = employerDoc.data() || {};
      const billing = employer.billing || {};
      const graceEndsAt = billing.paymentGraceEndsAt;
      if (!graceEndsAt || typeof graceEndsAt.toMillis !== "function") continue;
      if (graceEndsAt.toMillis() > now.toMillis()) continue;

      await updateEmployerBilling(employerDoc.ref, {
        billingStatus: "suspended",
        subscriptionStatus: "suspended",
        paymentStatus: "failed",
        paymentActionRequired: true,
        billingSuspendedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const jobs = await firestore
        .collection("jobs")
        .where("ownerId", "==", employerDoc.id)
        .where("moderationStatus", "==", "approved")
        .get();
      const batch = firestore.batch();
      for (const jobDoc of jobs.docs) {
        const job = jobDoc.data() || {};
        if (!isSlotOccupyingJob(job)) continue;
        batch.set(jobDoc.ref, {
          active: false,
          status: "suspended",
          billingSuspended: true,
          suspensionReason: "billing_suspended",
          preBillingSuspensionStatus: job.status || "active",
          billingSuspendedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        suspendedVacancies += 1;
      }
      await batch.commit();
      suspendedEmployers += 1;
      await createBillingNotificationOnce(
        employerDoc.id,
        `billing_grace_expired_${graceEndsAt.toMillis()}`,
        {
          title: "Vacancies suspended",
          message:
            "Your Direct Debit issue was not resolved within 3 days. Live vacancies have been suspended until billing is restored.",
          body:
            "Your Direct Debit issue was not resolved within 3 days. Live vacancies have been suspended until billing is restored.",
          targetType: "billing",
          targetId: employerDoc.id,
        },
      );
    }

    console.log("BILLING GRACE EXPIRY COMPLETE", JSON.stringify({
      suspendedEmployers,
      suspendedVacancies,
    }));
  },
);

exports.goCardlessReturn = onRequest((request, response) => {
  response
    .status(200)
    .set("Content-Type", "text/html; charset=utf-8")
    .send(
      htmlResponse(
        "Direct Debit setup submitted",
        "Your GoCardless Sandbox Direct Debit setup has been submitted. You may now return to STROYKA. We will confirm the final mandate status after GoCardless sends webhook events.",
      ),
    );
});

exports.goCardlessExit = onRequest((request, response) => {
  response
    .status(200)
    .set("Content-Type", "text/html; charset=utf-8")
    .send(
      htmlResponse(
        "Direct Debit setup not completed",
        "The GoCardless Sandbox Direct Debit setup was not completed. You may return to STROYKA and try again when ready.",
      ),
    );
});

exports.goCardlessWebhook = onRequest(
  {
    secrets: [goCardlessWebhookSecret, goCardlessAccessToken],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request, response) => {
  if (request.method !== "POST") {
    response.set("Allow", "POST").status(405).send("Method Not Allowed");
    return;
  }

  const rawBody = request.rawBody || Buffer.from("");
  const signature = request.get("Webhook-Signature") || "";
  const webhookSecret = goCardlessWebhookSecret.value();
  const validSignature = verifyGoCardlessWebhookSignature(
    rawBody,
    signature,
    webhookSecret,
  );
  if (!validSignature) {
    console.warn(
      "GOCARDLESS WEBHOOK INVALID SIGNATURE",
      JSON.stringify({ rawBodyBytes: rawBody.length }),
    );
    response.status(498).send("Invalid webhook signature");
    return;
  }

  let body = {};
  try {
    body = JSON.parse(rawBody.toString("utf8"));
  } catch (error) {
    response.status(400).send("Invalid JSON");
    return;
  }
  const events = Array.isArray(body.events) ? body.events : [];

  console.log(
    "GOCARDLESS WEBHOOK RECEIVED",
    JSON.stringify({
      rawBodyBytes: rawBody.length,
      eventCount: events.length,
      hasSignatureHeader: true,
    }),
  );

  const accessToken = goCardlessAccessToken.value();
  const processed = [];
  const skipped = [];
  for (const event of events) {
    const eventId = cleanText(event.id);
    if (!eventId) continue;
    const eventRef = admin
      .firestore()
      .collection("gocardless_processed_events")
      .doc(eventId);
    try {
      await eventRef.create({
        provider: "gocardless",
        environment: "sandbox",
        resourceType: cleanText(event.resource_type),
        action: cleanText(event.action),
        receivedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "processing",
      });
    } catch (error) {
      skipped.push(eventId);
      continue;
    }

    const result = await processGoCardlessEvent(event, accessToken);
    await eventRef.set(
      {
        status: "processed",
        result,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    processed.push(eventId);
  }

  response.status(200).json({
    received: true,
    processed,
    skipped,
  });
  },
);

function activeMemberStatus(status) {
  const normalized = String(status || "").trim().toLowerCase();
  return ![
    "removed",
    "deleted",
    "inactive",
    "left",
    "rejected",
  ].includes(normalized);
}

function isHeldDocument(data) {
  const status = String(data.status || "").trim().toLowerCase();
  return data.moderationHold === true ||
    data.held === true ||
    data.suspended === true ||
    data.profileHeld === true ||
    data.profileSuspended === true ||
    status === "suspended" ||
    status === "on_hold";
}

function isActiveUserDocument(data) {
  return data &&
    !isHeldDocument(data) &&
    data.deleted !== true &&
    data.accountDeleted !== true &&
    data.anonymised !== true &&
    data.active !== false;
}

function isActiveTeamDocument(data) {
  return data &&
    !isHeldDocument(data) &&
    data.deleted !== true &&
    data.accountDeleted !== true &&
    data.active !== false;
}

function addMemberId(ids, value) {
  const id = String(value || "").trim();
  if (id) ids.add(id);
}

function addMemberIdsFromList(ids, value) {
  if (!Array.isArray(value)) return;
  for (const item of value) {
    if (typeof item === "string") {
      addMemberId(ids, item);
    } else if (item && typeof item === "object") {
      addMemberId(
        ids,
        item.userId || item.uid || item.workerId || item.id,
      );
    }
  }
}

function addMemberIdsFromStatusMap(ids, value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return;
  for (const [memberId, status] of Object.entries(value)) {
    if (activeMemberStatus(status)) addMemberId(ids, memberId);
  }
}

function teamApplicationMemberIds(team) {
  const ids = new Set();
  addMemberIdsFromList(ids, team.members);
  addMemberIdsFromList(ids, team.memberIds);
  addMemberId(ids, team.ownerId);
  addMemberId(ids, team.createdBy);
  addMemberId(ids, team.leaderId);
  addMemberIdsFromStatusMap(ids, team.memberStatuses);
  addMemberIdsFromStatusMap(ids, team.membersStatus);
  return [...ids];
}

function activeApplicationStatus(status) {
  const normalized = String(status || "").trim().toLowerCase();
  return ![
    "withdrawn",
    "cancelled",
    "canceled",
    "deleted",
    "removed",
    "inactive",
  ].includes(normalized);
}

function isPublicApplicationJob(job) {
  const moderationStatus = String(job.moderationStatus || "").trim();
  const status = String(job.status || "").trim().toLowerCase();
  const statusAllowed = !Object.prototype.hasOwnProperty.call(job, "status") ||
    ["active", "published", "open"].includes(status);
  return moderationStatus === "approved" &&
    statusAllowed &&
    !isHeldDocument(job) &&
    job.deleted !== true &&
    job.companyDeleted !== true &&
    job.employerDeleted !== true;
}

function firstStringValue(data, keys) {
  for (const key of keys) {
    const value = data[key];
    if (value !== undefined && value !== null) {
      const text = String(value).trim();
      if (text) return text;
    }
  }
  return "";
}

function readIntValue(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  const parsed = Number.parseInt(String(value || ""), 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function jobPositionCounts(job) {
  const positions = readIntValue(
    job.positions ||
      job.totalPositions ||
      job.totalSlots ||
      job.workersNeeded ||
      job.requiredWorkers,
  );
  const filledPositions = readIntValue(
    job.filledPositions || job.acceptedCount || job.hiredCount,
  );
  const remainingKeys = [
    "remainingPositions",
    "openSlots",
    "availablePositions",
    "availableSlots",
    "remainingSlots",
    "positionsAvailable",
  ];
  const hasStoredRemaining = remainingKeys.some((key) => {
    return Object.prototype.hasOwnProperty.call(job, key) &&
      job[key] !== null &&
      job[key] !== undefined;
  });
  const remainingRaw = readIntValue(
    job.remainingPositions ||
      job.openSlots ||
      job.availablePositions ||
      job.availableSlots ||
      job.remainingSlots ||
      job.positionsAvailable,
  );
  const remaining = hasStoredRemaining
    ? remainingRaw
    : Math.max(positions - filledPositions, 0);

  return { positions, filledPositions, remaining };
}

function applicationPhysicalAddressFields(job) {
  return {
    addressLine1: job.addressLine1 || job.siteAddressLine1 || "",
    addressLine2: job.addressLine2 || job.siteAddressLine2 || "",
    addressLine3: job.addressLine3 || job.siteAddressLine3 || "",
    townCity: job.townCity || job.siteTownCity || job.city || "",
    county: job.county || job.siteCounty || "",
    postcode: job.postcode || job.sitePostcode || "",
    country: job.country || job.siteCountry || "",
    fullAddress: job.fullAddress || job.address || job.siteAddress || "",
  };
}

function applicationJobSnapshotFields(job) {
  return {
    companyName: job.companyName || job.employerName || "",
    companyLogoUrl: job.companyLogoUrl || job.employerAvatarUrl || "",
    employerAvatarUrl: job.employerAvatarUrl || job.companyLogoUrl || "",
    payType: job.payType || job.compensationType || "",
    payAmount: job.payAmount || job.salary || job.rate || "",
    payUnit: job.payUnit || job.rateUnit || "",
    duration: job.duration || "",
    jobType: job.jobType || job.type || "",
    jobStatusAtApplication: job.status || "",
  };
}

exports.submitTeamApplication = onCall(
  {
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to apply as a team.",
      );
    }

    const uid = request.auth.uid;
    const jobId = cleanText(request.data && request.data.jobId);
    const teamId = cleanText(request.data && request.data.teamId);

    console.log(
      "TEAM APPLY FUNCTION START",
      JSON.stringify({ uid, jobId, teamId }),
    );

    if (!jobId || !teamId) {
      throw new HttpsError(
        "invalid-argument",
        "Team application data is missing.",
      );
    }

    const db = admin.firestore();
    const applicationId = `team_${jobId}_${teamId}`;
    const userRef = db.collection("users").doc(uid);
    const teamRef = db.collection("teams").doc(teamId);
    const jobRef = db.collection("jobs").doc(jobId);
    const applicationRef = db.collection("applications").doc(applicationId);

    const result = await db.runTransaction(async (transaction) => {
      console.log(
        "TEAM APPLY TX READ START",
        JSON.stringify({
          userPath: userRef.path,
          teamPath: teamRef.path,
          jobPath: jobRef.path,
          applicationPath: applicationRef.path,
        }),
      );

      const userSnap = await transaction.get(userRef);
      const teamSnap = await transaction.get(teamRef);
      const jobSnap = await transaction.get(jobRef);
      const applicationSnap = await transaction.get(applicationRef);

      console.log(
        "TEAM APPLY TX READ SUCCESS",
        JSON.stringify({
          userExists: userSnap.exists,
          teamExists: teamSnap.exists,
          jobExists: jobSnap.exists,
          applicationExists: applicationSnap.exists,
        }),
      );

      if (!userSnap.exists || !isActiveUserDocument(userSnap.data() || {})) {
        throw new HttpsError(
          "permission-denied",
          "Only active workers can submit applications.",
        );
      }

      const user = userSnap.data() || {};
      if (String(user.role || "").trim().toLowerCase() !== "worker") {
        throw new HttpsError(
          "permission-denied",
          "Only workers can submit applications.",
        );
      }

      if (!teamSnap.exists) {
        throw new HttpsError("not-found", "Team is no longer available.");
      }

      const team = teamSnap.data() || {};
      if (!isActiveTeamDocument(team)) {
        throw new HttpsError(
          "failed-precondition",
          "Team is no longer active.",
        );
      }

      let members = teamApplicationMemberIds(team);
      if (!members.includes(uid)) {
        throw new HttpsError(
          "permission-denied",
          "Only team members can apply with this team.",
        );
      }
      members = [...new Set(members)].sort();

      if (!jobSnap.exists) {
        throw new HttpsError("not-found", "Job is no longer available.");
      }

      const job = jobSnap.data() || {};
      if (!isPublicApplicationJob(job)) {
        throw new HttpsError(
          "failed-precondition",
          "This job is not accepting applications.",
        );
      }

      const counts = jobPositionCounts(job);
      if (counts.positions <= 0) {
        throw new HttpsError(
          "failed-precondition",
          "This job has invalid position data.",
        );
      }
      if (members.length > counts.remaining) {
        throw new HttpsError(
          "failed-precondition",
          "Not enough positions available.",
        );
      }

      if (applicationSnap.exists) {
        const existing = applicationSnap.data() || {};
        if (activeApplicationStatus(existing.status)) {
          throw new HttpsError(
            "already-exists",
            "This team already applied for this job.",
          );
        }
      }

      const ownerId = firstStringValue(job, [
        "ownerId",
        "employerId",
        "createdBy",
        "userId",
      ]);
      if (!ownerId) {
        throw new HttpsError(
          "failed-precondition",
          "This job is missing employer information.",
        );
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      const payload = {
        jobId,
        jobTitle: firstStringValue(job, ["title", "trade"]) || "Job",
        jobTrade: job.trade || "",
        jobSite: job.site || "",
        ...applicationPhysicalAddressFields(job),
        ...applicationJobSnapshotFields(job),
        type: "team",
        teamId,
        teamName: firstStringValue(team, ["name", "teamName"]) || "Team",
        teamAvatarUrl: team.avatarUrl || team.photo || "",
        workerId: uid,
        applicantId: uid,
        members,
        workersCount: members.length,
        membersStatus: Object.fromEntries(members.map((id) => [id, "pending"])),
        employerId: ownerId,
        ownerId,
        status: "pending",
        viewedByEmployer: false,
        createdAt: now,
        updatedAt: now,
        applicationActivityAt: now,
        unreadFor: [ownerId],
      };

      console.log(
        "TEAM APPLY TX WRITE START",
        JSON.stringify({
          path: applicationRef.path,
          workersCount: members.length,
          ownerId,
        }),
      );

      transaction.set(applicationRef, payload, { merge: true });

      return {
        applicationId,
        workersCount: members.length,
      };
    });

    console.log(
      "TEAM APPLY FUNCTION SUCCESS",
      JSON.stringify({ uid, jobId, teamId, applicationId }),
    );

    return result;
  },
);

function notificationPreferences(user) {
  const settings = user.settings || {};
  const stored = settings.notifications || user.notificationPreferences || {};
  return {
    ...DEFAULT_NOTIFICATION_PREFERENCES,
    ...stored,
  };
}

function preferenceKeyForCategory(category) {
  switch (category) {
    case "job":
      return "jobAlerts";
    case "application":
      return "applicationUpdates";
    case "offer":
      return "offers";
    case "chat":
      return "messages";
    case "admin":
      return "adminMessages";
    case "billing":
      return "billing";
    case "support":
      return "supportReplies";
    case "policy":
      return "policyUpdates";
    default:
      return "enabled";
  }
}

function categoryFor(data) {
  const type = String(data.type || "");
  if (data.category) return String(data.category);
  if (type.includes("offer")) return "offer";
  if (type === "message" || data.chatId) return "chat";
  if (type === "job_alert" || type === "job_status") return "job";
  if (type === "billing" || data.relatedPaymentRequestId) return "billing";
  if (type === "support" || data.relatedSupportRequestId) return "support";
  if (type === "admin_message") return "admin";
  if (type === "policy_update" || type === "legal_update") return "policy";
  if (
    type === "application" ||
    type === "application_status" ||
    type === "application_reopened"
  ) {
    return "application";
  }
  return "alert";
}

function tokenList(user) {
  const tokens = new Set();
  if (typeof user.fcmToken === "string" && user.fcmToken.trim()) {
    tokens.add(user.fcmToken.trim());
  }
  if (Array.isArray(user.fcmTokens)) {
    user.fcmTokens.forEach((token) => {
      if (typeof token === "string" && token.trim()) tokens.add(token.trim());
    });
  }
  return [...tokens];
}

async function userTokenList(userId, user) {
  const tokens = new Set(tokenList(user));
  const snapshot = await admin
    .firestore()
    .collection("users")
    .doc(userId)
    .collection("deviceTokens")
    .where("active", "==", true)
    .get();

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    const token = typeof data.token === "string" ? data.token.trim() : "";
    if (token) tokens.add(token);
  });

  return [...tokens];
}

function cleanData(data) {
  const payload = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === null || value === undefined) continue;
    if (typeof value === "string") {
      payload[key] = value;
    } else if (
      typeof value === "number" ||
      typeof value === "boolean"
    ) {
      payload[key] = String(value);
    }
  }
  return payload;
}

async function unreadBadgeCount(userId, prefs) {
  if (prefs.badges === false) return 0;

  const notifications = await admin
    .firestore()
    .collection("users")
    .doc(userId)
    .collection("notifications")
    .where("read", "==", false)
    .count()
    .get();

  const chats = await admin
    .firestore()
    .collection("chats")
    .where("unreadFor", "array-contains", userId)
    .count()
    .get();

  const unreadNotifications = notifications.data().count || 0;
  const unreadChats = chats.data().count || 0;
  const badge = unreadNotifications + unreadChats;

  await admin.firestore().collection("users").doc(userId).set(
    {
      notificationState: {
        unreadCount: unreadNotifications,
        unreadChatCount: unreadChats,
        badgeCount: badge,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    },
    { merge: true },
  );

  return badge;
}

exports.sendUserNotificationPush = onDocumentCreated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const notification = event.data.data();
    const { userId, notificationId } = event.params;

    if (!notification || notification.pushEligible === false) return;

    const userDoc = await admin.firestore().collection("users").doc(userId).get();
    if (!userDoc.exists) return;

    const user = userDoc.data() || {};
    const prefs = notificationPreferences(user);
    const category = categoryFor(notification);
    const categoryKey = preferenceKeyForCategory(category);

    if (prefs.enabled === false || prefs[categoryKey] === false) return;

    const tokens = await userTokenList(userId, user);
    if (tokens.length === 0) return;

    const push = notification.push || {};
    const title = String(push.title || notification.title || "STROYKA");
    const body = String(
      push.body ||
        notification.body ||
        notification.message ||
        "You have a new notification",
    );
    const badge = await unreadBadgeCount(userId, prefs);
    const data = {
      ...cleanData(push.data || {}),
      ...cleanData(notification),
      userId,
      notificationId,
      category,
    };

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        body,
      },
      data,
      android: {
        priority: "high",
        notification: {
          channelId: "default_channel",
          sound: prefs.sound === false ? undefined : "default",
          notificationCount: badge,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: prefs.sound === false ? undefined : "default",
            badge,
          },
        },
      },
    });

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      const code = result.error && result.error.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        invalidTokens.push(tokens[index]);
      }
    });

    if (invalidTokens.length > 0) {
      const userRef = admin.firestore().collection("users").doc(userId);
      const writes = [
        userRef.set(
          {
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
            push: {
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true },
        ),
      ];
      invalidTokens.forEach((token) => {
        writes.push(userRef.collection("deviceTokens").doc(token).set(
          {
            active: false,
            invalidatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        ));
      });
      await Promise.all(writes);
    }

    await event.data.ref.set(
      {
        push: {
          sent: response.successCount > 0,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          successCount: response.successCount,
          failureCount: response.failureCount,
        },
      },
      { merge: true },
    );
  },
);

exports.sendChatNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const message = event.data.data();
    const chatId = event.params.chatId;

    const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
    if (!chatDoc.exists) return;

    const chat = chatDoc.data();
    const senderId = String(message.senderId || "");
    if (!senderId) return;

    const recipients = new Set();
    for (const id of Array.isArray(chat.members) ? chat.members : []) {
      if (id) recipients.add(String(id));
    }
    for (const id of Array.isArray(chat.participants) ? chat.participants : []) {
      if (id) recipients.add(String(id));
    }
    if (chat.workerId) recipients.add(String(chat.workerId));
    if (chat.employerId) recipients.add(String(chat.employerId));
    recipients.delete(senderId);
    if (recipients.size === 0) return;

    const attachments = Array.isArray(message.attachments) ? message.attachments : [];
    const body = String(message.text || "").trim() ||
      (attachments.length > 0 ? "Sent an attachment" : "New chat message");

    const writes = [];
    for (const receiverId of recipients) {
      const notificationRef = admin
        .firestore()
        .collection("users")
        .doc(receiverId)
        .collection("notifications")
        .doc();

      writes.push(notificationRef.set({
        notificationId: notificationRef.id,
        userId: receiverId,
        type: "message",
        category: "chat",
        title: "New message",
        message: body,
        body,
        targetType: "chat",
        targetId: chatId,
        chatId,
        read: false,
        badgeEligible: true,
        pushEligible: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        push: {
          title: "New message",
          body,
          category: "chat",
          sound: true,
          badge: true,
          data: {
            notificationId: notificationRef.id,
            userId: receiverId,
            type: "message",
            category: "chat",
            targetType: "chat",
            targetId: chatId,
            chatId,
          },
        },
      }));
    }

    await Promise.all(writes);
  },
);
