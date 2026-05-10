import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/mise_action_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class _FakeProcessService implements MiseProcessService {
  _FakeProcessService(this._run);

  final Future<MiseCommandResult> Function(MiseCommandRequest request) _run;

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
  Future<String> resolveExecutablePath() {
    throw UnimplementedError();
  }
}

void main() {
  test('emits progress events for command stages and output', () async {
    final processService = _FakeProcessService((request) async {
      request.onOutput?.call(
        const MiseCommandOutputChunk(
          source: MiseCommandOutputSource.stdout,
          text: 'installing sdk\n',
        ),
      );
      return MiseCommandResult(
        request: request,
        stdout: 'installing sdk\n',
        stderr: '',
        exitCode: 0,
        duration: const Duration(milliseconds: 10),
      );
    });
    final service = LocalMiseActionService(processService);
    final events = <MiseActionProgressEvent>[];

    final result = await service.runScript(
      'mise install flutter@3.41.4\nmise use --global flutter@3.41.4',
      onProgress: events.add,
    );

    expect(result.isSuccess, isTrue);
    expect(
      events.map((event) => event.type),
      containsAllInOrder([
        MiseActionProgressEventType.commandStarted,
        MiseActionProgressEventType.output,
        MiseActionProgressEventType.commandFinished,
        MiseActionProgressEventType.commandStarted,
        MiseActionProgressEventType.output,
        MiseActionProgressEventType.commandFinished,
      ]),
    );
    expect(events.first.commandIndex, 1);
    expect(events.first.totalCommands, 2);
    expect(
      events.where((event) => event.output == 'installing sdk\n'),
      hasLength(2),
    );
  });

  test('cleans lockfiles created during a failed install action', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mise-action-lock-cleanup-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });
    final lockfilesDirectory = Directory(
      '${tempDirectory.path}/mise/lockfiles',
    );
    await lockfilesDirectory.create(recursive: true);

    final oldLockfile = File('${lockfilesDirectory.path}/old-lock');
    await oldLockfile.writeAsString('existing');

    final newLockfile = File('${lockfilesDirectory.path}/new-lock');
    final processService = _FakeProcessService((request) async {
      await newLockfile.writeAsString('stale');
      return MiseCommandResult(
        request: request,
        stdout: '',
        stderr: 'install failed',
        exitCode: 1,
        duration: const Duration(milliseconds: 12),
      );
    });
    final service = LocalMiseActionService(
      processService,
      lockfileCleaner: MiseLockfileCleaner(
        lockfileDirectories: [lockfilesDirectory.path],
      ),
    );

    final result = await service.runScript('mise install flutter@3.41.4');

    expect(result.isSuccess, isFalse);
    expect(await oldLockfile.exists(), isTrue);
    expect(await newLockfile.exists(), isFalse);
    expect(result.lockfileCleanupReport.removedPaths, [newLockfile.path]);
    expect(result.lockfileCleanupReport.detail, contains('已自动清理 1 个'));
  });

  test('cleans explicit waiting-for-lock path from command output', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'mise-action-waiting-lock-',
    );
    addTearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    final lockfilesDirectory = Directory(
      '${tempDirectory.path}/Library/Caches/mise/lockfiles',
    );
    await lockfilesDirectory.create(recursive: true);
    final staleLockfile = File('${lockfilesDirectory.path}/41d246818771175c');
    await staleLockfile.writeAsString('stale');

    final processService = _FakeProcessService((request) async {
      return MiseCommandResult(
        request: request,
        stdout: '',
        stderr:
            'DEBUG waiting for lock on ${staleLockfile.path}\n'
            'install failed',
        exitCode: 1,
        duration: const Duration(milliseconds: 12),
      );
    });
    final service = LocalMiseActionService(
      processService,
      lockfileCleaner: MiseLockfileCleaner(
        lockfileDirectories: [lockfilesDirectory.path],
      ),
    );

    final result = await service.runScript('mise use --global flutter@3.41.4');

    expect(result.isSuccess, isFalse);
    expect(await staleLockfile.exists(), isFalse);
    expect(result.lockfileCleanupReport.removedPaths, [staleLockfile.path]);
  });
}
