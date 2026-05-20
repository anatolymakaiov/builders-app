import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'worker_profile_screen.dart';
import 'job_list_screen.dart';
import 'map_screen.dart';
import 'employer_dashboard_screen.dart';
import 'my_applications_screen.dart';
import 'my_chats_screen.dart';
import 'saved_jobs_screen.dart';
import 'notifications_screen.dart';
import 'employer_applications_screen.dart';
import 'post_job_screen.dart';
import 'employer_profile_screen.dart';
import 'admin_dashboard_screen.dart';
import '../services/billing_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';
import '../widgets/legal_documents.dart';
import '../widgets/profile_hamburger_menu.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int currentIndex = 0;

  String role = "worker";
  String? userId;
  bool loading = true;
  bool legalPromptShown = false;
  int _lastNotificationCount = 0;
  int _lastChatCount = 0;
  int _lastApplicationCount = 0;
  int employerProfileInitialTab = 0;

  @override
  void initState() {
    super.initState();
    initUser();
  }

  Future<void> initUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    userId = user.uid;
    unawaited(NotificationService().saveToken(user.uid));

    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance.collection("users").doc(userId).set({
          "role": "worker",
          "createdAt": FieldValue.serverTimestamp(),
        });

        role = "worker";
      } else {
        final data = doc.data();
        final rawRole = data?["role"]?.toString();
        role =
            rawRole == "admin" || rawRole == "employer" ? rawRole! : "worker";
        final hasProfile = data?["profileComplete"] == true ||
            data?["onboardingComplete"] == true ||
            data?["profileCreated"] == true ||
            (role == "worker" &&
                (data?["name"]?.toString().trim() ?? "").isNotEmpty) ||
            (role == "employer" &&
                (data?["companyName"]?.toString().trim() ?? "").isNotEmpty);

        if (hasProfile &&
            role != "admin" &&
            !LegalDocuments.hasAcceptedCurrentVersion(data, role)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            promptForUpdatedLegalDocuments();
          });
        }
      }
    } catch (e) {
      debugPrint("INIT USER ERROR: $e");
      role = "worker";
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  Future<void> promptForUpdatedLegalDocuments() async {
    if (!mounted || legalPromptShown || userId == null || role == "admin") {
      return;
    }
    legalPromptShown = true;

    final result = await Navigator.push<LegalAcceptanceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LegalAcceptanceScreen(role: role),
      ),
    );

    if (result == null) {
      legalPromptShown = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please accept required legal documents to continue"),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        promptForUpdatedLegalDocuments();
      });
      return;
    }

    try {
      await LegalDocuments.saveAcceptances(
        userId: userId!,
        role: role,
        language: result.language,
      );
    } catch (e) {
      debugPrint("LEGAL PROMPT SAVE ERROR: $e");
      legalPromptShown = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not save legal acceptance. Please try again."),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        promptForUpdatedLegalDocuments();
      });
    }
  }

  /// 🔔 NOTIFICATIONS
  Stream<int> getUnreadNotifications() {
    if (userId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection("users")
        .doc(userId!)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .snapshots()
        .map((snap) {
      unawaited(NotificationService().syncUnreadBadgeCount(userId!));
      return snap.docs.length;
    });
  }

  /// 💬 REAL UNREAD MESSAGES
  Stream<int> getUnreadChats() {
    if (userId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection("chats")
        .where("unreadFor", arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      unawaited(NotificationService().syncUnreadBadgeCount(userId!));
      return snapshot.docs.length;
    });
  }

  Stream<int> getUnreadApplications() {
    if (userId == null) return const Stream.empty();

    if (role == "employer") {
      return getUnviewedEmployerApplications(userId!);
    }

    return FirebaseFirestore.instance
        .collection("applications")
        .where("unreadFor", arrayContains: userId)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<int> getUnreadProfileNotices() {
    if (userId == null || role == "admin") return const Stream.empty();
    final controller = StreamController<int>();
    var adminInboxCount = 0;
    var policyNoticeCount = 0;

    void emit() {
      if (!controller.isClosed) {
        controller.add(adminInboxCount + policyNoticeCount);
      }
    }

    final adminSub =
        ProfileHamburgerMenu.unreadAdminInboxCountStream(userId!).listen(
      (unreadCount) {
        adminInboxCount = unreadCount;
        emit();
      },
      onError: (_) {
        adminInboxCount = 0;
        emit();
      },
    );

    final policySub = FirebaseFirestore.instance
        .collection("users")
        .doc(userId!)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .where("category", isEqualTo: "policy")
        .snapshots()
        .listen(
      (snapshot) {
        policyNoticeCount = snapshot.docs.length;
        emit();
      },
      onError: (_) {
        policyNoticeCount = 0;
        emit();
      },
    );

    controller.onCancel = () async {
      await adminSub.cancel();
      await policySub.cancel();
    };

    return controller.stream;
  }

  Future<void> openPostJobOrBilling() async {
    final employerId = userId;
    if (employerId == null) return;

    try {
      await BillingService().assertEmployerCanPost(employerId);
    } on BillingLimitException catch (e) {
      if (!mounted) return;

      final openBilling = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Choose billing plan first"),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Not now"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Open Billing"),
            ),
          ],
        ),
      );

      if (!mounted || openBilling != true) return;

      setState(() {
        employerProfileInitialTab = 4;
        currentIndex = 5;
      });
      return;
    } catch (e) {
      debugPrint("Billing pre-check error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not check billing plan. Please try again."),
        ),
      );
      return;
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostJobScreen(
          onJobCreated: (_) {},
        ),
      ),
    );
  }

  Stream<int> getUnviewedEmployerApplications(String employerId) {
    final controller = StreamController<int>();
    final applicationsRef =
        FirebaseFirestore.instance.collection("applications");

    List<QueryDocumentSnapshot<Map<String, dynamic>>>? employerDocs;
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? ownerDocs;
    late final StreamSubscription employerSub;
    late final StreamSubscription ownerSub;

    void emit() {
      final byEmployer = employerDocs;
      final byOwner = ownerDocs;
      if (byEmployer == null || byOwner == null || controller.isClosed) return;

      final seen = <String>{};
      var count = 0;
      for (final doc in [...byEmployer, ...byOwner]) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        if (data["viewedByEmployer"] != true) count++;
      }

      controller.add(count);
    }

    employerSub = applicationsRef
        .where("employerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      employerDocs = snapshot.docs;
      emit();
    }, onError: controller.addError);

    ownerSub = applicationsRef
        .where("ownerId", isEqualTo: employerId)
        .snapshots()
        .listen((snapshot) {
      ownerDocs = snapshot.docs;
      emit();
    }, onError: (error) {
      debugPrint("OWNER APPLICATION BADGE STREAM SKIPPED: $error");
      ownerDocs = const [];
      emit();
    });

    controller.onCancel = () async {
      await employerSub.cancel();
      await ownerSub.cancel();
    };

    return controller.stream;
  }

  /// 📱 SCREENS
  List<Widget> getScreens() {
    if (role == "admin") {
      return const [
        AdminDashboardScreen(),
      ];
    }

    if (role == "employer") {
      return [
        const EmployerDashboardScreen(),
        const MapScreen(),
        const EmployerApplicationsScreen(),
        const NotificationsScreen(),
        const MyChatsScreen(),
        EmployerProfileScreen(
          key: ValueKey("employer-profile-$employerProfileInitialTab"),
          userId: userId!,
          initialTab: employerProfileInitialTab,
        ),
      ];
    }

    return [
      const JobListScreen(),
      const MapScreen(),
      const SavedJobsScreen(),
      const MyApplicationsScreen(),
      const NotificationsScreen(),
      const MyChatsScreen(),
      WorkerProfileScreen(
        userId: userId!,
      ),
    ];
  }

  /// 🔴 BADGE UI
  Widget buildBadgeIcon(IconData icon, int count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                count > 9 ? '9+' : count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 📌 MENU
  List<BottomNavigationBarItem> getMenuItems(
    int notifCount,
    int chatCount,
    int applicationCount,
    int profileCount,
  ) {
    if (role == "admin") {
      return const [
        BottomNavigationBarItem(
          icon: Icon(Icons.admin_panel_settings),
          label: "Admin",
        ),
      ];
    }

    if (role == "employer") {
      return [
        const BottomNavigationBarItem(
          icon: Icon(Icons.work),
          label: "My Jobs",
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: "Map",
        ),
        BottomNavigationBarItem(
          icon: buildBadgeIcon(Icons.assignment, applicationCount),
          label: "Applications",
        ),
        BottomNavigationBarItem(
          icon: buildBadgeIcon(Icons.notifications, notifCount),
          label: "Alerts",
        ),
        BottomNavigationBarItem(
          icon: buildBadgeIcon(Icons.chat, chatCount),
          label: "Chats",
        ),
        BottomNavigationBarItem(
          icon: buildBadgeIcon(Icons.person, profileCount),
          label: "Profile",
        ),
      ];
    }

    return [
      const BottomNavigationBarItem(
        icon: Icon(Icons.work),
        label: "Jobs",
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.map),
        label: "Map",
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.favorite),
        label: "Saved",
      ),
      BottomNavigationBarItem(
        icon: buildBadgeIcon(Icons.assignment, applicationCount),
        label: "Applications",
      ),
      BottomNavigationBarItem(
        icon: buildBadgeIcon(Icons.notifications, notifCount),
        label: "Alerts",
      ),
      BottomNavigationBarItem(
        icon: buildBadgeIcon(Icons.chat, chatCount),
        label: "Chats",
      ),
      BottomNavigationBarItem(
        icon: buildBadgeIcon(Icons.person, profileCount),
        label: "Profile",
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (role == "admin") {
      return Scaffold(
        body: StroykaBackground(
          asset: AppAssets.darkBackgrounds.first,
          child: const AdminDashboardScreen(),
        ),
      );
    }

    return StreamBuilder<int>(
      stream: getUnreadNotifications(),
      builder: (context, notifSnap) {
        if (notifSnap.hasData) _lastNotificationCount = notifSnap.data ?? 0;
        final notifCount = _lastNotificationCount;

        return StreamBuilder<int>(
          stream: getUnreadChats(),
          builder: (context, chatSnap) {
            if (chatSnap.hasData) _lastChatCount = chatSnap.data ?? 0;
            final chatCount = _lastChatCount;

            return StreamBuilder<int>(
              stream: getUnreadApplications(),
              builder: (context, appSnap) {
                if (appSnap.hasData) _lastApplicationCount = appSnap.data ?? 0;
                final applicationCount = _lastApplicationCount;

                return StreamBuilder<int>(
                  stream: getUnreadProfileNotices(),
                  builder: (context, profileSnap) {
                    final profileCount = profileSnap.data ?? 0;

                    final screens = getScreens();
                    final items = getMenuItems(
                      notifCount,
                      chatCount,
                      applicationCount,
                      profileCount,
                    );

                    if (currentIndex >= screens.length) {
                      currentIndex = 0;
                    }

                    return Scaffold(
                      body: StroykaBackground(
                        asset: AppAssets.darkBackgrounds[
                            currentIndex % AppAssets.darkBackgrounds.length],
                        child: IndexedStack(
                          index: currentIndex,
                          children: screens,
                        ),
                      ),
                      floatingActionButton:
                          role == "employer" && currentIndex == 0
                              ? FloatingActionButton(
                                  onPressed: openPostJobOrBilling,
                                  child: const Icon(Icons.add),
                                )
                              : null,
                      bottomNavigationBar: SafeArea(
                        top: false,
                        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.deep.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.blueprintLine
                                  .withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.34),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: BottomNavigationBar(
                            currentIndex: currentIndex,
                            items: items,
                            type: BottomNavigationBarType.fixed,
                            backgroundColor: Colors.transparent,
                            selectedItemColor: AppColors.blueprintLine,
                            unselectedItemColor:
                                Colors.white.withValues(alpha: 0.82),
                            showUnselectedLabels: true,
                            onTap: (index) {
                              setState(() {
                                if (role == "employer" &&
                                    index == 5 &&
                                    currentIndex != 5) {
                                  employerProfileInitialTab = 0;
                                }
                                currentIndex = index;
                              });
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
