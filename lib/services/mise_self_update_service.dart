import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mise_gui/services/app_update_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';

const _miseGitHubApiBase = 'https://api.github.com/repos/jdx/mise';

class MiseSelfUpdateInfo {
  const MiseSelfUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseUrl,
    required this.updateAvailable,
    required MiseUpgradeCommand upgradeCommand,
  }) : _upgradeCommand = upgradeCommand;

  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseUrl;
  final bool updateAvailable;
  final MiseUpgradeCommand _upgradeCommand;

  String get commandPreview => _upgradeCommand.displayCommand;
  String get installSourceLabel => _upgradeCommand.installSourceLabel;
  bool get usesPackageManager => _upgradeCommand.usesPackageManager;
}

class MiseSelfUpdateResult {
  const MiseSelfUpdateResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;

  bool get isSuccess => exitCode == 0;

  String? get stdoutSnippet => _snippet(stdout);
  String? get stderrSnippet => _snippet(stderr);

  static String? _snippet(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.split('\n').take(3).join('\n');
  }
}

class MiseSystemCommandResult {
  const MiseSystemCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;

  bool get isSuccess => exitCode == 0;
}

abstract class MiseSystemCommandRunner {
  Future<String?> findExecutable(List<String> candidates);

  Future<String?> resolvePath(String path);

  Future<MiseSystemCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    void Function(MiseCommandOutputChunk chunk)? onOutput,
  });
}

class LocalMiseSystemCommandRunner implements MiseSystemCommandRunner {
  const LocalMiseSystemCommandRunner();

  @override
  Future<String?> findExecutable(List<String> candidates) async {
    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) {
        continue;
      }
      if (_isPathLike(candidate)) {
        final file = File(candidate);
        if (await file.exists()) {
          return file.resolveSymbolicLinks();
        }
        continue;
      }

      final resolved = await _findOnPath(candidate);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  @override
  Future<String?> resolvePath(String path) async {
    if (path.trim().isEmpty) {
      return null;
    }

    final file = File(path);
    if (await file.exists()) {
      return file.resolveSymbolicLinks();
    }

    final directory = Directory(path);
    if (await directory.exists()) {
      return directory.resolveSymbolicLinks();
    }

    return null;
  }

  @override
  Future<MiseSystemCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(minutes: 5),
    void Function(MiseCommandOutputChunk chunk)? onOutput,
  }) async {
    final stopwatch = Stopwatch()..start();
    Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: _systemEnvironment(),
        includeParentEnvironment: true,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      stopwatch.stop();
      return MiseSystemCommandResult(
        stdout: '',
        stderr: error.toString(),
        exitCode: error.errorCode,
        duration: stopwatch.elapsed,
      );
    }

    final stdoutCollector = MiseProcessOutputCollector(
      source: MiseCommandOutputSource.stdout,
      onOutput: onOutput,
    );
    final stderrCollector = MiseProcessOutputCollector(
      source: MiseCommandOutputSource.stderr,
      onOutput: onOutput,
    );
    final stdoutFuture = process.stdout
        .listen(stdoutCollector.add)
        .asFuture<void>();
    final stderrFuture = process.stderr
        .listen(stderrCollector.add)
        .asFuture<void>();

    int exitCode;
    var timedOut = false;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      exitCode = -1;
    }

    await stdoutFuture;
    await stderrFuture;
    stopwatch.stop();

    final stderr = stderrCollector.toText();
    return MiseSystemCommandResult(
      stdout: stdoutCollector.toText(),
      stderr: timedOut
          ? [
              stderr.trim(),
              'command timed out after ${timeout.inSeconds}s and was terminated.',
            ].where((item) => item.isNotEmpty).join('\n')
          : stderr,
      exitCode: exitCode,
      duration: stopwatch.elapsed,
    );
  }

  Future<String?> _findOnPath(String executable) async {
    final result = Platform.isWindows
        ? await Process.run('where', [executable])
        : await Process.run('/bin/sh', ['-lc', 'command -v $executable']);
    if (result.exitCode != 0) {
      return null;
    }
    final path = result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (path.isEmpty) {
      return null;
    }
    return await resolvePath(path) ?? path;
  }

  bool _isPathLike(String value) =>
      value.contains('/') ||
      value.contains(r'\') ||
      value.startsWith('.') ||
      value.startsWith('~');

  Map<String, String> _systemEnvironment() {
    final environment = <String, String>{...Platform.environment};
    final pathEntries = <String>[];

    void addPathEntries(String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      for (final entry in value.split(Platform.pathSeparator)) {
        if (entry.isEmpty || pathEntries.contains(entry)) {
          continue;
        }
        pathEntries.add(entry);
      }
    }

    addPathEntries(Platform.environment['PATH']);
    if (!Platform.isWindows) {
      addPathEntries('/opt/homebrew/bin:/opt/homebrew/sbin');
      addPathEntries('/usr/local/bin:/usr/local/sbin');
      addPathEntries('/home/linuxbrew/.linuxbrew/bin');
      addPathEntries('/usr/bin:/bin:/usr/sbin:/sbin');
    }
    environment.addAll(readConfiguredMiseProxyEnvironmentSync());
    environment['PATH'] = pathEntries.join(Platform.pathSeparator);
    return environment;
  }
}

