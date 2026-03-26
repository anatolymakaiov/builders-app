import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              const Icon(Icons.construction, size: 70, color: Colors.orange),

              const SizedBox(height: 20),

              const Text(
                "Builder Jobs",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 40),

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
                    DropdownMenuItem(value: "employer", child: Text("Employer")),
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
                      : Text(isLogin ? "Login" : "Register"),
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
                      ? "No account? Register"
                      : "Already have account? Login",
                ),
              )

            ],
          ),
        ),
      ),
    );
  }
}