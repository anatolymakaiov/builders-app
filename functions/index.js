const crypto = require("crypto");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { HttpsError, onCall, onRequest } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const sharp = require("sharp");

admin.initializeApp();

const idealPostcodesApiKey = defineSecret("IDEAL_POSTCODES_API_KEY");
const goCardlessAccessToken = defineSecret("GOCARDLESS_ACCESS_TOKEN");
const goCardlessWebhookSecret = defineSecret("GOCARDLESS_WEBHOOK_SECRET");
const GOCARDLESS_SANDBOX_API_BASE = "https://api-sandbox.gocardless.com";
const GOCARDLESS_API_VERSION = "2015-07-06";
const DEFAULT_FUNCTION_REGION = "us-central1";
const PAYMENT_GRACE_DAYS = 3;
const TRIAL_DAYS = 30;
const CONFIGURED_MANDATE_STATUSES = new Set([
  "pending_submission",
  "submitted",
  "active",
  "reinstated",
]);
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

const ACCOUNT_LINK_MAX_MEMBERS = 10;
const ACCOUNT_LINK_SESSION_MINUTES = 30;

function accountLinkTokenHash(token) {
  return crypto.createHash("sha256").update(String(token || "")).digest("hex");
}

function accountIdentity(uid, data) {
  const role = cleanText(data.role || data.userRole).toLowerCase() || "worker";
  const employer = role === "employer" || role === "company";
  const displayName = employer
    ? cleanText(
      data.companyName || data.businessName || data.displayName || data.name,
    )
    : cleanText(
      data.name || data.displayName ||
      [data.firstName, data.lastName].map(cleanText).filter(Boolean).join(" "),
    );
  const avatarUrl = employer
    ? cleanText(
      data.companyLogo || data.companyLogoUrl || data.companyAvatarUrl ||
      data.logo || data.avatarUrl || data.photo,
    )
    : cleanText(
      data.photo || data.avatarUrl || data.photoUrl || data.profilePhotoUrl,
    );
  return {
    uid,
    role,
    displayName: displayName || (employer ? "Company" : "Worker"),
    avatarUrl,
    username: cleanText(data.username || data.userName || data.handle),
  };
}

function assertLinkableUser(snapshot) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "STROYKA account was not found.");
  }
  const data = snapshot.data() || {};
  if (data.accountDeleted === true || data.deleted === true) {
    throw new HttpsError("failed-precondition", "This account is unavailable.");
  }
  if (cleanText(data.role).toLowerCase() === "admin") {
    throw new HttpsError(
      "permission-denied",
      "Administrator accounts cannot be linked.",
    );
  }
}

async function linkAccountUids(transaction, sourceUid, targetUid) {
  const db = admin.firestore();
  const sourceMemberRef = db.collection("account_link_members").doc(sourceUid);
  const targetMemberRef = db.collection("account_link_members").doc(targetUid);
  const [sourceMember, targetMember] = await Promise.all([
    transaction.get(sourceMemberRef),
    transaction.get(targetMemberRef),
  ]);
  const sourceGroupId = cleanText(sourceMember.data()?.groupId);
  const targetGroupId = cleanText(targetMember.data()?.groupId);
  const groupIds = [...new Set([sourceGroupId, targetGroupId].filter(Boolean))];
  const groupSnapshots = new Map();
  for (const groupId of groupIds) {
    const ref = db.collection("account_link_groups").doc(groupId);
    groupSnapshots.set(groupId, await transaction.get(ref));
  }

  if (sourceGroupId && sourceGroupId === targetGroupId) {
    return sourceGroupId;
  }

  const sourceMembers = sourceGroupId
    ? (groupSnapshots.get(sourceGroupId)?.data()?.memberIds || [])
    : [sourceUid];
  const targetMembers = targetGroupId
    ? (groupSnapshots.get(targetGroupId)?.data()?.memberIds || [])
    : [targetUid];
  const memberIds = [...new Set([
    ...sourceMembers.map(String),
    ...targetMembers.map(String),
    sourceUid,
    targetUid,
  ])];
  if (memberIds.length > ACCOUNT_LINK_MAX_MEMBERS) {
    throw new HttpsError(
      "resource-exhausted",
      `A maximum of ${ACCOUNT_LINK_MAX_MEMBERS} accounts can be linked.`,
    );
  }

  const groupId = sourceGroupId || targetGroupId ||
    db.collection("account_link_groups").doc().id;
  const groupRef = db.collection("account_link_groups").doc(groupId);
  transaction.set(groupRef, {
    memberIds,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(sourceGroupId || targetGroupId ? {} : {
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }),
  }, { merge: true });
  for (const memberUid of memberIds) {
    transaction.set(db.collection("account_link_members").doc(memberUid), {
      groupId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  for (const oldGroupId of groupIds) {
    if (oldGroupId !== groupId) {
      transaction.delete(db.collection("account_link_groups").doc(oldGroupId));
    }
  }
  return groupId;
}

exports.listLinkedAccounts = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const db = admin.firestore();
  const uid = request.auth.uid;
  const member = await db.collection("account_link_members").doc(uid).get();
  let memberIds = [uid];
  if (member.exists) {
    const groupId = cleanText(member.data()?.groupId);
    const group = groupId
      ? await db.collection("account_link_groups").doc(groupId).get()
      : null;
    const storedMembers = group?.data()?.memberIds;
    if (Array.isArray(storedMembers) && storedMembers.includes(uid)) {
      memberIds = [...new Set(storedMembers.map(String))];
    }
  }
  const snapshots = await Promise.all(
    memberIds.map((memberUid) => db.collection("users").doc(memberUid).get()),
  );
  return {
    accounts: snapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => accountIdentity(snapshot.id, snapshot.data() || {})),
  };
});

