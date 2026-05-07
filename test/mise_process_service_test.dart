import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';

void main() {
  test('diagnoses missing make for source builds', () {
    final diagnosis = diagnoseMiseCommandFailure(
      command: 'mise install redis@8.6.2',
      stderr:
          'mise [redis] Compiling Redis from source...\n'
          'sh: make: command not found\n'
          'Failed to compile Redis. Make sure you have a C compiler (gcc/clang) and make installed.',
    );

    expect(diagnosis, isNotNull);
    expect(diagnosis!.summary, contains('缺少 make'));
    expect(diagnosis.detail, contains('xcode-select --install'));
  });

  test('diagnoses missing compiler toolchain', () {
    final diagnosis = diagnoseMiseCommandFailure(
      command: 'mise install erlang@27',
      stderr: 'configure: error: no acceptable C compiler found in \$PATH',
    );

    expect(diagnosis, isNotNull);
    expect(diagnosis!.summary, contains('C 编译工具链'));
    expect(diagnosis.detail, contains('clang --version'));
  });

  test('parses shell environment output with startup banner noise', () {
    final environment = parseShellEnvironmentOutput(
      'Welcome back to zsh!\n'
      '__MISE_GUI_SHELL_ENVIRONMENT_START__\u0000'
      'PATH=/usr/local/bin:/usr/bin\u0000'
      'HOME=/Users/demo\u0000'
      '__MISE_GUI_SHELL_ENVIRONMENT_END__\u0000',
    );

    expect(environment['PATH'], '/usr/local/bin:/usr/bin');
    expect(environment['HOME'], '/Users/demo');
    expect(environment.length, 2);
  });

  test('extracts resolved executable path from noisy shell output', () {
    const resolved = MiseResolvedExecutableRef(
      subject: 'node',
      command: 'command -v node',
      exitCode: 0,
      stdout: 'Last login: Thu May  7 09:00:00 on ttys000\n'
          '/Users/demo/.local/share/mise/shims/node\n',
      stderr: '',
    );

    expect(
      resolved.resolvedPath,
      '/Users/demo/.local/share/mise/shims/node',
    );
  });
}
