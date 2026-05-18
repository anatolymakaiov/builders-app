const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

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

    const tokens = tokenList(user);
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
      await admin.firestore().collection("users").doc(userId).set(
        {
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
          push: {
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );
    }
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
    const senderId = message.senderId;
    const receiverId = senderId === chat.workerId ? chat.employerId : chat.workerId;
    if (!receiverId) return;

    const notificationRef = admin
      .firestore()
      .collection("users")
      .doc(receiverId)
      .collection("notifications")
      .doc();

    await notificationRef.set({
      notificationId: notificationRef.id,
      userId: receiverId,
      type: "message",
      category: "chat",
      title: "New message",
      message: message.text || "New chat message",
      body: message.text || "New chat message",
      targetType: "chat",
      targetId: chatId,
      chatId,
      read: false,
      badgeEligible: true,
      pushEligible: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      push: {
        title: "New message",
        body: message.text || "New chat message",
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
    });
  },
);
