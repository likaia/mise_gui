import 'dart:convert';
import 'dart:io';

import 'package:mise_gui/services/mise_process_service.dart';

class MiseLockfileSnapshot {
  const MiseLockfileSnapshot({required this.modifiedAtByPath});

  final Map<String, DateTime> modifiedAtByPath;
}

class MiseLockfileCleanupReport {
  const MiseLockfileCleanupReport({
    this.removedPaths = const [],
    this.failedPaths = const [],
    this.detectedPaths = const [],
  });

  final List<String> removedPaths;
  final List<String> failedPaths;
  final List<String> detectedPaths;

  bool get hasFindings =>
      removedPaths.isNotEmpty ||
      failedPaths.isNotEmpty ||
      detectedPaths.isNotEmpty;

  String? get detail {
    if (!hasFindings) {
      return null;
    }

    final parts = <String>[];
    if (removedPaths.isNotEmpty) {
      parts.add('已自动清理 ${removedPaths.length} 个可能残留的 mise 锁文件。');
      parts.addAll(removedPaths.map((path) => '已清理: $path'));
    }
    if (failedPaths.isNotEmpty) {
      parts.add('有 ${failedPaths.length} 个锁文件未能自动删除，可以确认没有其他 mise 进程后手动删除。');
      parts.addAll(
        failedPaths.map((path) => '需手动处理: rm -f ${_shellEscape(path)}'),
      );
    }
    if (detectedPaths.isNotEmpty) {
      parts.addAll(detectedPaths.map((path) => '检测到锁路径: $path'));
    }
    return parts.join('\n');
  }

  static String _shellEscape(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }
}

class MiseLockfileCleaner {
  const MiseLockfileCleaner({List<String>? lockfileDirectories})
    : _lockfileDirectories = lockfileDirectories;

  final List<String>? _lockfileDirectories;

  Future<MiseLockfileSnapshot> capture() async {
    final modifiedAtByPath = <String, DateTime>{};
    for (final directoryPath in _resolvedLockfileDirectories()) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        continue;
      }

      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File) {
            continue;
          }
          final stat = await entity.stat();
          modifiedAtByPath[entity.path] = stat.modified;
        }
      } on FileSystemException {
        continue;
      }
    }
    return MiseLockfileSnapshot(modifiedAtByPath: modifiedAtByPath);
  }

  Future<MiseLockfileCleanupReport> cleanupAfterFailedAction({
    required MiseLockfileSnapshot snapshot,
    required String output,
  }) async {
    final candidates = <String>{
      ..._extractLockfilePaths(output),
      ...await _findNewOrChangedLockfiles(snapshot),
    };
    if (candidates.isEmpty) {
      return const MiseLockfileCleanupReport();
    }

    final removedPaths = <String>[];
    final failedPaths = <String>[];
    final detectedPaths = <String>[];

    for (final path in candidates) {
      if (!_isSafeLockfilePath(path)) {
        detectedPaths.add(path);
        continue;
      }

      final file = File(path);
      if (!await file.exists()) {
        detectedPaths.add(path);
        continue;
      }

      try {
        await file.delete();
        removedPaths.add(path);
      } on FileSystemException {
        failedPaths.add(path);
      }
    }

    return MiseLockfileCleanupReport(
      removedPaths: removedPaths,
      failedPaths: failedPaths,
      detectedPaths: detectedPaths,
    );
  }

  Future<List<String>> _findNewOrChangedLockfiles(
    MiseLockfileSnapshot snapshot,
  ) async {
    final paths = <String>[];
    for (final directoryPath in _resolvedLockfileDirectories()) {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        continue;
      }

      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File) {
            continue;
          }

          final stat = await entity.stat();
          final previousModifiedAt = snapshot.modifiedAtByPath[entity.path];
          if (previousModifiedAt == null ||
              stat.modified.isAfter(previousModifiedAt)) {
            paths.add(entity.path);
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    return paths;
  }

  Set<String> _extractLockfilePaths(String output) {
    final paths = <String>{};
    final matcher = RegExp(
      r'(?:^|\s)(~?[^\s`"]*[/\\]mise[/\\]lockfiles[/\\][A-Za-z0-9._-]+)',
      caseSensitive: false,
    );

    for (final match in matcher.allMatches(output)) {
      final rawPath = match.group(1)?.trim();
      if (rawPath == null || rawPath.isEmpty) {
        continue;
      }
      paths.add(_expandHome(rawPath));
    }

    return paths;
  }

  List<String> _resolvedLockfileDirectories() {
    if (_lockfileDirectories != null) {
      return _lockfileDirectories;
    }

    final environment = Platform.environment;
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    final cacheHome = environment['XDG_CACHE_HOME'];
    final localAppData = environment['LOCALAPPDATA'];

    return <String>[
      if (environment['MISE_CACHE_DIR'] case final miseCacheDir?)
        _joinPath(miseCacheDir, 'lockfiles'),
      if (home != null && home.isNotEmpty && Platform.isMacOS)
        '$home/Library/Caches/mise/lockfiles',
      if (cacheHome != null && cacheHome.isNotEmpty)
        '$cacheHome/mise/lockfiles',
      if (home != null && home.isNotEmpty) '$home/.cache/mise/lockfiles',
      if (localAppData != null && localAppData.isNotEmpty)
        '$localAppData\\mise\\lockfiles',
    ];
  }

  String _joinPath(String parent, String child) {
    final separator = Platform.isWindows ? '\\' : '/';
    if (parent.endsWith('/') || parent.endsWith('\\')) {
      return '$parent$child';
    }
    return '$parent$separator$child';
  }

  String _expandHome(String path) {
    if (!path.startsWith('~/')) {
      return path;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return path;
    }
    return '$home/${path.substring(2)}';
  }

  bool _isSafeLockfilePath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/mise/lockfiles/') &&
        !normalized.endsWith('/mise/lockfiles/') &&
        !normalized.contains('/../');
  }
}