exports.linkAuthenticatedAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const secondaryIdToken = cleanText(request.data?.secondaryIdToken);
  if (!secondaryIdToken) {
    throw new HttpsError("invalid-argument", "Account proof is required.");
  }
  let verified;
  try {
    verified = await admin.auth().verifyIdToken(secondaryIdToken, true);
  } catch (_) {
    throw new HttpsError("permission-denied", "Account proof is invalid.");
  }
  const sourceUid = request.auth.uid;
  const targetUid = cleanText(verified.uid);
  if (!targetUid || sourceUid === targetUid) {
    throw new HttpsError("already-exists", "This is already the current account.");
  }
  const db = admin.firestore();
  const [sourceUser, targetUser] = await Promise.all([
    db.collection("users").doc(sourceUid).get(),
    db.collection("users").doc(targetUid).get(),
  ]);
  assertLinkableUser(sourceUser);
  assertLinkableUser(targetUser);
  await db.runTransaction(
    (transaction) => linkAccountUids(transaction, sourceUid, targetUid),
  );
  return { linked: true, target: accountIdentity(targetUid, targetUser.data()) };
});

exports.createLinkedAccountSwitchToken = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const sourceUid = request.auth.uid;
  const targetUid = cleanText(request.data?.targetUid);
  if (!targetUid || targetUid === sourceUid) {
    throw new HttpsError("invalid-argument", "Choose another linked account.");
  }
  const db = admin.firestore();
  const [sourceMember, targetMember, targetUser] = await Promise.all([
    db.collection("account_link_members").doc(sourceUid).get(),
    db.collection("account_link_members").doc(targetUid).get(),
    db.collection("users").doc(targetUid).get(),
  ]);
  assertLinkableUser(targetUser);
  const sourceGroupId = cleanText(sourceMember.data()?.groupId);
  const targetGroupId = cleanText(targetMember.data()?.groupId);
  if (!sourceGroupId || sourceGroupId !== targetGroupId) {
    throw new HttpsError("permission-denied", "That account is not linked.");
  }
  const group = await db.collection("account_link_groups").doc(sourceGroupId).get();
  const memberIds = group.data()?.memberIds;
  if (!Array.isArray(memberIds) ||
      !memberIds.includes(sourceUid) ||
      !memberIds.includes(targetUid)) {
    throw new HttpsError("permission-denied", "That account is not linked.");
  }
  const token = await admin.auth().createCustomToken(targetUid, {
    stroykaAccountSwitch: true,
    sourceUid,
  });
  return { token };
});

