import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/portrait/portrait_web_layout.dart';
import 'package:test_app/web_app/portrait/portrait_web_navigation.dart';
import 'package:test_app/web_app/portrait/portrait_web_section.dart';

void main() {
  final automatic = Uri.parse('https://www.stroyka.uk/');

  test('automatic mode uses strict portrait aspect ratio only on Web', () {
    expect(
      resolveWebPresentationMode(
          viewport: const Size(500, 900), isWeb: true, uri: automatic),
      WebPresentationMode.portrait,
    );
    expect(
      resolveWebPresentationMode(
          viewport: const Size(900, 500), isWeb: true, uri: automatic),
      WebPresentationMode.desktop,
    );
    expect(
      resolveWebPresentationMode(
          viewport: const Size(500, 500), isWeb: true, uri: automatic),
      WebPresentationMode.desktop,
    );
    expect(
      resolveWebPresentationMode(
          viewport: const Size(500, 900), isWeb: false, uri: automatic),
      WebPresentationMode.desktop,
    );
  });

  test('URL override takes precedence only on Web', () {
    expect(
      resolveWebPresentationMode(
        viewport: const Size(1200, 700),
        isWeb: true,
        uri: Uri.parse('https://www.stroyka.uk/?layout=portrait'),
      ),
      WebPresentationMode.portrait,
    );
    expect(
      resolveWebPresentationMode(
        viewport: const Size(400, 800),
        isWeb: true,
        uri: Uri.parse('https://www.stroyka.uk/?layout=desktop'),
      ),
      WebPresentationMode.desktop,
    );
    expect(
      resolveWebPresentationMode(
        viewport: const Size(400, 800),
        isWeb: false,
        uri: Uri.parse('https://www.stroyka.uk/?layout=portrait'),
      ),
      WebPresentationMode.desktop,
    );
  });

  testWidgets('dispatcher swaps shells when viewport changes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: WebPresentationDispatcher(
        isWeb: true,
        uri: automatic,
        desktop: const Text('Desktop workspace'),
        portrait: const Text('Portrait workspace'),
      ),
    ));
    expect(find.text('Desktop workspace'), findsOneWidget);
    expect(find.text('Portrait workspace'), findsNothing);

    tester.view.physicalSize = const Size(500, 900);
    await tester.pump();
    expect(find.text('Portrait workspace'), findsOneWidget);
    expect(find.text('Desktop workspace'), findsNothing);

    tester.view.physicalSize = const Size(1200, 700);
    await tester.pump();
    expect(find.text('Desktop workspace'), findsOneWidget);
  });

  test('portrait shell has five native-style navigation destinations', () {
    expect(PortraitWebSection.values.map((section) => section.label),
        ['Jobs', 'Map', 'Applications', 'Chats', 'Profile']);
  });

  testWidgets('portrait navigation fits a narrow viewport and selects a tab',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    PortraitWebSection? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PortraitWebNavigation(
          selected: PortraitWebSection.jobs,
          applicationCount: 2,
          onSelected: (section) => selected = section,
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('portrait-nav-profile')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portrait-nav-map')));
    expect(selected, PortraitWebSection.map);
  });
}
