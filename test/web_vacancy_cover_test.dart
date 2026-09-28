import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/web_app/pages/jobs/web_job_display.dart';

void main() {
  test('selected vacancy photo becomes cover without losing other photos', () {
    final photos = ['old.jpg', 'second.jpg', 'new.jpg'];
    final reordered = webVacancyPhotosWithCover(photos, 'new.jpg');

    expect(reordered, ['new.jpg', 'old.jpg', 'second.jpg']);
    expect(webVacancyCoverPhoto(reordered), 'new.jpg');
    expect(photos, ['old.jpg', 'second.jpg', 'new.jpg']);
  });

  test('vacancy without photos has no cover', () {
    expect(webVacancyCoverPhoto(const []), isEmpty);
  });
}
