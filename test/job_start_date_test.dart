import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/job_start_date.dart';
import 'package:test_app/services/vacancy_import_service.dart';

void main() {
  test('formats expected start date consistently', () {
    expect(formatJobStartDate(DateTime(2026, 10, 12)), '12 Oct 2026');
    expect(formatJobStartDate(null), 'Not specified');
  });

  test('storage timestamp preserves the UK calendar day', () {
    final millis = jobStartDateStorageMillis(DateTime(2026, 10, 12));
    final stored = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    expect(stored, DateTime.utc(2026, 10, 12, 12));
  });

  test('vacancy import extracts only an explicitly labelled start date',
      () async {
    const text = '''
Job description: Ceiling fixer required for a commercial project.
Expected start date: 12 October 2026
Responsibilities: Install suspended ceilings.
''';
    final parsed = await VacancyImportService.parsePlatformFile(
      PlatformFile(
        name: 'vacancy.txt',
        size: utf8.encode(text).length,
        bytes: utf8.encode(text),
      ),
    );

    expect(parsed.expectedStartDate, DateTime(2026, 10, 12));
  });

  test('vacancy import does not invent an unlabelled date', () async {
    const text = '''
Job description: Long construction project through 12 October 2026.
Responsibilities: General site duties and reporting.
''';
    final parsed = await VacancyImportService.parsePlatformFile(
      PlatformFile(
        name: 'vacancy.txt',
        size: utf8.encode(text).length,
        bytes: utf8.encode(text),
      ),
    );

    expect(parsed.expectedStartDate, isNull);
  });
}
