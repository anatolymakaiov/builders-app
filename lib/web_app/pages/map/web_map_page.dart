import 'package:flutter/material.dart';

import '../../widgets/web_page_container.dart';
import '../../widgets/web_panel.dart';

class WebMapPage extends StatelessWidget {
  const WebMapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const WebPageContainer(
      child: WebPanel(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 42),
              SizedBox(height: 16),
              Text(
                'Map',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text('The dedicated desktop map workspace will be built here.'),
            ],
          ),
        ),
      ),
    );
  }
}