exports.unlinkAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const requesterUid = request.auth.uid;
  const targetUid = cleanText(request.data?.targetUid);
  if (!targetUid) {
    throw new HttpsError("invalid-argument", "Account to unlink is required.");
  }
  const db = admin.firestore();
  await db.runTransaction(async (transaction) => {
    const requesterRef = db.collection("account_link_members").doc(requesterUid);
    const targetRef = db.collection("account_link_members").doc(targetUid);
    const [requester, target] = await Promise.all([
      transaction.get(requesterRef),
      transaction.get(targetRef),
    ]);
    const groupId = cleanText(requester.data()?.groupId);
    if (!groupId || groupId !== cleanText(target.data()?.groupId)) {
      throw new HttpsError("permission-denied", "That account is not linked.");
    }
    const groupRef = db.collection("account_link_groups").doc(groupId);
    const group = await transaction.get(groupRef);
    const members = Array.isArray(group.data()?.memberIds)
      ? group.data().memberIds.map(String)
      : [];
    if (!members.includes(requesterUid) || !members.includes(targetUid)) {
      throw new HttpsError("permission-denied", "That account is not linked.");
    }
    const detachedUid = targetUid === requesterUid ? requesterUid : targetUid;
    const remaining = members.filter((memberUid) => memberUid !== detachedUid);
    transaction.delete(db.collection("account_link_members").doc(detachedUid));
    if (remaining.length < 2) {
      transaction.delete(groupRef);
      for (const memberUid of remaining) {
        transaction.delete(db.collection("account_link_members").doc(memberUid));
      }
    } else {
      transaction.update(groupRef, {
        memberIds: remaining,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
  return { unlinked: true };
});

exports.createAccountLinkSession = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const sourceUid = request.auth.uid;
  const sourceUser = await admin.firestore().collection("users").doc(sourceUid).get();
  assertLinkableUser(sourceUser);
  const token = crypto.randomBytes(32).toString("base64url");
  const tokenHash = accountLinkTokenHash(token);
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + ACCOUNT_LINK_SESSION_MINUTES * 60 * 1000,
  );
  await admin.firestore().collection("account_link_sessions").doc(tokenHash).set({
    sourceUid,
    expiresAt,
    consumed: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { sessionToken: token, expiresAt: expiresAt.toMillis() };
});

exports.redeemAccountLinkSession = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const sessionToken = cleanText(request.data?.sessionToken);
  if (!sessionToken) {
    throw new HttpsError("invalid-argument", "Link session is required.");
  }
  const tokenHash = accountLinkTokenHash(sessionToken);
  const db = admin.firestore();
  const sessionRef = db.collection("account_link_sessions").doc(tokenHash);
  const targetUid = request.auth.uid;
  await db.runTransaction(async (transaction) => {
    const session = await transaction.get(sessionRef);
    if (!session.exists) {
      throw new HttpsError("not-found", "Link session was not found.");
    }
    const sessionData = session.data() || {};
    const sourceUid = cleanText(sessionData.sourceUid);
    const expiresAt = sessionData.expiresAt;
    if (sessionData.consumed === true) {
      throw new HttpsError("failed-precondition", "Link session was already used.");
    }
    if (!expiresAt || expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError("deadline-exceeded", "Link session has expired.");
    }
    if (!sourceUid || sourceUid === targetUid) {
      throw new HttpsError("invalid-argument", "A different account is required.");
    }
    await linkAccountUids(transaction, sourceUid, targetUid);
    transaction.update(sessionRef, {
      consumed: true,
      consumedBy: targetUid,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { linked: true };
});

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

const ACCEPTED_WORK_STATUSES = new Set([
  "offer_accepted",
  "accepted",
  "hired",
  "completed",
]);

function userRole(data) {
  return cleanText(data && (data.role || data.userRole)).toLowerCase();
}

function unavailableUser(data) {
  return !data || data.deleted === true || data.accountDeleted === true ||
    data.anonymised === true || data.active === false ||
    data.moderationHold === true || data.profileSuspended === true ||
    data.profileHold === true || data.accountOnHold === true ||
    ["suspended", "on_hold"].includes(cleanText(data.status).toLowerCase());
}

function applicationWorkerIds(data) {
  const ids = new Set();
  for (const value of [data.workerId, data.applicantId, data.userId]) {
    const id = cleanText(value);
    if (id) ids.add(id);
  }
  if (Array.isArray(data.members)) {
    for (const member of data.members) {
      if (typeof member === "string") {
        if (member.trim()) ids.add(member.trim());
      } else if (member && typeof member === "object") {
        const id = cleanText(
          member.uid || member.userId || member.workerId || member.id,
        );
        if (id) ids.add(id);
      }
    }
  }
  for (const map of [data.membersStatus, data.memberStatuses]) {
    if (map && typeof map === "object" && !Array.isArray(map)) {
      for (const id of Object.keys(map)) {
        if (id.trim()) ids.add(id.trim());
      }
    }
  }
  return ids;
}

async function accountsShareLinkGroup(firestore, firstUid, secondUid) {
  const [first, second] = await Promise.all([
    firestore.collection("account_link_members").doc(firstUid).get(),
    firestore.collection("account_link_members").doc(secondUid).get(),
  ]);
  const firstGroup = cleanText(first.data()?.groupId);
  const secondGroup = cleanText(second.data()?.groupId);
  return Boolean(firstGroup && firstGroup === secondGroup);
}

function reviewCompanyName(data) {
  return cleanText(
    data.companyName || data.businessName || data.displayName || data.name,
  ) || "Company";
}

function reviewCompanyLogo(data) {
  return cleanText(
    data.companyLogo || data.companyLogoUrl || data.companyAvatarUrl ||
    data.logo || data.avatarUrl || data.photo,
  );
}

function reviewWorkerName(data) {
  return cleanText(
    data.name || data.displayName ||
    [data.firstName, data.lastName].map(cleanText).filter(Boolean).join(" "),
  ) || "Worker";
}

function publicReviewRequest(snapshot) {
  const data = snapshot.data() || {};
  return {
    id: snapshot.id,
    workerId: cleanText(data.workerId),
    employerId: cleanText(data.employerId),
    applicationId: cleanText(data.applicationId),
    jobId: cleanText(data.jobId),
    jobTitle: cleanText(data.jobTitle),
    workerName: cleanText(data.workerName),
    employerName: cleanText(data.employerName),
    employerLogoUrl: cleanText(data.employerLogoUrl),
    status: cleanText(data.status),
    rating: Number(data.rating) || 0,
    review: cleanText(data.review),
    createdAtMillis: data.createdAt?.toMillis?.() || 0,
    respondedAtMillis: data.respondedAt?.toMillis?.() || 0,
    decidedAtMillis: data.decidedAt?.toMillis?.() || 0,
  };
}

async function reviewNotification(transaction, recipientId, id, payload) {
  const ref = admin.firestore()
    .collection("users")
    .doc(recipientId)
    .collection("notifications")
    .doc(id);
  transaction.set(ref, {
    notificationId: id,
    userId: recipientId,
    category: "reviews",
    read: false,
    badgeEligible: true,
    pushEligible: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...payload,
  });
}

async function eligibleReviewApplications(firestore, workerId) {
  const applications = new Map();
  const queries = [
    firestore.collection("applications").where("workerId", "==", workerId),
    firestore.collection("applications").where("applicantId", "==", workerId),
    firestore.collection("applications").where("userId", "==", workerId),
    firestore.collection("applications").where(
      "members",
      "array-contains",
      workerId,
    ),
  ];
  for (const field of ["membersStatus", "memberStatuses"]) {
    for (const status of [
      "pending",
      "accepted",
      "offer_accepted",
      "hired",
      "completed",
    ]) {
      queries.push(
        firestore.collection("applications").where(
          new admin.firestore.FieldPath(field, workerId),
          "==",
          status,
        ),
      );
    }
  }
  for (const query of queries) {
    const snapshot = await query.get();
    for (const doc of snapshot.docs) applications.set(doc.id, doc);
  }
  return [...applications.values()].filter((doc) => {
    const data = doc.data() || {};
    return ACCEPTED_WORK_STATUSES.has(cleanText(data.status).toLowerCase()) &&
      applicationWorkerIds(data).has(workerId);
  });
}

async function resolveReviewEngagement(firestore, workerId, applicationId) {
  const application = await firestore
    .collection("applications")
    .doc(applicationId)
    .get();
  if (!application.exists) return null;
  const data = application.data() || {};
  if (!ACCEPTED_WORK_STATUSES.has(cleanText(data.status).toLowerCase()) ||
      !applicationWorkerIds(data).has(workerId)) {
    return null;
  }
  const jobId = cleanText(data.jobId);
  const job = jobId
    ? await firestore.collection("jobs").doc(jobId).get()
    : null;
  const jobData = job?.data() || {};
  const employerId = cleanText(
    data.employerId || data.ownerId || jobData.employerId ||
    jobData.ownerId || jobData.createdBy,
  );
  if (!employerId) return null;
  return {
    application,
    applicationData: data,
    employerId,
    jobId,
    jobTitle: cleanText(
      data.jobTitle || data.title || jobData.title || jobData.trade,
    ) || "Work engagement",
  };
}

exports.listEligibleEmployerReviews = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const firestore = admin.firestore();
  const workerId = request.auth.uid;
  const worker = await firestore.collection("users").doc(workerId).get();
  const workerData = worker.data() || {};
  if (userRole(workerData) !== "worker" || unavailableUser(workerData)) {
    throw new HttpsError(
      "permission-denied",
      "Only an active Worker can request a review.",
    );
  }
  const applications = await eligibleReviewApplications(firestore, workerId);
  const engagements = [];
  for (const application of applications) {
    const resolved = await resolveReviewEngagement(
      firestore,
      workerId,
      application.id,
    );
    if (!resolved) continue;
    const employer = await firestore
      .collection("users")
      .doc(resolved.employerId)
      .get();
    const employerData = employer.data() || {};
    if (!employer.exists || unavailableUser(employerData) ||
        !["employer", "company"].includes(userRole(employerData)) ||
        await accountsShareLinkGroup(
          firestore,
          workerId,
          resolved.employerId,
        )) {
      continue;
    }
    const requestId = crypto.createHash("sha256")
      .update(`${workerId}:${application.id}:${resolved.employerId}`)
      .digest("hex");
    const existing = await firestore
      .collection("worker_review_requests")
      .doc(requestId)
      .get();
    engagements.push({
      applicationId: application.id,
      employerId: resolved.employerId,
      employerName: reviewCompanyName(employerData),
      employerLogoUrl: reviewCompanyLogo(employerData),
      jobId: resolved.jobId,
      jobTitle: resolved.jobTitle,
      requestStatus: existing.exists
        ? cleanText(existing.data()?.status)
        : "",
    });
  }
  return { engagements };
});

exports.listMyEmployerReviewRequests = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const firestore = admin.firestore();
  const uid = request.auth.uid;
  const user = await firestore.collection("users").doc(uid).get();
  const role = userRole(user.data() || {});
  const field = role === "worker" ? "workerId" : "employerId";
  if (role !== "worker" && role !== "employer" && role !== "company") {
    throw new HttpsError("permission-denied", "Reviews are not available.");
  }
  const snapshot = await firestore
    .collection("worker_review_requests")
    .where(field, "==", uid)
    .get();
  const reviews = snapshot.docs.map(publicReviewRequest);
  reviews.sort((a, b) => b.createdAtMillis - a.createdAtMillis);
  return { reviews };
});

