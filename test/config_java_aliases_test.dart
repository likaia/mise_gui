import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/features/config/presentation/config_page.dart';

void main() {
  test('writes default java aliases when enabled', () {
    final next = buildJavaAliasesConfigContent(
      currentContent: '[tools]\njava = "21"\n',
      enabled: true,
      aliases: javaAliasDefaults,
    );

    expect(next, contains('[tool_alias.java.versions]'));
    expect(next, contains('8 = "corretto-8"'));
    expect(next, contains('21 = "corretto-21"'));
    expect(next, contains('25 = "corretto-25"'));
  });

  test('removes java alias section when disabled', () {
    final next = buildJavaAliasesConfigContent(
      currentContent:
          '[tools]\n'
          'java = "21"\n'
          '\n'
          '[tool_alias.java.versions]\n'
          '8 = "corretto-8"\n'
          '21 = "corretto-21"\n'
          '\n'
          '[settings]\n'
          'http_retries = 2\n',
      enabled: false,
      aliases: const {},
    );

    expect(next, isNot(contains('[tool_alias.java.versions]')));
    expect(next, isNot(contains('corretto-21')));
    expect(next, contains('[tools]'));
    expect(next, contains('[settings]'));
  });

  test('replaces existing java aliases with edited values', () {
    final next = buildJavaAliasesConfigContent(
      currentContent:
          '[tool_alias.java.versions]\n'
          '8 = "corretto-8"\n',
      enabled: true,
      aliases: const {'21': 'temurin-21'},
    );

    expect(next, contains('21 = "temurin-21"'));
    expect(next, isNot(contains('corretto-8')));
  });
}
