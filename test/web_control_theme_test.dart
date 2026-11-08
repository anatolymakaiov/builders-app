import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/theme/web_theme.dart';
import 'package:test_app/web_app/widgets/web_toolbar_field.dart';

void main() {
  testWidgets('Web search, select and actions share compact toolbar height',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      theme: WebTheme.light,
      home: Scaffold(
        body: Row(children: [
          const SizedBox(
            width: 240,
            child: WebToolbarField(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: 'all',
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [DropdownMenuItem(value: 'all', child: Text('All'))],
              onChanged: (_) {},
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(
            width: 180,
            child: TextField(
              decoration: InputDecoration(labelText: 'Job title'),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit),
            label: const Text('New message'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.tune),
            label: const Text('Filters'),
          ),
        ]),
      ),
    ));

    final search = tester.getRect(find.byType(WebToolbarField));
    final dropdown =
        tester.getRect(find.byType(DropdownButtonFormField<String>));
    final filled = tester.getRect(find.byType(FilledButton));
    final outlined = tester.getRect(find.byType(OutlinedButton));
    final plainInput = tester.getRect(find.byType(TextField).last);
    for (final entry in {
      'search': search,
      'dropdown': dropdown,
      'filled': filled,
      'outlined': outlined,
      'plain input': plainInput,
    }.entries) {
      final rect = entry.value;
      expect(rect.height, WebToolbar.controlHeight, reason: entry.key);
      expect(rect.top, search.top);
      expect(rect.bottom, search.bottom);
    }
    expect(
      Theme.of(tester.element(find.byType(FilledButton)))
          .filledButtonTheme
          .style!
          .backgroundColor!
          .resolve({}),
      WebTheme.accentSoft,
    );
    expect(WebToolbar.primaryActionStyle.backgroundColor!.resolve({}),
        WebTheme.accent);
    expect(WebToolbar.primaryActionStyle.minimumSize!.resolve({})!.height,
        WebToolbar.controlHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Web controls keep their height when toolbar wraps',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 430.0, 768.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(MaterialApp(
        theme: WebTheme.light,
        home: Scaffold(
          body: Wrap(spacing: 12, runSpacing: 12, children: [
            const SizedBox(
              width: 180,
              child: TextField(
                decoration: InputDecoration(hintText: 'Search jobs'),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: 'all',
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All'))
                ],
                onChanged: (_) {},
              ),
            ),
            FilledButton(onPressed: () {}, child: const Text('Post Job')),
          ]),
        ),
      ));
      for (final finder in [
        find.byType(TextField),
        find.byType(DropdownButtonFormField<String>),
        find.byType(FilledButton),
      ]) {
        expect(tester.getRect(finder).height, WebToolbar.controlHeight);
      }
      expect(tester.takeException(), isNull);
    }
  });
}
