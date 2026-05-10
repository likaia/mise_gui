import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_self_update_service.dart';

class _FakeProcessService implements MiseProcessService {
  _FakeProcessService(this._run, {this.executablePath = '/tmp/mise'});

  final Future<MiseCommandResult> Function(MiseCommandRequest request) _run;
  final String executablePath;

  @override
  Future<ShellEnvironmentLoadResult> inspectShellEnvironment() {
    throw UnimplementedError();
  }

  @override
  Future<WindowsShimPathStatus> inspectWindowsShimPath() {
    throw UnimplementedError();
  }

  @override
  Future<MiseCommandResult> run(MiseCommandRequest request) => _run(request);

  @override
  Future<String> resolveExecutablePath() async => executablePath;
}

class _FakeSystemRunner implements MiseSystemCommandRunner {
  _FakeSystemRunner({
    this.executables = const <String, String>{},
    this.resolvedPaths = const <String, String>{},
    this.results = const <String, MiseSystemCommandResult>{},
  });

  final Map<String, String> executables;
  final Map<String, String> resolvedPaths;
  final Map<String, MiseSystemCommandResult> results;
  final calls = <String>[];

  @override
  Future<String?> findExecutable(List<String> candidates) async {
    for (final candidate in candidates) {
      final resolved = executables[candidate];
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  @override
  Future<String?> resolvePath(String path) async => resolvedPaths[path] ?? path;

  @override
  Future<MiseSystemCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    void Function(MiseCommandOutputChunk chunk)? onOutput,
  }) async {
    final key = '$executable ${arguments.join(' ')}';
    calls.add(key);
    final result =
        results[key] ??
        const MiseSystemCommandResult(
          stdout: '',
          stderr: '',
          exitCode: 0,
          duration: Duration(milliseconds: 1),
        );
    if (result.stdout.isNotEmpty) {
      onOutput?.call(
        MiseCommandOutputChunk(
          source: MiseCommandOutputSource.stdout,
          text: result.stdout,
        ),
      );
    }
    if (result.stderr.isNotEmpty) {
      onOutput?.call(
        MiseCommandOutputChunk(
          source: MiseCommandOutputSource.stderr,
          text: result.stderr,
        ),
      );
    }
    return result;
  }
}

void main() {
  test(
    'selfUpdate runs non-interactive mise self-update for direct install',
    () async {
      late MiseCommandRequest capturedRequest;
      final service = GitHubMiseSelfUpdateService(
        processService: _FakeProcessService((request) async {
          capturedRequest = request;
          request.onOutput?.call(
            const MiseCommandOutputChunk(
              source: MiseCommandOutputSource.stdout,
              text: 'updated\n',
            ),
          );
          return MiseCommandResult(
            request: request,
            stdout: 'updated\n',
            stderr: '',
            exitCode: 0,
            duration: const Duration(milliseconds: 8),
          );
        }),
      );
      final chunks = <MiseCommandOutputChunk>[];

      final result = await service.selfUpdate(onOutput: chunks.add);

      expect(capturedRequest.arguments, ['self-update', '--yes']);
      expect(capturedRequest.allowNonZeroExit, isTrue);
      expect(capturedRequest.preferShellExecution, isTrue);
      expect(result.isSuccess, isTrue);
      expect(chunks.single.text, 'updated\n');
    },
  );

  test(
    'selfUpdate uses brew when active mise is installed by Homebrew',
    () async {
      final systemRunner = _FakeSystemRunner(
        executables: const {'/opt/homebrew/bin/brew': '/opt/homebrew/bin/brew'},
        resolvedPaths: const {
          '/opt/homebrew/Cellar/mise/2026.3.9/bin/mise':
              '/opt/homebrew/Cellar/mise/2026.3.9/bin/mise',
          '/opt/homebrew/opt/mise': '/opt/homebrew/Cellar/mise/2026.3.9',
        },
        results: const {
          '/opt/homebrew/bin/brew --prefix mise': MiseSystemCommandResult(
            stdout: '/opt/homebrew/opt/mise\n',
            stderr: '',
            exitCode: 0,
            duration: Duration(milliseconds: 1),
          ),
          '/opt/homebrew/bin/brew upgrade mise': MiseSystemCommandResult(
            stdout: 'upgraded\n',
            stderr: '',
            exitCode: 0,
            duration: Duration(milliseconds: 1),
          ),
        },
      );
      final service = GitHubMiseSelfUpdateService(
        processService: _FakeProcessService((request) {
          fail('brew-managed mise should not call mise self-update');
        }, executablePath: '/opt/homebrew/Cellar/mise/2026.3.9/bin/mise'),
        systemRunner: systemRunner,
      );
      final chunks = <MiseCommandOutputChunk>[];

      final result = await service.selfUpdate(onOutput: chunks.add);

      expect(result.isSuccess, isTrue);
      expect(
        systemRunner.calls,
        contains('/opt/homebrew/bin/brew upgrade mise'),
      );
      expect(chunks.single.text, 'upgraded\n');
    },
  );
}
