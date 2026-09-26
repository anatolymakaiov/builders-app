import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/worker_availability_service.dart';
import 'package:test_app/web_app/portrait/portrait_worker_presentation.dart';
import 'package:test_app/web_app/portrait/portrait_worker_profile_header.dart';
import 'package:test_app/web_app/services/web_profile_data_service.dart';
import 'package:test_app/web_app/widgets/web_design_components.dart';
import 'package:test_app/web_app/widgets/web_page_container.dart';

void main() {
  testWidgets('Worker portrait keeps actions but uses the shell title',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PortraitWorkerPresentation(
          child: WebPageContainer(
            child: Column(
              children: [
                WebPageHeader(
                  title: 'Jobs',
                  subtitle: 'Desktop-only repeated heading',
                  actions: [
                    TextButton(onPressed: null, child: Text('Filters'))
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Jobs'), findsNothing);
    expect(find.text('Desktop-only repeated heading'), findsNothing);
    expect(find.text('Filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop page heading is unchanged without portrait scope',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WebPageHeader(title: 'Jobs', subtitle: 'Find work'),
      ),
    ));
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Find work'), findsOneWidget);
  });

  testWidgets('Worker profile header fits narrow Web and retains actions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var switched = false;
    WorkerAvailability? changedAvailability;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PortraitWorkerProfileHeader(
            profile: const WebProfileData(
              id: 'worker-1',
              data: {'name': 'Alex Worker', 'role': 'worker'},
            ),
            ownProfile: true,
            mediaBusy: false,
            onSwitchAccount: () => switched = true,
            onEdit: () {},
            onChangeHeader: () {},
            onChangeAvatar: () {},
            onAvailabilityChanged: (value) => changedAvailability = value,
          ),
        ),
      ),
    ));
    expect(find.text('Alex Worker'), findsOneWidget);
    expect(find.text('Open to Work'), findsOneWidget);
    expect(find.byTooltip('Change avatar'), findsOneWidget);
    await tester.tap(find.byTooltip('Switch account'));
    expect(switched, isTrue);
    await tester.tap(find.byTooltip('Change availability'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Busy').last);
    expect(changedAvailability, WorkerAvailability.busy);
    expect(tester.takeException(), isNull);
  });
}