abstract class MiseSelfUpdateService {
  Future<MiseSelfUpdateInfo> checkForUpdate();

  Future<MiseSelfUpdateResult> selfUpdate({
    MiseSelfUpdateInfo? info,
    void Function(MiseCommandOutputChunk chunk)? onOutput,
  });
}

class GitHubMiseSelfUpdateService implements MiseSelfUpdateService {
  const GitHubMiseSelfUpdateService({
    required MiseProcessService processService,
    MiseSystemCommandRunner systemRunner = const LocalMiseSystemCommandRunner(),
  }) : _processService = processService,
       _systemRunner = systemRunner;

  final MiseProcessService _processService;
  final MiseSystemCommandRunner _systemRunner;

  @override
  Future<MiseSelfUpdateInfo> checkForUpdate() async {
    final currentVersion = await _loadCurrentVersion();
    final release = await _loadLatestRelease();
    final latestVersion = normalizeReleaseVersion(release.tagName);
    final upgradeCommand = await _detectUpgradeCommand();

    return MiseSelfUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tagName: release.tagName,
      releaseUrl: release.releaseUrl,
      updateAvailable:
          compareReleaseVersions(latestVersion, currentVersion) > 0,
      upgradeCommand: upgradeCommand,
    );
  }

  @override
  Future<MiseSelfUpdateResult> selfUpdate({
    MiseSelfUpdateInfo? info,
    void Function(MiseCommandOutputChunk chunk)? onOutput,
  }) async {
    final command = info?._upgradeCommand ?? await _detectUpgradeCommand();
    if (command.useMiseProcessService) {
      final result = await _processService.run(
        MiseCommandRequest(
          arguments: command.arguments,
          timeout: const Duration(minutes: 5),
          allowNonZeroExit: true,
          preferShellExecution: true,
          onOutput: onOutput,
        ),
      );

      return MiseSelfUpdateResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        duration: result.duration,
      );
    }

    final result = await _systemRunner.run(
      command.executable,
      command.arguments,
      timeout: const Duration(minutes: 10),
      onOutput: onOutput,
    );
    return MiseSelfUpdateResult(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      duration: result.duration,
    );
  }

  Future<String> _loadCurrentVersion() async {
    final result = await _processService.run(
      const MiseCommandRequest(
        arguments: ['--version'],
        timeout: Duration(seconds: 5),
      ),
    );
    final firstLine = result.stdout
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final match = RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(firstLine);
    return match?.group(1) ?? firstLine;
  }

  Future<_MiseReleaseRef> _loadLatestRelease() async {
    final releaseJson = await _getJsonMap(
      '$_miseGitHubApiBase/releases/latest',
    );
    final tagName = releaseJson['tag_name']?.toString().trim();
    final releaseUrl = releaseJson['html_url']?.toString().trim();
    if (tagName == null || tagName.isEmpty) {
      throw const FormatException('Missing mise release tag_name');
    }
    return _MiseReleaseRef(
      tagName: tagName,
      releaseUrl: releaseUrl == null || releaseUrl.isEmpty
          ? 'https://github.com/jdx/mise/releases/tag/$tagName'
          : releaseUrl,
    );
  }

  Future<Map<String, dynamic>> _getJsonMap(String rawUrl) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    configureHttpClientProxy(client);

    try {
      final request = await client.getUrl(Uri.parse(rawUrl));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'mise_gui-mise-update-checker',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Unexpected response ${response.statusCode} for $rawUrl',
          uri: Uri.parse(rawUrl),
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Expected GitHub API object response');
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } finally {
      client.close(force: true);
    }
  }

  Future<MiseUpgradeCommand> _detectUpgradeCommand() async {
    final executablePath = await _resolveMiseExecutablePath();
    final homebrewCommand = await _detectHomebrewCommand(executablePath);
    if (homebrewCommand != null) {
      return homebrewCommand;
    }

    if (Platform.isWindows) {
      final scoopCommand = await _detectScoopCommand(executablePath);
      if (scoopCommand != null) {
        return scoopCommand;
      }

      final wingetCommand = await _detectWingetCommand(executablePath);
      if (wingetCommand != null) {
        return wingetCommand;
      }
    }

    return const MiseUpgradeCommand.selfUpdate();
  }

  Future<String?> _resolveMiseExecutablePath() async {
    try {
      final path = await _processService.resolveExecutablePath();
      final resolvedPath = await _systemRunner.resolvePath(path);
      return resolvedPath ?? path;
    } catch (_) {
      return null;
    }
  }

  Future<MiseUpgradeCommand?> _detectHomebrewCommand(
    String? executablePath,
  ) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return null;
    }

    final brew = await _systemRunner.findExecutable(const [
      '/opt/homebrew/bin/brew',
      '/usr/local/bin/brew',
      '/home/linuxbrew/.linuxbrew/bin/brew',
      'brew',
    ]);
    if (brew == null) {
      return null;
    }

    final prefixResult = await _systemRunner.run(brew, const [
      '--prefix',
      'mise',
    ], timeout: const Duration(seconds: 5));
    if (!prefixResult.isSuccess) {
      return null;
    }

    final prefix = prefixResult.stdout
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (prefix.isEmpty) {
      return null;
    }

    final resolvedPrefix = await _systemRunner.resolvePath(prefix) ?? prefix;
    final activePath = executablePath ?? '';
    final activeLooksHomebrew =
        activePath.contains('/Cellar/mise/') ||
        activePath.contains('/homebrew/');
    if (activePath.isNotEmpty &&
        !_pathIsInside(activePath, resolvedPrefix) &&
        !activeLooksHomebrew) {
      return null;
    }

    return MiseUpgradeCommand.packageManager(
      executable: brew,
      arguments: const ['upgrade', 'mise'],
      displayCommand: 'brew upgrade mise',
      installSourceLabel: 'Homebrew',
    );
  }

  Future<MiseUpgradeCommand?> _detectScoopCommand(
    String? executablePath,
  ) async {
    final scoop = await _systemRunner.findExecutable(const [
      'scoop',
      'scoop.cmd',
    ]);
    if (scoop == null) {
      return null;
    }

    final activePath = executablePath ?? '';
    final whichResult = await _systemRunner.run(scoop, const [
      'which',
      'mise',
    ], timeout: const Duration(seconds: 5));
    final scoopPath = whichResult.stdout
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final resolvedScoopPath = scoopPath.isEmpty
        ? null
        : await _systemRunner.resolvePath(scoopPath) ?? scoopPath;
    final activeLooksScoop = _normalizePath(
      activePath,
    ).contains('/scoop/apps/mise/');
    if (resolvedScoopPath != null &&
        activePath.isNotEmpty &&
        !_samePath(activePath, resolvedScoopPath) &&
        !activeLooksScoop) {
      return null;
    }

    if (resolvedScoopPath == null && !activeLooksScoop) {
      final listResult = await _systemRunner.run(scoop, const [
        'list',
        'mise',
      ], timeout: const Duration(seconds: 5));
      if (!listResult.isSuccess) {
        return null;
      }
    }

    return MiseUpgradeCommand.packageManager(
      executable: scoop,
      arguments: const ['update', 'mise'],
      displayCommand: 'scoop update mise',
      installSourceLabel: 'Scoop',
    );
  }

  Future<MiseUpgradeCommand?> _detectWingetCommand(
    String? executablePath,
  ) async {
    final winget = await _systemRunner.findExecutable(const ['winget']);
    if (winget == null) {
      return null;
    }

    final listResult = await _systemRunner.run(winget, const [
      'list',
      '--id',
      'jdx.mise',
      '--exact',
    ], timeout: const Duration(seconds: 10));
    if (!listResult.isSuccess) {
      return null;
    }

    final activePath = executablePath ?? '';
    final normalizedActivePath = _normalizePath(activePath);
    final activeIsConcretePath =
        normalizedActivePath.contains('/') ||
        normalizedActivePath.contains(':');
    final activeLooksWinget =
        normalizedActivePath.contains('/winget/') ||
        normalizedActivePath.contains('/microsoft/winget/') ||
        normalizedActivePath.contains('jdx.mise');
    if (activeIsConcretePath && !activeLooksWinget) {
      return null;
    }

    return MiseUpgradeCommand.packageManager(
      executable: winget,
      arguments: const [
        'upgrade',
        '--id',
        'jdx.mise',
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements',
      ],
      displayCommand: 'winget upgrade jdx.mise',
      installSourceLabel: 'winget',
    );
  }

  bool _pathIsInside(String path, String parent) {
    final normalizedPath = _normalizePath(path);
    final normalizedParent = _normalizePath(parent);
    return normalizedPath == normalizedParent ||
        normalizedPath.startsWith('$normalizedParent/');
  }

  bool _samePath(String left, String right) =>
      _normalizePath(left) == _normalizePath(right);

  String _normalizePath(String path) => path
      .trim()
      .replaceAll(r'\', '/')
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();
}

class MiseUpgradeCommand {
  const MiseUpgradeCommand.selfUpdate()
    : executable = 'mise',
      arguments = const ['self-update', '--yes'],
      displayCommand = 'mise self-update --yes',
      installSourceLabel = '直接安装',
      usesPackageManager = false,
      useMiseProcessService = true;

  const MiseUpgradeCommand.packageManager({
    required this.executable,
    required this.arguments,
    required this.displayCommand,
    required this.installSourceLabel,
  }) : usesPackageManager = true,
       useMiseProcessService = false;

  final String executable;
  final List<String> arguments;
  final String displayCommand;
  final String installSourceLabel;
  final bool usesPackageManager;
  final bool useMiseProcessService;
}

class _MiseReleaseRef {
  const _MiseReleaseRef({required this.tagName, required this.releaseUrl});

  final String tagName;
  final String releaseUrl;
}
