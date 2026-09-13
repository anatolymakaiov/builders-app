import 'package:flutter/material.dart';

import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebChatsPage extends StatelessWidget {
  const WebChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WebPageContainer(
      child: WebPanel(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 42),
              SizedBox(height: 16),
              Text(
                'Chats',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text('The dedicated desktop chat workspace will be built here.'),
            ],
          ),
        ),
      ),
    );
  }
}
