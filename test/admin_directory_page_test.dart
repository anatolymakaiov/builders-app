import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/job_taxonomy_service.dart';
import 'package:test_app/web_app/admin/admin_directory_page.dart';
import 'package:test_app/web_app/admin/admin_directory_service.dart';
import 'package:test_app/web_app/services/web_admin_profile_service.dart';

class _DirectoryService extends AdminDirectoryService {
  int calls = 0;

  @override
  Future<AdminDirectoryPageResult> load({required String role,
    required String search, required String location, required String status,
    required List<ConstructionRole> professions, int? radiusKm,
    String? cursor}) async {
    calls++;
    if (cursor != null) {
      return const AdminDirectoryPageResult([
        AdminDirectoryEntry(WebAdminRecord('users', 'worker-2', {
          'role': 'worker', 'firstName': 'Sam', 'trade': 'Fixer',
          'city': 'Manchester',
        }), 2.0),
      ], null);
    }
    return const AdminDirectoryPageResult([
      AdminDirectoryEntry(WebAdminRecord('users', 'worker-1', {
        'role': 'worker', 'firstName': 'Alex', 'trade': 'Dryliner',
        'city': 'Manchester',
      }), 1.0),
    ], 'next');
  }
}

void main() {
  testWidgets('Admin directory loads pages and opens a selected profile',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DirectoryService();
    WebAdminRecord? opened;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      AdminDirectoryPage(role: 'worker', service: service,
        onOpenRecord: (record) async { opened = record; }))));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Profession'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Sam'), findsOneWidget);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'worker-2');
    expect(service.calls, greaterThanOrEqualTo(2));
  });
}
