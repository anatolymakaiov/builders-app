import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application_details_screen.dart';
import 'chat_screen.dart';
import 'job_details_screen.dart';
import 'worker_profile_screen.dart';
import '../models/job.dart';
import '../services/calendar_service.dart';
import '../services/app_navigation.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/profile_hamburger_menu.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  Future<void> handleNotificationTap(
    BuildContext context,
    DocumentReference reference,
    Map<String, dynamic> data,
  ) {
    return _NotificationsScreenState().handleNotificationTap(
      context,
      reference,
      data,
    );
  }

  void openNotificationDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    _NotificationsScreenState().openNotificationDetails(context, data);
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Set<String> expandedNotifications = {};
  int refreshTick = 0;

  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  Future<void> refreshNotifications() async {
    setState(() => refreshTick++);
  }

  String? cleanId(dynamic value) {
    final text = value?.toString().trim() ?? "";
    if (text.isEmpty || text == "null") return null;
    return text;
  }

  String notificationTitle(Map<String, dynamic> data) {
    final type = data["type"] ?? "";
    final title = data["title"]?.toString();
    if (title != null && title.isNotEmpty) return title;

    switch (type) {
      case "application":
        return "New application received";
      case "accepted":
        return "You got accepted";
      case "rejected":
        return "Application rejected";
      case "message":
        return "New message";
      case "job_alert":
        return "New matching job";
      case "application_status":
        return "Application status updated";
      case "offer":
        return "New offer received";
      case "offer_accepted":
        return "Offer accepted";
      case "offer_rejected":
        return "Offer rejected";
      case "offer_expiry":
        return "Offer expiry reminder";
      case "work_start":
        return "Work start reminder";
      case "job_status":
        return "Job status updated";
      case "billing":
        return "Billing update";
      case "report":
        return "Complaint update";
      case "admin_message":
        return "Admin message";
      case "package_approval":
        return "Package approval update";
      default:
        return "Notification";
    }
  }

  Future<void> openJobNotification(
    BuildContext context, {
    required String jobId,
    String? applicationId,
  }) async {
    final jobDoc =
        await FirebaseFirestore.instance.collection("jobs").doc(jobId).get();

    if (!jobDoc.exists) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This job is no longer available")),
      );
      return;
    }

    final job = Job.fromFirestore(jobDoc.id, jobDoc.data()!);
    if (job.isClosed || jobDoc.data()?["deleted"] == true) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This item is no longer available.")),
      );
      return;
    }

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailScreen(
          job: job,
          applicationId: applicationId,
        ),
      ),
    );
  }

  Future<void> openApplicationNotification(
    BuildContext context, {
    required String applicationId,
    bool openWorkerJobDetails = false,
    String? fallbackJobId,
  }) async {
    final appDoc = await FirebaseFirestore.instance
        .collection("applications")
        .doc(applicationId)
        .get();

    if (!appDoc.exists || appDoc.data() == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("This application is no longer available")),
      );
      return;
    }

    final appData = appDoc.data()!;
    appData["id"] = appDoc.id;

    if (openWorkerJobDetails) {
      final jobId = cleanId(appData["jobId"] ?? fallbackJobId);
      if (jobId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This offer is missing the related job details"),
          ),
        );
        return;
      }

      if (!context.mounted) return;
      await openJobNotification(
        context,
        jobId: jobId,
        applicationId: applicationId,
      );
      return;
    }

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ApplicationDetailsScreen(
          applicationId: applicationId,
          data: appData,
        ),
      ),
    );
  }

  Future<String?> resolveApplicationId(
    Map<String, dynamic> data, {
    String? preferredId,
    String? fallbackJobId,
  }) async {
    final direct = cleanId(preferredId) ??
        cleanId(data["relatedApplicationId"]) ??
        cleanId(data["applicationId"]);
    if (direct != null) {
      final directDoc = await FirebaseFirestore.instance
          .collection("applications")
          .doc(direct)
          .get();
      if (directDoc.exists) return direct;
    }

    final targetId = cleanId(data["targetId"]);
    if (targetId != null && targetId != fallbackJobId) {
      final targetDoc = await FirebaseFirestore.instance
          .collection("applications")
          .doc(targetId)
          .get();
      if (targetDoc.exists) return targetId;
    }

    final jobId = cleanId(fallbackJobId) ??
        cleanId(data["relatedJobId"]) ??
        cleanId(data["jobId"]) ??
        targetId;
    if (jobId == null) return null;

    final uid = userId;
    final role = await currentUserRole();
    QuerySnapshot<Map<String, dynamic>> query;
    if (role == "employer" && uid != null) {
      query = await FirebaseFirestore.instance
          .collection("applications")
          .where("jobId", isEqualTo: jobId)
          .where("employerId", isEqualTo: uid)
          .limit(1)
          .get();
    } else if (uid != null) {
      query = await FirebaseFirestore.instance
          .collection("applications")
          .where("jobId", isEqualTo: jobId)
          .where("members", arrayContains: uid)
          .limit(1)
          .get();
    } else {
      return null;
    }

    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  Future<String?> currentUserRole() async {
    final uid = userId;
    if (uid == null) return null;

    final userDoc =
        await FirebaseFirestore.instance.collection("users").doc(uid).get();
    return userDoc.data()?["role"]?.toString().trim().toLowerCase();
  }

  bool isWorkerOfferNotification(Map<String, dynamic> data) {
    return isOfferRelatedNotification(data);
  }

  bool isOfferRelatedNotification(Map<String, dynamic> data) {
    final type = data["type"]?.toString().trim().toLowerCase() ?? "";
    final category = data["category"]?.toString().trim().toLowerCase() ?? "";
    return category == "offer" ||
        type == "offer" ||
        type == "offer_accepted" ||
        type == "offer_rejected" ||
        type == "offer_expiry" ||
        type == "work_start" ||
        type == "work_start_reminder";
  }

  Future<bool> openOfferRelatedNotification(
    BuildContext context,
    Map<String, dynamic> data, {
    String? applicationId,
    String? jobId,
  }) async {
    if (!isOfferRelatedNotification(data)) return false;

    final id = await resolveApplicationId(
      data,
      preferredId: applicationId,
      fallbackJobId: jobId,
    );
    if (!context.mounted) return true;
    if (id == null) {
      openNotificationDetails(context, data);
      return true;
    }

    await openApplicationNotification(
      context,
      applicationId: id,
      fallbackJobId: jobId,
      openWorkerJobDetails: true,
    );
    return true;
  }

  Future<void> openChatNotification(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final chatId = cleanId(data["chatId"] ?? data["targetId"]);
    if (chatId != null) {
      final chatDoc = await FirebaseFirestore.instance
          .collection("chats")
          .doc(chatId)
          .get();
      if (!chatDoc.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This chat is no longer available")),
        );
        return;
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)),
      );
      return;
    }

    final jobId = cleanId(data["jobId"] ?? data["relatedJobId"]);
    if (jobId == null) {
      openNotificationDetails(context, data);
      return;
    }

    final chatQuery = await FirebaseFirestore.instance
        .collection("chats")
        .where("jobId", isEqualTo: jobId)
        .limit(1)
        .get();

    if (!context.mounted) return;

    if (chatQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This chat is no longer available")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatQuery.docs.first.id),
      ),
    );
  }

  void openBillingNotification(BuildContext context) {
    final uid = userId;
    if (uid == null) {
      openNotificationDetails(context, const {});
      return;
    }

    shellNavigationCommand.value = const ShellNavigationCommand(
      role: "employer",
      tabIndex: 5,
      employerProfileInitialTab: 4,
    );
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
  }

  void openNotificationDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationDetailsScreen(data: data),
      ),
    );
  }

  String targetTypeFor(Map<String, dynamic> data) {
    final explicit = cleanId(data["targetType"]);
    if (explicit != null) return explicit;

    final type = data["type"]?.toString() ?? "";
    if (type == "message" || cleanId(data["chatId"]) != null) return "chat";
    if (type == "billing" || cleanId(data["relatedPaymentRequestId"]) != null) {
      return "billing";
    }
    if (type == "report" || cleanId(data["relatedReportId"]) != null) {
      return "report";
    }
    if (type == "support" || cleanId(data["relatedSupportRequestId"]) != null) {
      return "support_request";
    }
    if (type == "admin_message") return "admin_message";
    if (isOfferRelatedNotification(data)) {
      return "offer";
    }
    if (type == "application" ||
        type == "application_status" ||
        type == "work_start") {
      return "application";
    }
    if (type == "job_alert" ||
        type == "job_status" ||
        type == "package_approval") {
      return "job";
    }

    if (cleanId(data["applicationId"] ?? data["relatedApplicationId"]) !=
        null) {
      return "application";
    }
    if (cleanId(data["jobId"] ?? data["relatedJobId"]) != null) return "job";

    return "notification";
  }

  Future<void> handleNotificationTap(
    BuildContext context,
    DocumentReference reference,
    Map<String, dynamic> data,
  ) async {
    await reference.set({
      "read": true,
      "readAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final uid = userId;
    if (uid != null) {
      await NotificationService().syncUnreadBadgeCount(uid);
    }

    if (!context.mounted) return;

    final targetType = targetTypeFor(data);
    final targetId = cleanId(data["targetId"]);
    final applicationId = cleanId(
      data["relatedApplicationId"] ?? data["applicationId"],
    );
    final jobId = cleanId(data["relatedJobId"] ?? data["jobId"]);
    final workerId = cleanId(data["workerId"]);
    final role = await currentUserRole();
    if (!context.mounted) return;

    if (await openOfferRelatedNotification(
      context,
      data,
      applicationId: applicationId,
      jobId: jobId,
    )) {
      return;
    }
    if (!context.mounted) return;

    switch (targetType) {
      case "application":
      case "offer":
        final id = await resolveApplicationId(
          data,
          preferredId: applicationId,
          fallbackJobId: jobId,
        );
        if (!context.mounted) return;
        if (id != null) {
          await openApplicationNotification(
            context,
            applicationId: id,
            fallbackJobId: jobId,
            openWorkerJobDetails:
                role == "worker" && isWorkerOfferNotification(data),
          );
          return;
        }
        break;
      case "job":
      case "inactive_job":
      case "expired_job":
        final id = jobId ?? targetId;
        if (id != null) {
          await openJobNotification(
            context,
            jobId: id,
            applicationId: applicationId,
          );
          return;
        }
        break;
      case "billing":
      case "payment":
      case "payment_request":
        openBillingNotification(context);
        return;
      case "chat":
        await openChatNotification(context, data);
        return;
      case "worker":
        final id = targetId ?? workerId;
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => WorkerProfileScreen(userId: id)),
          );
          return;
        }
        break;
      case "support_request":
      case "report":
        openNotificationDetails(context, data);
        return;
      case "admin_message":
        final currentUser = FirebaseAuth.instance.currentUser;
        final threadId = cleanId(data["threadId"] ?? targetId);
        final messageId = cleanId(data["adminMessageId"]);
        if (currentUser != null && threadId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminInboxMessageScreen(
                userId: currentUser.uid,
                role: role ?? "",
                threadId: threadId,
                initialMessageId: messageId ?? threadId,
              ),
            ),
          );
          return;
        }
        openNotificationDetails(context, data);
        return;
      case "notification":
        openNotificationDetails(context, data);
        return;
    }

    if (!context.mounted) return;

    if (applicationId != null) {
      final id = await resolveApplicationId(
        data,
        preferredId: applicationId,
        fallbackJobId: jobId,
      );
      if (!context.mounted) return;
      if (id == null) {
        openNotificationDetails(context, data);
        return;
      }
      await openApplicationNotification(
        context,
        applicationId: id,
        fallbackJobId: jobId,
        openWorkerJobDetails:
            role == "worker" && isWorkerOfferNotification(data),
      );
      return;
    }
    if (!context.mounted) return;

    if (jobId != null) {
      await openJobNotification(
        context,
        jobId: jobId,
        applicationId: applicationId,
      );
      return;
    }

    if (!context.mounted) return;
    openNotificationDetails(context, data);
  }

  Future<void> expandNotification(
    DocumentReference reference,
    String notificationId,
    Map<String, dynamic> data,
  ) async {
    final isExpanded = expandedNotifications.contains(notificationId);

    setState(() {
      if (isExpanded) {
        expandedNotifications.remove(notificationId);
      } else {
        expandedNotifications.add(notificationId);
      }
    });

    if (!isExpanded && data["read"] != true) {
      await reference.set({
        "read": true,
        "readAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final uid = userId;
      if (uid != null) {
        await NotificationService().syncUnreadBadgeCount(uid);
      }
    }
  }

  String notificationBody(Map<String, dynamic> data) {
    return (data["body"] ?? data["message"] ?? "Tap to read")?.toString() ??
        "Tap to read";
  }

  String notificationTimeLabel(dynamic value) {
    DateTime? date;
    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }
    if (date == null) return "";

    final now = DateTime.now();
    final isToday =
        now.year == date.year && now.month == date.month && now.day == date.day;
    String two(int number) => number.toString().padLeft(2, "0");
    if (isToday) return "${two(date.hour)}:${two(date.minute)}";
    return "${two(date.day)}/${two(date.month)}";
  }

  Future<bool> confirmDeleteItem(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete item"),
        content: const Text("Are you sure you want to delete this item?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    return result == true;
  }

  Widget deleteBackground() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(Icons.delete_outline, color: Colors.white),
          SizedBox(width: 8),
          Text(
            "Delete",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> deleteNotification(
    BuildContext context,
    QueryDocumentSnapshot doc,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await confirmDeleteItem(context);
    if (!confirmed) return false;
    final uid = userId;
    await doc.reference.set({
      "deleted": true,
      if (uid != null) "hiddenForUsers": FieldValue.arrayUnion([uid]),
      "read": true,
      "deletedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (uid != null) {
      await NotificationService().syncUnreadBadgeCount(uid);
    }
    return true;
  }

  Widget buildNotificationCard({
    required BuildContext context,
    required QueryDocumentSnapshot doc,
    required Map<String, dynamic> data,
  }) {
    final read = data["read"] == true;
    final type = data["type"]?.toString() ?? "";
    final body = notificationBody(data);
    final titleText = notificationTitle(data);
    final isExpanded = expandedNotifications.contains(doc.id);
    final timeLabel = notificationTimeLabel(data["createdAt"]);
    final canAddCalendar =
        (type == "work_start" || type == "offer" || type == "offer_accepted") &&
            data["offer"] is Map;

    return Dismissible(
      key: ValueKey("notification-${doc.id}"),
      direction: DismissDirection.endToStart,
      background: deleteBackground(),
      confirmDismiss: (_) => deleteNotification(context, doc, data),
      child: StroykaSurface(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        texture: read
            ? "assets/branding/texture_light_triangles.jpg"
            : "assets/branding/texture_light_dots.jpg",
        child: AnimatedSize(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => expandNotification(doc.reference, doc.id, data),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!read)
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(top: 7, right: 9),
                          decoration: const BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          titleText,
                          maxLines: isExpanded ? null : 1,
                          overflow: isExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 16,
                            fontWeight:
                                read ? FontWeight.w700 : FontWeight.w900,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.more_horiz,
                        color: AppColors.blueprint,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: isExpanded ? 0 : 42,
                    ),
                    child: Text(
                      body,
                      maxLines: isExpanded ? null : 2,
                      overflow: isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 14,
                        height: 1.32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 12),
                    Divider(
                      color: AppColors.blueprintLine.withValues(alpha: 0.35),
                      height: 1,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => expandNotification(
                            doc.reference,
                            doc.id,
                            {...data, "read": true},
                          ),
                          icon: const Icon(Icons.expand_less, size: 18),
                          label: const Text("Collapse"),
                        ),
                        const Spacer(),
                        if (canAddCalendar)
                          IconButton(
                            tooltip: "Add to calendar",
                            icon: const Icon(Icons.calendar_month),
                            onPressed: () => addNotificationOfferToCalendar(
                              context,
                              data,
                            ),
                          ),
                        ElevatedButton.icon(
                          onPressed: () => handleNotificationTap(
                            context,
                            doc.reference,
                            data,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 17),
                          label: const Text("Open"),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> addNotificationOfferToCalendar(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final offerRaw = data["offer"];
    if (offerRaw is! Map) return;

    final offer = Map<String, dynamic>.from(offerRaw);
    final title = data["jobTitle"]?.toString() ??
        data["title"]?.toString() ??
        "Construction job";

    final added = await CalendarService.addOfferToCalendar(
      title: title,
      offer: offer,
      fallbackLocation:
          (data["jobAddress"] ?? data["jobLocation"] ?? data["siteAddress"])
              ?.toString(),
      workerName: data["workerName"]?.toString(),
      contactInfo: data["contactInfo"]?.toString(),
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added
              ? "Offer added to calendar"
              : "Enter the start date in a calendar-readable format",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
      ),
      body: StroykaScreenBody(
        child: StreamBuilder<QuerySnapshot>(
          key: ValueKey("notifications-$refreshTick"),
          stream: FirebaseFirestore.instance
              .collection("users")
              .doc(userId!)
              .collection("notifications")
              .orderBy("createdAt", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = (snapshot.data?.docs ?? []).where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final hiddenForUsers = data["hiddenForUsers"];
              return data["deleted"] != true &&
                  !(hiddenForUsers is List && hiddenForUsers.contains(userId));
            }).toList();

            if (docs.isEmpty) {
              return RefreshIndicator(
                onRefresh: refreshNotifications,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 220),
                    Center(child: Text("No notifications")),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: refreshNotifications,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;

                  return buildNotificationCard(
                    context: context,
                    doc: doc,
                    data: data,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class NotificationDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const NotificationDetailsScreen({
    super.key,
    required this.data,
  });

  String valueText(dynamic value) {
    if (value == null) return "";
    if (value is Timestamp) return value.toDate().toString();
    if (value is Map || value is List) return value.toString();
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final title = data["title"]?.toString() ?? "Notification";
    final message = (data["message"] ?? data["body"])?.toString() ?? "";
    final rows = [
      ("Type", data["type"]),
      ("Status", data["status"]),
      ("Job", data["jobId"] ?? data["relatedJobId"]),
      ("Application", data["applicationId"] ?? data["relatedApplicationId"]),
      ("Payment request", data["relatedPaymentRequestId"]),
      ("Support request", data["relatedSupportRequestId"]),
      ("Report", data["relatedReportId"]),
      ("Created", data["createdAt"]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Notification")),
      body: StroykaScreenBody(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            StroykaSurface(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(message),
                  ],
                  const SizedBox(height: 18),
                  ...rows.map((row) {
                    final value = valueText(row.$2);
                    if (value.isEmpty) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              row.$1,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