exports.getEmployerReviewRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const requestId = cleanText(request.data?.requestId);
  if (!requestId) {
    throw new HttpsError("invalid-argument", "Review request is required.");
  }
  const snapshot = await admin.firestore()
    .collection("worker_review_requests")
    .doc(requestId)
    .get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Review request was not found.");
  }
  const data = snapshot.data() || {};
  if (![data.workerId, data.employerId].includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Review request is private.");
  }
  return { review: publicReviewRequest(snapshot) };
});

exports.requestEmployerReview = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const firestore = admin.firestore();
  const workerId = request.auth.uid;
  const applicationId = cleanText(request.data?.applicationId);
  if (!applicationId) {
    throw new HttpsError("invalid-argument", "Work engagement is required.");
  }
  const [worker, engagement] = await Promise.all([
    firestore.collection("users").doc(workerId).get(),
    resolveReviewEngagement(firestore, workerId, applicationId),
  ]);
  const workerData = worker.data() || {};
  if (!worker.exists || userRole(workerData) !== "worker" ||
      unavailableUser(workerData)) {
    throw new HttpsError(
      "permission-denied",
      "Only an active Worker can request a review.",
    );
  }
  if (!engagement) {
    throw new HttpsError(
      "permission-denied",
      "A confirmed work relationship is required.",
    );
  }
  const employer = await firestore
    .collection("users")
    .doc(engagement.employerId)
    .get();
  const employerData = employer.data() || {};
  if (!employer.exists || unavailableUser(employerData) ||
      !["employer", "company"].includes(userRole(employerData))) {
    throw new HttpsError("failed-precondition", "Company is unavailable.");
  }
  if (await accountsShareLinkGroup(
    firestore,
    workerId,
    engagement.employerId,
  )) {
    throw new HttpsError(
      "permission-denied",
      "Linked accounts cannot review each other.",
    );
  }
  const requestId = crypto.createHash("sha256")
    .update(`${workerId}:${applicationId}:${engagement.employerId}`)
    .digest("hex");
  const reviewRef = firestore.collection("worker_review_requests").doc(requestId);
  await firestore.runTransaction(async (transaction) => {
    const [existing, workerLink, employerLink] = await Promise.all([
      transaction.get(reviewRef),
      transaction.get(
        firestore.collection("account_link_members").doc(workerId),
      ),
      transaction.get(
        firestore.collection("account_link_members").doc(engagement.employerId),
      ),
    ]);
    if (existing.exists) {
      throw new HttpsError(
        "already-exists",
        "A review request already exists for this work engagement.",
      );
    }
    const workerGroup = cleanText(workerLink.data()?.groupId);
    const employerGroup = cleanText(employerLink.data()?.groupId);
    if (workerGroup && workerGroup === employerGroup) {
      throw new HttpsError(
        "permission-denied",
        "Linked accounts cannot review each other.",
      );
    }
    transaction.create(reviewRef, {
      workerId,
      employerId: engagement.employerId,
      applicationId,
      jobId: engagement.jobId,
      jobTitle: engagement.jobTitle,
      workerName: reviewWorkerName(workerData),
      employerName: reviewCompanyName(employerData),
      employerLogoUrl: reviewCompanyLogo(employerData),
      status: "requested",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await reviewNotification(
      transaction,
      engagement.employerId,
      `worker-review-request-${requestId}`,
      {
        type: "worker_review_requested",
        title: `${reviewWorkerName(workerData)} requested a review`,
        body: engagement.jobTitle,
        targetType: "worker_review",
        targetId: requestId,
        reviewRequestId: requestId,
        workerId,
        relatedJobId: engagement.jobId,
        relatedApplicationId: applicationId,
      },
    );
  });
  return { requestId };
});

exports.respondEmployerReview = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const firestore = admin.firestore();
  const employerId = request.auth.uid;
  const requestId = cleanText(request.data?.requestId);
  const reviewText = cleanText(request.data?.review);
  const rating = Number(request.data?.rating);
  if (!requestId || !reviewText || !Number.isInteger(rating) ||
      rating < 1 || rating > 5) {
    throw new HttpsError(
      "invalid-argument",
      "A 1–5 star rating and written review are required.",
    );
  }
  const reviewRef = firestore.collection("worker_review_requests").doc(requestId);
  await firestore.runTransaction(async (transaction) => {
    const preliminary = await transaction.get(reviewRef);
    if (!preliminary.exists) {
      throw new HttpsError("not-found", "Review request was not found.");
    }
    const preliminaryData = preliminary.data() || {};
    const [employer, workerLink, employerLink] = await Promise.all([
      transaction.get(firestore.collection("users").doc(employerId)),
      transaction.get(
        firestore.collection("account_link_members").doc(preliminaryData.workerId),
      ),
      transaction.get(
        firestore.collection("account_link_members").doc(employerId),
      ),
    ]);
    const data = preliminaryData;
    const employerData = employer.data() || {};
    if (data.employerId !== employerId ||
        !["employer", "company"].includes(userRole(employerData)) ||
        unavailableUser(employerData)) {
      throw new HttpsError(
        "permission-denied",
        "Only the requested company can respond.",
      );
    }
    if (data.status !== "requested") {
      throw new HttpsError(
        "failed-precondition",
        "This review request has already been answered.",
      );
    }
    const workerGroup = cleanText(workerLink.data()?.groupId);
    const employerGroup = cleanText(employerLink.data()?.groupId);
    if (workerGroup && workerGroup === employerGroup) {
      throw new HttpsError(
        "permission-denied",
        "Linked accounts cannot review each other.",
      );
    }
    transaction.update(reviewRef, {
      status: "responded",
      rating,
      review: reviewText,
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await reviewNotification(
      transaction,
      data.workerId,
      `worker-review-response-${requestId}`,
      {
        type: "worker_review_responded",
        title: `${data.employerName || "Company"} responded to your review request`,
        body: "Review the response and choose whether to publish it.",
        targetType: "worker_review",
        targetId: requestId,
        reviewRequestId: requestId,
        employerId,
        relatedJobId: data.jobId || "",
        relatedApplicationId: data.applicationId || "",
      },
    );
  });
  return { status: "responded" };
});

