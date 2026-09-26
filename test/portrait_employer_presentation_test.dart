import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/portrait/portrait_employer_presentation.dart';
import 'package:test_app/web_app/portrait/portrait_employer_profile_header.dart';
import 'package:test_app/web_app/portrait/portrait_employer_form_dialog.dart';
import 'package:test_app/web_app/services/web_profile_data_service.dart';
import 'package:test_app/web_app/widgets/web_design_components.dart';
import 'package:test_app/web_app/widgets/web_page_container.dart';

void main() {
  testWidgets('Employer portrait header shows company and usable actions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var edited = false;
    var switched = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PortraitEmployerPresentation(
            child: PortraitEmployerProfileHeader(
              profile: const WebProfileData(
                id: 'employer-1',
                data: {'companyName': 'Build Right Ltd', 'role': 'employer'},
              ),
              ownProfile: true,
              mediaBusy: false,
              onEdit: () => edited = true,
              onChangeAvatar: () {},
              onChangeHeader: () {},
              onSwitchAccount: () => switched = true,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Build Right Ltd'), findsOneWidget);
    expect(find.byTooltip('Change logo'), findsOneWidget);
    expect(find.byTooltip('Change header'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit company profile'));
    await tester.tap(find.byTooltip('Switch account'));
    expect(edited, isTrue);
    expect(switched, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employer portrait uses shell heading and keeps page actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PortraitEmployerPresentation(
          child: WebPageHeader(
            title: 'Jobs',
            subtitle: 'Desktop-only heading',
            actions: [
              TextButton(onPressed: () {}, child: const Text('Post a job')),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('Jobs'), findsNothing);
    expect(find.text('Desktop-only heading'), findsNothing);
    expect(find.text('Post a job'), findsOneWidget);
  });

  testWidgets('Forced portrait limits content width on a wide browser',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PortraitEmployerPresentation(
          child: WebPageContainer(
            child: ColoredBox(
              key: ValueKey('portrait-content'),
              color: Colors.blue,
              child: SizedBox(height: 40, width: double.infinity),
            ),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byKey(const ValueKey('portrait-content'))).width,
        lessThanOrEqualTo(696));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Employer portrait form scrolls and keeps primary action visible',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var submitted = false;
    await tester.pumpWidget(MaterialApp(
      home: PortraitEmployerFormDialog(
        title: 'Make offer',
        body: ListView(children: [
          for (var index = 0; index < 18; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                decoration: InputDecoration(labelText: 'Field $index'),
              ),
            ),
        ]),
        actions: [
          FilledButton(
            onPressed: () => submitted = true,
            child: const Text('Send offer'),
          ),
        ],
      ),
    ));
    expect(find.text('Make offer'), findsOneWidget);
    await tester.tap(find.text('Send offer'));
    expect(submitted, isTrue);
    expect(tester.takeException(), isNull);
  });
}
