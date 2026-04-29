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
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

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

  /// 🔔 NOTIFICATIONS
  Stream<int> getUnreadNotifications() {
    if (userId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection("users")
        .doc(userId!)
        .collection("notifications")
        .where("read", isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  /// 💬 REAL UNREAD MESSAGES
  Stream<int> getUnreadChats() {
    if (userId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection("chats")
        .where("unreadFor", arrayContains: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<int> getUnreadApplications() {
    if (userId == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection("applications")
        .where("unreadFor", arrayContains: userId)
        .snapshots()
        .map((snap) => snap.docs.length);
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
          userId: userId!,
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
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
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
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
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
      const BottomNavigationBarItem(
        icon: Icon(Icons.person),
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

    return StreamBuilder<int>(
      stream: getUnreadNotifications(),
      builder: (context, notifSnap) {
        final notifCount = notifSnap.data ?? 0;

        return StreamBuilder<int>(
          stream: getUnreadChats(),
          builder: (context, chatSnap) {
            final chatCount = chatSnap.data ?? 0;

            return StreamBuilder<int>(
              stream: getUnreadApplications(),
              builder: (context, appSnap) {
                final applicationCount = appSnap.data ?? 0;

                final screens = getScreens();
                final items =
                    getMenuItems(notifCount, chatCount, applicationCount);

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
                  floatingActionButton: role == "employer" && currentIndex == 0
                      ? FloatingActionButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PostJobScreen(
                                  onJobCreated: (_) {},
                                ),
                              ),
                            );
                          },
                          child: const Icon(Icons.add),
                        )
                      : null,
                  bottomNavigationBar: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: BottomNavigationBar(
                        currentIndex: currentIndex,
                        items: items,
                        type: BottomNavigationBarType.fixed,
                        backgroundColor: Colors.transparent,
                        selectedItemColor: AppColors.green,
                        unselectedItemColor: Colors.white,
                        showUnselectedLabels: true,
                        onTap: (index) {
                          setState(() {
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
  }
}
