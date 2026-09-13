import 'package:flutter/material.dart';

import '../theme/web_theme.dart';
import 'web_auth_gate.dart';

class StroykaWebApp extends StatelessWidget {
  const StroykaWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STROYKA Web',
      debugShowCheckedModeBanner: false,
      theme: WebTheme.light,
      home: const WebAuthGate(),
    );
  }
}