class ExecutedMiseCommand {
  const ExecutedMiseCommand({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
}

class MiseActionResult {
  const MiseActionResult({
    required this.script,
    required this.commands,
    this.lockfileCleanupReport = const MiseLockfileCleanupReport(),
  });

  final String script;
  final List<ExecutedMiseCommand> commands;
  final MiseLockfileCleanupReport lockfileCleanupReport;

  bool get isSuccess =>
      commands.isNotEmpty && commands.every((item) => item.exitCode == 0);

  int get exitCode => commands.isEmpty ? -1 : commands.last.exitCode;

  Duration get duration =>
      commands.fold(Duration.zero, (total, item) => total + item.duration);

  String get stdout => commands
      .where((item) => item.stdout.trim().isNotEmpty)
      .map((item) => '\$ ${item.command}\n${item.stdout.trim()}')
      .join('\n\n');

  String get stderr => commands
      .where((item) => item.stderr.trim().isNotEmpty)
      .map((item) => '\$ ${item.command}\n${item.stderr.trim()}')
      .join('\n\n');

  String? get stdoutSnippet {
    for (final command in commands.reversed) {
      final trimmed = command.stdout.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.split('\n').take(3).join('\n');
      }
    }
    return null;
  }

  String? get stderrSnippet {
    for (final command in commands.reversed) {
      final trimmed = command.stderr.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.split('\n').take(3).join('\n');
      }
    }
    return null;
  }
}

abstract class MiseActionService {
  Future<MiseActionResult> runScript(String script, {String? workingDirectory});
}

class LocalMiseActionService implements MiseActionService {
  const LocalMiseActionService(
    this._processService, {
    MiseLockfileCleaner lockfileCleaner = const MiseLockfileCleaner(),
  }) : _lockfileCleaner = lockfileCleaner;

  final MiseProcessService _processService;
  final MiseLockfileCleaner _lockfileCleaner;

  @override
  Future<MiseActionResult> runScript(
    String script, {
    String? workingDirectory,
  }) async {
    final commands = <ExecutedMiseCommand>[];
    final lockfileSnapshot = await _lockfileCleaner.capture();
    var lockfileCleanupReport = const MiseLockfileCleanupReport();

    for (final rawLine in const LineSplitter().convert(script)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (!line.startsWith('mise ')) {
        throw UnsupportedError(
          'Only mise CLI commands can be executed from GUI actions.',
        );
      }

      final arguments = _parseArguments(line.substring(5));
      final result = await _processService.run(
        MiseCommandRequest(
          arguments: arguments,
          workingDirectory: workingDirectory,
          allowNonZeroExit: true,
          preferShellExecution: true,
          timeout: const Duration(minutes: 6),
        ),
      );

      commands.add(
        ExecutedMiseCommand(
          command: line,
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
          duration: result.duration,
        ),
      );

      if (result.exitCode != 0) {
        lockfileCleanupReport = await _lockfileCleaner.cleanupAfterFailedAction(
          snapshot: lockfileSnapshot,
          output: '${result.stdout}\n${result.stderr}',
        );
        break;
      }
    }

    return MiseActionResult(
      script: script,
      commands: commands,
      lockfileCleanupReport: lockfileCleanupReport,
    );
  }

  List<String> _parseArguments(String input) {
    final matches = RegExp(
      r'''[^\s"']+|"([^"]*)"|'([^']*)' ''',
    ).allMatches('$input ').toList();
    if (matches.isEmpty) {
      return const <String>[];
    }

    return matches.map((match) {
      final full = match.group(0)!.trimRight();
      if (full.startsWith('"') && full.endsWith('"')) {
        return full.substring(1, full.length - 1);
      }
      if (full.startsWith("'") && full.endsWith("'")) {
        return full.substring(1, full.length - 1);
      }
      return full;
    }).toList();
  }
}
