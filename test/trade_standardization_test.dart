import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/job.dart';
import 'package:test_app/services/job_taxonomy_service.dart';
import 'package:test_app/services/registration_validation_service.dart';
import 'package:test_app/widgets/trade_selector.dart';

void main() {
  test('catalog IDs are stable and unique', () {
    final ids = JobTaxonomyService.roles.map((role) => role.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(
        JobTaxonomyService.roleFor('fire_stopper')?.canonical, 'Fire Stopper');
    expect(JobTaxonomyService.roleFor('ceiling_fixer')?.canonical,
        'Ceiling Fixer');
  });

  test('known Dryliner spellings resolve to one ID', () {
    for (final value in [
      'Dryliner',
      'dry liner',
      'Drywall Fixer',
      'drylining',
      'dry lining',
      'drylining_fixer',
      'board fixer',
    ]) {
      expect(JobTaxonomyService.roleFor(value)?.id, 'dryliner', reason: value);
    }
    expect(
      JobTaxonomyService.suggestions('fixer').map((role) => role.id),
      contains('dryliner'),
    );
    expect(JobTaxonomyService.roleFor('unknown invention'), isNull);
  });

  test('worker fields accept one to three unique canonical trades', () {
    final ids = ['dryliner', 'fire_stopper', 'ceiling_fixer'];
    final fields = JobTaxonomyService.workerTradeFields(ids);
    expect(fields['primaryTradeId'], 'dryliner');
    expect(fields['tradeIds'], ids);
    expect(fields['trade'], 'Dryliner');
    expect(() => JobTaxonomyService.workerTradeFields([...ids, 'plasterer']),
        throwsArgumentError);
    expect(() => JobTaxonomyService.workerTradeFields(['dryliner', 'dryliner']),
        throwsArgumentError);
    expect(() => JobTaxonomyService.workerTradeFields(['invented_trade']),
        throwsArgumentError);
  });

  test('legacy worker values render without corrupting unknown values', () {
    expect(JobTaxonomyService.workerTradeIds({'trade': 'Dry Liner'}),
        ['dryliner']);
    expect(JobTaxonomyService.workerTradeLabels({'trade': 'Historic craft'}),
        ['Historic craft']);
    expect(JobTaxonomyService.workerTradeIds({'trade': 'Historic craft'}),
        isEmpty);
    expect(
      JobTaxonomyService.workerTradeIds({
        'primaryTradeId': 'unknown_old_id',
        'trade': 'Dry Liner',
      }),
      ['dryliner'],
    );
  });

  test('new registration never persists an unknown free-text trade', () {
    const details = PendingRegistrationDetails(
      email: 'worker@example.com',
      role: 'worker',
      registrationName: 'Alex Worker',
      phone: '',
      normalizedPhone: '',
      trade: 'Unlisted historical occupation',
    );
    final data = details.toUserDocument();
    expect(data.containsKey('tradeIds'), isFalse);
    expect(data.containsKey('registrationPosition'), isFalse);
  });

  test('job search matches canonical and legacy Dryliner by alias', () {
    final canonical = Job.fromFirestore('1', {
      'title': 'Dryliner',
      'trade': 'Dryliner',
      'canonicalRoleId': 'dryliner',
    });
    final legacy = Job.fromFirestore('2', {
      'title': 'Drywall Fixer',
      'trade': 'Drywall Fixer',
    });
    for (final job in [canonical, legacy]) {
      expect(JobTaxonomyService.matchesJob(job, 'fixer'), isTrue);
      expect(JobTaxonomyService.matchesJob(job, 'drywall fixer'), isTrue);
      expect(JobTaxonomyService.matchesTradeFilter(job, 'Dryliner'), isTrue);
    }
  });

  testWidgets('trade selector shows aliases and stops after three selections',
      (tester) async {
    var ids = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return TradeSelector(
            tradeIds: ids,
            onChanged: (next) => setState(() => ids = next),
          );
        }),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'drywall fixer');
    await tester.pumpAndSettle();
    expect(find.text('Dryliner'), findsWidgets);
    await tester.tap(find.text('Dryliner').last);
    await tester.pumpAndSettle();
    expect(ids, ['dryliner']);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TradeSelector(
          tradeIds: const ['dryliner', 'fire_stopper', 'ceiling_fixer'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(InputChip), findsNWidgets(3));
  });
}
