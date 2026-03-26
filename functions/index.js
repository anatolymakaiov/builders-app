const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendChatNotification = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {

    const message = event.data.data();
    const chatId = event.params.chatId;

    /// 1. получаем чат
    const chatDoc = await admin.firestore()
      .collection("chats")
      .doc(chatId)
      .get();

    if (!chatDoc.exists) return;

    const chat = chatDoc.data();

    /// 2. кто отправил
    const senderId = message.senderId;

    /// 3. кому отправить
    const receiverId =
      senderId === chat.workerId
        ? chat.employerId
        : chat.workerId;

    /// 4. получаем пользователя
    const userDoc = await admin.firestore()
      .collection("users")
      .doc(receiverId)
      .get();

    if (!userDoc.exists) return;

    const token = userDoc.data().fcmToken;

    if (!token) return;

    /// 5. отправляем push
    await admin.messaging().send({
      token: token,
      notification: {
        title: "New message",
        body: message.text,
      },
    });
  }
);