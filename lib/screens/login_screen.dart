import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../theme/stroyka_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String role = "worker"; // 🔥 выбор роли
  bool isLogin = true;
  bool loading = false;

  Future<void> submit() async {
    setState(() => loading = true);

    try {
      UserCredential result;

      if (isLogin) {
        /// LOGIN
        result = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        /// REGISTER
        result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        /// 🔥 СОЗДАЕМ USER В FIRESTORE
        await FirebaseFirestore.instance
            .collection("users")
            .doc(result.user!.uid)
            .set({
          "role": role,
          "createdAt": FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: StroykaSurface(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            texture: "assets/branding/texture_light_cloud.jpg",
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  AppAssets.logo,
                  height: 94,
                ),

                const SizedBox(height: 18),

                const Text(
                  "STROYKA",
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "Работа в строительстве",
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 32),

                /// EMAIL
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: "Email"),
                ),

                const SizedBox(height: 10),

                /// PASSWORD
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(labelText: "Password"),
                  obscureText: true,
                ),

                const SizedBox(height: 20),

                /// ROLE (только при регистрации)
                if (!isLogin)
                  DropdownButton<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: "worker", child: Text("Worker")),
                      DropdownMenuItem(
                          value: "employer", child: Text("Employer")),
                    ],
                    onChanged: (value) {
                      setState(() {
                        role = value!;
                      });
                    },
                  ),

                const SizedBox(height: 30),

                /// BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: loading ? null : submit,
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(isLogin ? "Войти" : "Зарегистрироваться"),
                  ),
                ),

                const SizedBox(height: 20),

                /// SWITCH LOGIN / REGISTER
                TextButton(
                  onPressed: () {
                    setState(() {
                      isLogin = !isLogin;
                    });
                  },
                  child: Text(
                    isLogin
                        ? "Нет аккаунта? Зарегистрироваться"
                        : "Уже есть аккаунт? Войти",
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
