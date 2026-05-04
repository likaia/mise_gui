import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/app_update_service.dart';

void main() {
  test('normalizes tag versions before comparison', () {
    expect(normalizeReleaseVersion('v1.0.0'), '1.0.0');
    expect(normalizeReleaseVersion('1.0.0+7'), '1.0.0');
    expect(normalizeReleaseVersion('refs/tags/v1.2.3'), '1.2.3');
  });

  test('compares stable versions correctly', () {
    expect(compareReleaseVersions('v1.0.1', '1.0.0'), greaterThan(0));
    expect(compareReleaseVersions('1.2.0', '1.10.0'), lessThan(0));
    expect(compareReleaseVersions('1.0.0', '1.0.0+99'), 0);
  });

  test('treats pre-release as lower than stable release', () {
    expect(compareReleaseVersions('1.0.0', '1.0.0-beta.1'), greaterThan(0));
    expect(
      compareReleaseVersions('1.0.0-beta.2', '1.0.0-beta.1'),
      greaterThan(0),
    );
  });
}