exports.decideEmployerReview = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const firestore = admin.firestore();
  const workerId = request.auth.uid;
  const requestId = cleanText(request.data?.requestId);
  const decision = cleanText(request.data?.decision).toLowerCase();
  if (!requestId || !["publish", "decline"].includes(decision)) {
    throw new HttpsError("invalid-argument", "Choose Publish or Decline.");
  }
  const reviewRef = firestore.collection("worker_review_requests").doc(requestId);
  await firestore.runTransaction(async (transaction) => {
    const review = await transaction.get(reviewRef);
    if (!review.exists) {
      throw new HttpsError("not-found", "Review request was not found.");
    }
    const data = review.data() || {};
    if (data.workerId !== workerId) {
      throw new HttpsError(
        "permission-denied",
        "Only the Worker can publish or decline this review.",
      );
    }
    if (data.status !== "responded") {
      throw new HttpsError(
        "failed-precondition",
        "This response has already been decided.",
      );
    }
    const [workerLink, employerLink, publishedReviews] = await Promise.all([
      transaction.get(
        firestore.collection("account_link_members").doc(workerId),
      ),
      transaction.get(
        firestore.collection("account_link_members").doc(data.employerId),
      ),
      decision === "publish"
        ? transaction.get(
          firestore.collection("users").doc(workerId).collection("reviews"),
        )
        : Promise.resolve(null),
    ]);
    const workerGroup = cleanText(workerLink.data()?.groupId);
    const employerGroup = cleanText(employerLink.data()?.groupId);
    if (workerGroup && workerGroup === employerGroup) {
      throw new HttpsError(
        "permission-denied",
        "Linked accounts cannot review each other.",
      );
    }
    const status = decision === "publish" ? "published" : "declined";
    transaction.update(reviewRef, {
      status,
      decidedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (decision === "publish") {
      transaction.create(
        firestore.collection("users")
          .doc(workerId)
          .collection("reviews")
          .doc(requestId),
        {
          requestId,
          employerId: data.employerId,
          employerName: data.employerName,
          employerLogoUrl: data.employerLogoUrl || "",
          workerId,
          applicationId: data.applicationId,
          jobId: data.jobId || "",
          jobTitle: data.jobTitle || "",
          rating: data.rating,
          review: data.review,
          status: "published",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      );
      const existingRatings = publishedReviews.docs
        .map((doc) => Number(doc.data().rating) || 0)
        .filter((value) => value >= 1 && value <= 5);
      const nextRatings = [...existingRatings, Number(data.rating)];
      const ratingTotal = nextRatings.reduce((sum, value) => sum + value, 0);
      transaction.set(
        firestore.collection("users").doc(workerId),
        {
          rating: ratingTotal / nextRatings.length,
          reviewsCount: nextRatings.length,
        },
        { merge: true },
      );
    }
    await reviewNotification(
      transaction,
      data.employerId,
      `worker-review-decision-${requestId}`,
      {
        type: `worker_review_${status}`,
        title: decision === "publish"
          ? `${data.workerName || "Worker"} published your review`
          : `${data.workerName || "Worker"} declined your review`,
        body: data.jobTitle || "Review request updated",
        targetType: "worker_review",
        targetId: requestId,
        reviewRequestId: requestId,
        workerId,
      },
    );
  });
  return { status: decision === "publish" ? "published" : "declined" };
});

function storagePathFromImageUrl(rawUrl) {
  const value = cleanText(rawUrl);
  if (!value) return "";

  if (value.startsWith("gs://")) {
    const withoutScheme = value.slice("gs://".length);
    const firstSlash = withoutScheme.indexOf("/");
    return firstSlash >= 0 ? withoutScheme.slice(firstSlash + 1) : "";
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch (_) {
    return "";
  }

  if (parsed.hostname.includes("firebasestorage.googleapis.com")) {
    const marker = "/o/";
    const markerIndex = parsed.pathname.indexOf(marker);
    if (markerIndex < 0) return "";
    return decodeURIComponent(parsed.pathname.slice(markerIndex + marker.length));
  }

  if (parsed.hostname.includes("storage.googleapis.com")) {
    const parts = parsed.pathname.split("/").filter(Boolean);
    if (parts.length < 2) return "";
    return decodeURIComponent(parts.slice(1).join("/"));
  }

  return "";
}

function extensionForStoragePath(path) {
  const fileName = String(path || "").split("/").pop() || "";
  const dot = fileName.lastIndexOf(".");
  if (dot < 0 || dot === fileName.length - 1) return "";
  return fileName.slice(dot + 1).toLowerCase();
}

function isHeicLike(path, contentType) {
  const extension = extensionForStoragePath(path);
  const type = cleanText(contentType).toLowerCase();
  return extension === "heic" ||
    extension === "heif" ||
    type === "image/heic" ||
    type === "image/heif";
}

function isWebConvertibleImagePath(path) {
  const prefixes = [
    "profile_photos/",
    "profile_headers/",
    "company_photos/",
    "job_photos/",
    "portfolio/",
    "team_avatars/",
    "team_portfolio/",
    "chat_media/",
    "chat_audio/",
    "chat_video/",
    "chat_voice/",
    "chat_attachments/",
  ];
  return prefixes.some((prefix) => path.startsWith(prefix));
}

function firebaseDownloadUrl(bucketName, path, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
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

exports.getWebCompatibleImage = onCall(
  {
    timeoutSeconds: 30,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to load this image.",
      );
    }

    const sourceUrl = cleanText(request.data && request.data.url);
    const sourcePath = storagePathFromImageUrl(sourceUrl);
    if (!sourcePath) {
      throw new HttpsError("invalid-argument", "Invalid image URL.");
    }
    if (!isWebConvertibleImagePath(sourcePath)) {
      throw new HttpsError(
        "permission-denied",
        "This image cannot be converted for web display.",
      );
    }

    const bucket = admin.storage().bucket();
    const sourceFile = bucket.file(sourcePath);
    const [exists] = await sourceFile.exists();
    if (!exists) {
      throw new HttpsError("not-found", "Image was not found.");
    }

    const [sourceMetadata] = await sourceFile.getMetadata();
    if (!isHeicLike(sourcePath, sourceMetadata.contentType)) {
      return {
        url: sourceUrl,
        sourcePath,
        converted: false,
      };
    }

    const hash = crypto.createHash("sha256").update(sourcePath).digest("hex");
    const derivativePath = `web_image_derivatives/${hash}.jpg`;
    const derivativeFile = bucket.file(derivativePath);
    const [derivativeExists] = await derivativeFile.exists();

    if (derivativeExists) {
      const [metadata] = await derivativeFile.getMetadata();
      const tokens = cleanText(
        metadata.metadata && metadata.metadata.firebaseStorageDownloadTokens,
      );
      const token = tokens.split(",").map((item) => item.trim()).find(Boolean);
      if (token) {
        return {
          url: firebaseDownloadUrl(bucket.name, derivativePath, token),
          sourcePath,
          derivativePath,
          converted: true,
          cached: true,
        };
      }
    }

    const [sourceBuffer] = await sourceFile.download();
    const jpegBuffer = await sharp(sourceBuffer)
      .rotate()
      .jpeg({ quality: 88, mozjpeg: true })
      .toBuffer();
    const token = crypto.randomUUID();

    await derivativeFile.save(jpegBuffer, {
      resumable: false,
      metadata: {
        contentType: "image/jpeg",
        cacheControl: "public, max-age=31536000, immutable",
        metadata: {
          firebaseStorageDownloadTokens: token,
          sourcePath,
          generatedFor: "flutter-web",
        },
      },
    });

    return {
      url: firebaseDownloadUrl(bucket.name, derivativePath, token),
      sourcePath,
      derivativePath,
      converted: true,
      cached: false,
    };
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
  return [
    "past_due",
    "payment_method_required",
    "suspended",
    "cancelled",
    "failed",
  ].includes(
    cleanText(billing.billingStatus || billing.subscriptionStatus)
      .toLowerCase(),
  );
}

function billingPlan(billing) {
  return planForId(
    billing.planId ||
      billing.currentPlanId ||
      billing.activePlanId ||
      billing.currentPlan ||
      billing.pendingPlan,
  );
}

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function dateOnly(value) {
  return value.toISOString().slice(0, 10);
}

function trialWindowForBilling(billing) {
  const existingStart = timestampToDate(
    billing.trialStartedAt || billing.trialStartDate,
  );
  const existingEnd = timestampToDate(
    billing.trialEndsAt || billing.trialEndDate,
  );
  const startedAt = existingStart || new Date();
  const endsAt = existingEnd || new Date(
    startedAt.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000,
  );
  return {
    startedAt,
    endsAt,
    startedTimestamp: admin.firestore.Timestamp.fromDate(startedAt),
    endsTimestamp: admin.firestore.Timestamp.fromDate(endsAt),
    isActive: endsAt.getTime() > Date.now(),
    alreadyStarted: !!existingStart,
  };
}

function directDebitConfigured(billing) {
  const mandateStatus = cleanText(billing.mandateStatus).toLowerCase();
  const explicit = billing.directDebitConfigured === true ||
    cleanText(billing.directDebitStatus).toLowerCase() === "active";
  return (explicit ||
      !!cleanText(billing.goCardlessMandateId || billing.directDebitMandateId)) &&
    CONFIGURED_MANDATE_STATUSES.has(mandateStatus) &&
    billing.directDebitEnabled === true;
}

function addMonths(date, months) {
  const next = new Date(date);
  next.setMonth(next.getMonth() + months);
  return next;
}

function billingPeriodEnd(billing) {
  return timestampToDate(
    billing.currentPeriodEnd ||
      billing.nextChargeDate ||
      billing.nextBillingDate ||
      billing.firstPaymentDate,
  ) || addMonths(new Date(), 1);
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
  const trialWindow = trialWindowForBilling(billing);
  const ddConfigured = directDebitConfigured(billing);
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
    directDebitConfigured: ddConfigured,
    directDebitStatus: billing.directDebitStatus || billing.mandateStatus || "",
    trialActive: trialWindow.isActive &&
      cleanText(billing.subscriptionStatus).toLowerCase() === "trial",
    trialStartedAt: billing.trialStartedAt || billing.trialStartDate || null,
    trialEndsAt: billing.trialEndsAt || billing.trialEndDate || null,
    firstPaymentDate: billing.firstPaymentDate ||
      billing.nextChargeDate ||
      billing.nextBillingDate ||
      null,
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
    currentPlanId: plan ? plan.id : cleanText(billing.currentPlan),
    pendingPlanId: cleanText(billing.pendingPlanId || billing.pendingPlan),
    pendingPlanEffectiveAt: billing.pendingPlanEffectiveAt || null,
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
  const status = String(reason || "").includes("cancel")
    ? "payment_method_required"
    : "past_due";
  if (billing.paymentGraceStartedAt && billing.paymentGraceEndsAt) {
    await updateEmployerBilling(employerRef, {
      billingStatus: status,
      subscriptionStatus: status,
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
    billingStatus: status,
    subscriptionStatus: status,
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
  const snap = await employerRef.get();
  const billing = (snap.data() || {}).billing || {};
  const trialWindow = trialWindowForBilling(billing);
  const subscriptionStatus = trialWindow.isActive ? "trial" : "active";
  await updateEmployerBilling(employerRef, {
    billingStatus: "active",
    subscriptionStatus,
    paymentStatus: "paid",
    trialActive: trialWindow.isActive,
    trialStatus: trialWindow.isActive ? "active" : "expired",
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
  const providedStartDate = payload.startDate;
  const startDateMillis = Number(payload.startDateMillis);
  delete payload.startDateMillis;
  delete payload.startDate;
  if (Number.isFinite(startDateMillis) && startDateMillis > 0) {
    payload.startDate = admin.firestore.Timestamp.fromMillis(startDateMillis);
  } else if (providedStartDate instanceof admin.firestore.Timestamp) {
    payload.startDate = providedStartDate;
  }
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

async function activateDirectDebitEntitlement(
  employerRef,
  mandateId,
  subscriptionId,
  plan,
  subscription = {},
  mandateStatus = "active",
) {
  const snap = await employerRef.get();
  const billing = (snap.data() || {}).billing || {};
  const trialWindow = trialWindowForBilling(billing);
  const subscriptionStatus = trialWindow.isActive ? "trial" : "active";
  const firstPaymentDate =
    subscription.start_date ||
    (subscription.upcoming_payments &&
      subscription.upcoming_payments[0] &&
      subscription.upcoming_payments[0].charge_date) ||
    dateOnly(trialWindow.endsAt);

  await updateEmployerBilling(employerRef, {
    billingStatus: "active",
    subscriptionStatus,
    paymentStatus: "pending",
    directDebitEnabled: true,
    directDebitConfigured: true,
    mandateStatus,
    directDebitStatus: "active",
    directDebitMandateId: mandateId,
    goCardlessMandateId: mandateId,
    goCardlessSubscriptionId: subscriptionId,
    subscriptionStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    currentPeriodStart: admin.firestore.FieldValue.serverTimestamp(),
    nextChargeDate: firstPaymentDate,
    firstPaymentDate,
    planId: plan.id,
    planName: plan.name,
    activePlanId: plan.id,
    activePlanName: plan.name,
    currentPlan: plan.id,
    currentPlanId: plan.id,
    pendingPlan: "",
    pendingPlanId: "",
    pendingPlanEffectiveAt: admin.firestore.FieldValue.delete(),
    planAmountPence: plan.amountPence,
    monthlyPrice: plan.amountPence / 100,
    currency: plan.currency,
    billingInterval: plan.interval,
    vacancySlotLimit: plan.vacancySlotLimit,
    trialStartedAt: trialWindow.startedTimestamp,
    trialStartDate: trialWindow.startedTimestamp,
    trialEndsAt: trialWindow.endsTimestamp,
    trialEndDate: trialWindow.endsTimestamp,
    trialActive: trialWindow.isActive,
    trialStatus: trialWindow.isActive ? "active" : "expired",
    paymentActionRequired: false,
    paymentFailureReason: "",
    paymentGraceStartedAt: admin.firestore.FieldValue.delete(),
    paymentGraceEndsAt: admin.firestore.FieldValue.delete(),
	  });
  console.log("GOCARDLESS ENTITLEMENT ACTIVATED", JSON.stringify({
    employerId: employerRef.id,
    mandateId,
    mandateStatus,
    subscriptionId,
    subscriptionStatus,
    planId: plan.id,
    trialActive: trialWindow.isActive,
    firstPaymentDate,
  }));
  await restoreBillingSuspendedVacancies(employerRef);
}

async function ensureGoCardlessSubscription(
  employerRef,
  mandateId,
  accessToken,
  mandateStatus = "active",
) {
  const employerSnap = await employerRef.get();
  const employer = employerSnap.data() || {};
  const billing = employer.billing || {};
  const existingSubscriptionId = cleanText(billing.goCardlessSubscriptionId);
  const plan = billingPlan(billing);
  if (!plan) {
    throw new HttpsError(
      "failed-precondition",
      "A valid STROYKA billing plan is required before subscription creation.",
    );
  }
  if (existingSubscriptionId) {
    await activateDirectDebitEntitlement(
      employerRef,
      mandateId,
      existingSubscriptionId,
      plan,
      {},
      mandateStatus,
    );
    return existingSubscriptionId;
  }
  const trialWindow = trialWindowForBilling(billing);

  const response = await goCardlessPost(
    "/subscriptions",
    {
      subscriptions: {
        amount: plan.amountPence,
        currency: plan.currency,
        name: `${plan.name} STROYKA company subscription`,
        interval_unit: "monthly",
        interval: 1,
        start_date: dateOnly(trialWindow.endsAt),
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

	  await activateDirectDebitEntitlement(
	    employerRef,
	    mandateId,
	    subscriptionId,
	    plan,
	    subscription,
	    mandateStatus,
	  );

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
    updates.mandateStatus = "pending_submission";
    updates.directDebitStatus = "pending_submission";
  }

  if (status === "fulfilled" && mandateId) {
    const mandateResponse = await goCardlessGet(
      `/mandates/${encodeURIComponent(mandateId)}`,
      accessToken,
    );
    const mandate = mandateResponse.mandates || mandateResponse.mandate || {};
    const mandateStatus = cleanText(mandate.status);
    if (mandateStatus) {
      updates.mandateStatus = mandateStatus;
      updates.directDebitStatus = mandateStatus;
    }
    console.log("GOCARDLESS BILLING REQUEST RECONCILED", JSON.stringify({
      employerId: employerRef.id,
      billingRequestId,
      billingRequestStatus: status,
      mandateId,
      mandateStatus,
      configuredStatus: CONFIGURED_MANDATE_STATUSES.has(mandateStatus),
    }));
    await updateEmployerBilling(employerRef, updates);
    if (CONFIGURED_MANDATE_STATUSES.has(mandateStatus)) {
      await ensureGoCardlessSubscription(
        employerRef,
        mandateId,
        accessToken,
        mandateStatus,
      );
    }
    return;
  }
  await updateEmployerBilling(employerRef, updates);
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
    console.log("GOCARDLESS EVENT CORRELATION", JSON.stringify({
      eventId: cleanText(event.id),
      resourceType,
      action,
      billingRequestId,
      employerMatched: !!employerRef,
    }));
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
    console.log("GOCARDLESS EVENT CORRELATION", JSON.stringify({
      eventId: cleanText(event.id),
      resourceType,
      action,
      mandateId,
      employerMatched: !!employerRef,
    }));
    if (!employerRef) return "mandate_unmatched";
    if (["created", "submitted"].includes(action)) {
      await updateEmployerBilling(employerRef, {
        billingStatus: "mandate_pending",
        subscriptionStatus: "setup_required",
        mandateStatus: action,
        directDebitStatus: action,
        goCardlessMandateId: mandateId,
        directDebitMandateId: mandateId,
      });
      if (CONFIGURED_MANDATE_STATUSES.has(action)) {
        await ensureGoCardlessSubscription(
          employerRef,
          mandateId,
          accessToken,
          action,
        );
        return "mandate_subscription_ensured";
      }
      return "mandate_pending";
    }
	    if (["active", "reinstated"].includes(action)) {
	      await ensureGoCardlessSubscription(
	        employerRef,
	        mandateId,
	        accessToken,
	        action,
	      );
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
    console.log("GOCARDLESS EVENT CORRELATION", JSON.stringify({
      eventId: cleanText(event.id),
      resourceType,
      action,
      subscriptionId,
      employerMatched: !!employerRef,
    }));
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
	      currentPlanId: plan.id,
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
	      directDebitConfigured: false,
	      directDebitStatus: "setup_pending",
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

exports.changeGoCardlessPlan = onCall(
  {
    timeoutSeconds: 15,
    memory: "256MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please sign in to change your billing plan.",
      );
    }

    const uid = request.auth.uid;
    const userRef = admin.firestore().collection("users").doc(uid);
    const userSnap = await userRef.get();
    const user = userSnap.data() || {};
    if (!userSnap.exists || !isEmployerBillingManager(user, uid)) {
      throw new HttpsError(
        "permission-denied",
        "Only the company account owner can change billing plan.",
      );
    }

    const newPlan = planForId(cleanText(request.data && request.data.planId));
    if (!newPlan) {
      throw new HttpsError(
        "invalid-argument",
        "Choose a valid STROYKA subscription plan.",
      );
    }

    const billing = user.billing || {};
    if (!directDebitConfigured(billing)) {
      throw new HttpsError(
        "failed-precondition",
        "Set up Direct Debit before changing plan.",
      );
    }

    const currentPlan = billingPlan(billing);
    if (currentPlan && currentPlan.id === newPlan.id) {
      return await safeBillingStatus(user, uid);
    }

    const trialWindow = trialWindowForBilling(billing);
    const trialActive = trialWindow.isActive &&
      cleanText(billing.subscriptionStatus).toLowerCase() === "trial";
    const currentAmount = currentPlan ? currentPlan.amountPence : 0;
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (trialActive || newPlan.amountPence >= currentAmount) {
      await updateEmployerBilling(userRef, {
        billingStatus: "active",
        subscriptionStatus: trialActive ? "trial" : "active",
        paymentStatus: billing.paymentStatus || "pending",
        planId: newPlan.id,
        planName: newPlan.name,
        activePlanId: newPlan.id,
        activePlanName: newPlan.name,
        currentPlan: newPlan.id,
        currentPlanId: newPlan.id,
        pendingPlan: "",
        pendingPlanId: "",
        pendingPlanEffectiveAt: admin.firestore.FieldValue.delete(),
        planAmountPence: newPlan.amountPence,
        monthlyPrice: newPlan.amountPence / 100,
        currency: newPlan.currency,
        billingInterval: newPlan.interval,
        vacancySlotLimit: newPlan.vacancySlotLimit,
        planChangedAt: now,
        planChangeDirection: !currentPlan || newPlan.amountPence >= currentAmount
          ? "upgrade"
          : "trial_downgrade",
        trialStartedAt: trialWindow.startedTimestamp,
        trialStartDate: trialWindow.startedTimestamp,
        trialEndsAt: trialWindow.endsTimestamp,
        trialEndDate: trialWindow.endsTimestamp,
        trialActive,
        trialStatus: trialActive ? "active" : "expired",
      });
      await restoreBillingSuspendedVacancies(userRef);
    } else {
      const effectiveAt = billingPeriodEnd(billing);
      await updateEmployerBilling(userRef, {
        pendingPlan: newPlan.id,
        pendingPlanId: newPlan.id,
        pendingPlanName: newPlan.name,
        pendingPlanAmountPence: newPlan.amountPence,
        pendingPlanVacancySlotLimit: newPlan.vacancySlotLimit,
        pendingPlanEffectiveAt: admin.firestore.Timestamp.fromDate(effectiveAt),
        planChangeDirection: "downgrade",
        planChangeRequestedAt: now,
      });
    }

    const refreshed = await userRef.get();
    return await safeBillingStatus(refreshed.data() || {}, uid);
  },
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
    if (!(jobData.startDate instanceof admin.firestore.Timestamp)) {
      throw new HttpsError(
        "invalid-argument",
        "Expected start date is required.",
      );
    }
    const now = new Date();
    const todayUtc = Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
    );
    if (jobData.startDate.toMillis() < todayUtc) {
      throw new HttpsError(
        "invalid-argument",
        "Expected start date cannot be in the past.",
      );
    }
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
    const billingLifecycleState = cleanText(
      billing.billingStatus || billing.subscriptionStatus,
    ).toLowerCase();
    const pending = [
      "setup_pending",
      "mandate_pending",
      "setup_required",
    ].includes(billingLifecycleState) || !directDebitConfigured(billing);

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
	      directDebitEnabled: false,
	      directDebitConfigured: false,
	      mandateStatus: "cancelled",
	      directDebitStatus: "cancelled",
	      cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
	    });
	    await startPaymentGrace(
	      userRef,
	      "direct_debit_cancelled",
	      `manual_cancel_${Date.now()}`,
	    );

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
    const statusSnapshots = await Promise.all(
      ["past_due", "payment_method_required"].map((status) => firestore
        .collection("users")
        .where("billing.billingStatus", "==", status)
        .get()),
    );
    const employerDocs = new Map();
    for (const snapshot of statusSnapshots) {
      for (const doc of snapshot.docs) {
        employerDocs.set(doc.id, doc);
      }
    }

    let suspendedEmployers = 0;
    let suspendedVacancies = 0;
    for (const employerDoc of employerDocs.values()) {
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
