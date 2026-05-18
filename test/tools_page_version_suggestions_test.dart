import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/features/tools/presentation/tools_page.dart';
import 'package:mise_gui/services/mise_query_service.dart';

void main() {
  test('selects the latest release for each major version', () {
    final selected = selectVersionSuggestions(const [
      MiseRemoteToolVersionRef(
        tool: 'node',
        version: '20.18.0',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'node',
        version: '20.19.0',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(tool: 'node', version: '19.9.0', rolling: false),
      MiseRemoteToolVersionRef(
        tool: 'node',
        version: '19.10.0',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'node',
        version: '18.20.4',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'node',
        version: '18.19.1',
        rolling: false,
      ),
    ]);

    expect(selected, ['20.19.0', '19.10.0', '18.20.4']);
  });

  test('handles vendor-prefixed java versions by major line', () {
    final selected = selectVersionSuggestions(const [
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-21.0.10+7.0.LTS',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-21.0.11+9.0.LTS',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'zulu-jre-javafx-26.30.11.0',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-21.0.11+9.0.LTS-jre',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(
        tool: 'java',
        version: 'temurin-17.0.16+8.0.LTS',
        rolling: false,
      ),
      MiseRemoteToolVersionRef(tool: 'java', version: '21.0.2', rolling: false),
    ]);

    expect(selected, ['temurin-21.0.11+9.0.LTS', 'temurin-17.0.16+8.0.LTS']);
  });
}
