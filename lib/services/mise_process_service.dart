import 'dart:async';
import 'dart:io';

const String _shellEnvironmentStartMarker =
    '__MISE_GUI_SHELL_ENVIRONMENT_START__';
const String _shellEnvironmentEndMarker = '__MISE_GUI_SHELL_ENVIRONMENT_END__';
final RegExp _environmentKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

class MiseCommandRequest {
  const MiseCommandRequest({
    required this.arguments,
    this.workingDirectory,
    this.timeout = const Duration(seconds: 30),
    this.allowNonZeroExit = false,
    this.preferShellExecution = false,
    this.onOutput,
  });

  final List<String> arguments;
  final String? workingDirectory;
  final Duration timeout;
  final bool allowNonZeroExit;
  final bool preferShellExecution;
  final void Function(MiseCommandOutputChunk chunk)? onOutput;

  String get displayCommand => ['mise', ...arguments].join(' ');
}

enum MiseCommandOutputSource { stdout, stderr }

class MiseCommandOutputChunk {
  const MiseCommandOutputChunk({required this.source, required this.text});

  final MiseCommandOutputSource source;
  final String text;
}

class MiseCommandResult {
  const MiseCommandResult({
    required this.request,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final MiseCommandRequest request;
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;

  bool get isSuccess => exitCode == 0;
}

class MiseProcessException implements Exception {
  const MiseProcessException({required this.message, required this.result});

  final String message;
  final MiseCommandResult result;

  @override
  String toString() =>
      '$message\n${result.request.displayCommand}\n${result.stderr}';
}

class MiseFailureDiagnosis {
  const MiseFailureDiagnosis({required this.summary, required this.detail});

  final String summary;
  final String detail;
}

enum ShellEnvironmentSource { shell, desktopFallback, unsupported }

class ShellEnvironmentLoadResult {
  const ShellEnvironmentLoadResult({
    required this.source,
    this.environment,
    this.detail,
  });

  final ShellEnvironmentSource source;
  final Map<String, String>? environment;
  final String? detail;

  bool get isFromShell => source == ShellEnvironmentSource.shell;
}

enum WindowsShimPathSource { present, missing, unsupported }

class WindowsShimPathStatus {
  const WindowsShimPathStatus({
    required this.source,
    this.shimPath,
    this.detail,
    this.commandPreview,
  });

  final WindowsShimPathSource source;
  final String? shimPath;
  final String? detail;
  final String? commandPreview;

  bool get isMissing => source == WindowsShimPathSource.missing;
}

bool isMiseCommandUnavailable(Object error) {
  if (error is! MiseProcessException) {
    return false;
  }

  final stderr = error.result.stderr.toLowerCase();
  final message = error.message.toLowerCase();

  return message.contains('unable to launch mise cli') ||
      stderr.contains('no such file or directory') ||
      stderr.contains('cannot find the file specified') ||
      stderr.contains('failed to execvp') ||
      stderr.contains('failed to start') ||
      stderr.contains('not found');
}

String recommendedMiseInstallCommand() {
  if (Platform.isMacOS) {
    return 'brew install mise';
  }
  if (Platform.isWindows) {
    return 'winget install jdx.mise';
  }
  return 'curl https://mise.run | sh';
}

MiseFailureDiagnosis? diagnoseMiseCommandFailure({
  required String command,
  String? stdout,
  String? stderr,
}) {
  final combined = [
    stdout ?? '',
    stderr ?? '',
  ].where((item) => item.trim().isNotEmpty).join('\n').toLowerCase();

  if (combined.isEmpty) {
    return null;
  }

  if (combined.contains('make: command not found')) {
    return MiseFailureDiagnosis(
      summary: '缺少 make，当前机器还不具备源码编译依赖。',
      detail:
          '$command 执行失败。错误输出显示系统找不到 `make`，这类像 Redis 一样需要本地编译的工具通常还依赖 Xcode Command Line Tools。'
          ' 先执行 `xcode-select --install`，再用 `make --version` 和 `clang --version` 确认命令可用，然后重试。'
          ' 已保留实际 CLI 和原始错误输出。',
    );
  }

  if (combined.contains('c compiler') ||
      combined.contains('clang: command not found') ||
      combined.contains('gcc: command not found') ||
      combined.contains('no acceptable c compiler found')) {
    return MiseFailureDiagnosis(
      summary: '缺少 C 编译工具链，当前机器无法完成源码构建。',
      detail:
          '$command 执行失败。错误输出显示系统缺少可用的 C 编译器。'
          ' 在 macOS 上先安装 Xcode Command Line Tools：`xcode-select --install`，然后确认 `clang --version`、`make --version` 可运行后再重试。'
          ' 已保留实际 CLI 和原始错误输出。',
    );
  }

  return null;
}

abstract class MiseProcessService {
  Future<MiseCommandResult> run(MiseCommandRequest request);
  Future<String> resolveExecutablePath();
  Future<ShellEnvironmentLoadResult> inspectShellEnvironment();
  Future<WindowsShimPathStatus> inspectWindowsShimPath();
}

class LocalMiseProcessService implements MiseProcessService {
  const LocalMiseProcessService({this.executablePath});

  final String? executablePath;
  static const List<String> _fallbackExecutablePaths = <String>[
    '/opt/homebrew/bin/mise',
    '/usr/local/bin/mise',
  ];

  @override
  Future<String> resolveExecutablePath() => _resolveExecutablePath();

  @override
  Future<MiseCommandResult> run(MiseCommandRequest request) async {
    final stopwatch = Stopwatch()..start();
    final resolvedExecutablePath = await _resolveExecutablePath();
    final environment = await _buildEnvironment();

    ProcessResult processResult;

    try {
      processResult = await _runProcess(
        request: request,
        executablePath: resolvedExecutablePath,
        environment: environment,
      );
    } on ProcessException catch (error) {
      stopwatch.stop();

      throw MiseProcessException(
        message: 'Unable to launch mise CLI from the desktop app',
        result: MiseCommandResult(
          request: request,
          stdout: '',
          stderr: _formatProcessException(
            executablePath: resolvedExecutablePath,
            environmentPath: environment['PATH'],
            error: error,
          ),
          exitCode: error.errorCode,
          duration: stopwatch.elapsed,
        ),
      );
    }

    stopwatch.stop();

    final result = MiseCommandResult(
      request: request,
      stdout: (processResult.stdout ?? '').toString(),
      stderr: (processResult.stderr ?? '').toString(),
      exitCode: processResult.exitCode,
      duration: stopwatch.elapsed,
    );

    if (!result.isSuccess && !request.allowNonZeroExit) {
      throw MiseProcessException(
        message: 'mise command failed with exit code ${result.exitCode}',
        result: result,
      );
    }

    return result;
  }

  @override
  Future<ShellEnvironmentLoadResult> inspectShellEnvironment() {
    return _loadShellEnvironment();
  }

  @override
  Future<WindowsShimPathStatus> inspectWindowsShimPath() async {
    if (!Platform.isWindows) {
      return const WindowsShimPathStatus(
        source: WindowsShimPathSource.unsupported,
      );
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      return const WindowsShimPathStatus(
        source: WindowsShimPathSource.missing,
        detail: '当前还没法确认 Windows 终端是否已经接入 mise。可以先查看修复命令，按提示补齐后再重开终端。',
      );
    }

    final shimPath = '$localAppData\\mise\\shims';
    final path = Platform.environment['PATH'] ?? '';
    final pathEntries = path
        .split(';')
        .map(_normalizeWindowsPathEntry)
        .where((entry) => entry.isNotEmpty)
        .toSet();

    if (pathEntries.contains(_normalizeWindowsPathEntry(shimPath))) {
      return WindowsShimPathStatus(
        source: WindowsShimPathSource.present,
        shimPath: shimPath,
      );
    }

    return WindowsShimPathStatus(
      source: WindowsShimPathSource.missing,
      shimPath: shimPath,
      detail:
          '检测到 Windows 终端还没有接入 mise shims。应用已经识别到该工具由 mise 管理，但新的 cmd / PowerShell 会话里还不能直接调用。'
          ' 执行下面的命令后，重新打开终端即可生效。',
      commandPreview: _windowsShimPathFixCommand(shimPath),
    );
  }

  Future<ProcessResult> _runProcess({
    required MiseCommandRequest request,
    required String executablePath,
    required Map<String, String> environment,
  }) async {
    if (!request.preferShellExecution || Platform.isWindows) {
      return _runProcessWithTimeout(
        executablePath,
        request.arguments,
        workingDirectory: request.workingDirectory,
        environment: environment,
        timeout: request.timeout,
        onOutput: request.onOutput,
      );
    }

    final shellPath = _shellPath(
      configuredShell: environment['SHELL'] ?? Platform.environment['SHELL'],
    );
    final command =
        'exec ${<String>[executablePath, ...request.arguments].map(_shellEscape).join(' ')}';

    return _runProcessWithTimeout(
      shellPath,
      ['-ilc', command],
      workingDirectory: request.workingDirectory,
      environment: environment,
      timeout: request.timeout,
      onOutput: request.onOutput,
    );
  }

  Future<ProcessResult> _runProcessWithTimeout(
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    required void Function(MiseCommandOutputChunk chunk)? onOutput,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutFuture = process.stdout
        .transform(systemEncoding.decoder)
        .listen((chunk) {
          stdoutBuffer.write(chunk);
          onOutput?.call(
            MiseCommandOutputChunk(
              source: MiseCommandOutputSource.stdout,
              text: chunk,
            ),
          );
        })
        .asFuture<void>();
    final stderrFuture = process.stderr
        .transform(systemEncoding.decoder)
        .listen((chunk) {
          stderrBuffer.write(chunk);
          onOutput?.call(
            MiseCommandOutputChunk(
              source: MiseCommandOutputSource.stderr,
              text: chunk,
            ),
          );
        })
        .asFuture<void>();

    int exitCode;
    var timedOut = false;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        if (Platform.isWindows) {
          process.kill();
        } else {
          process.kill(ProcessSignal.sigkill);
        }
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          // The process has been signalled; return a timeout result so callers
          // can record failure and run recovery hooks.
        }
      }
      exitCode = -1;
    }

    await stdoutFuture;
    await stderrFuture;
    final stdout = stdoutBuffer.toString();
    final stderr = stderrBuffer.toString();
    if (!timedOut) {
      return ProcessResult(process.pid, exitCode, stdout, stderr);
    }

    final timeoutMessage =
        'mise command timed out after ${timeout.inSeconds}s and was terminated.';
    return ProcessResult(
      process.pid,
      exitCode,
      stdout,
      [
        stderr.trim(),
        timeoutMessage,
      ].where((item) => item.isNotEmpty).join('\n'),
    );
  }

  Future<String> _resolveExecutablePath() async {
    if (executablePath != null && executablePath!.isNotEmpty) {
      return executablePath!;
    }

    final shellEnvironmentResult = await _loadShellEnvironment();
    final shellEnvironment = shellEnvironmentResult.environment;
    final homeDirectory =
        shellEnvironment?['HOME'] ?? Platform.environment['HOME'];
    final homeCandidates = <String>[
      if (homeDirectory != null) ...<String>[
        '$homeDirectory/.local/bin/mise',
        '$homeDirectory/.cargo/bin/mise',
        '$homeDirectory/bin/mise',
        '$homeDirectory/.local/share/mise/bin/mise',
      ],
    ];

    final pathCandidates = <String>[
      ..._resolvePathCandidates(shellEnvironment?['PATH']),
      ..._resolvePathCandidates(Platform.environment['PATH']),
      ...homeCandidates,
      ..._fallbackExecutablePaths,
    ];

    for (final candidate in pathCandidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file.resolveSymbolicLinks();
      }
    }

    return executablePath ?? 'mise';
  }

  List<String> _resolvePathCandidates(String? rawPath) {
    if (rawPath == null || rawPath.isEmpty) {
      return const <String>[];
    }

    final seen = <String>{};
    final candidates = <String>[];
    for (final entry in rawPath.split(Platform.pathSeparator)) {
      if (entry.isEmpty) {
        continue;
      }
      final candidate = '$entry/mise';
      if (seen.add(candidate)) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  Future<Map<String, String>> _buildEnvironment() async {
    final parent = Platform.environment;
    final shellEnvironmentResult = await _loadShellEnvironment();
    final shellEnvironment = shellEnvironmentResult.environment;
    final mergedEnvironment = <String, String>{
      ...parent,
      if (shellEnvironment != null) ...shellEnvironment,
    };
    final environment = <String, String>{};
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

    for (final entry in mergedEnvironment.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      environment[entry.key] = entry.value;
    }

    addPathEntries(shellEnvironment?['PATH']);
    addPathEntries(parent['PATH']);
    addPathEntries('/opt/homebrew/bin:/opt/homebrew/sbin');
    addPathEntries('/usr/local/bin:/usr/local/sbin');
    addPathEntries('/usr/bin:/bin:/usr/sbin:/sbin');

    final homeDirectory = shellEnvironment?['HOME'] ?? parent['HOME'];
    if (homeDirectory != null && homeDirectory.isNotEmpty) {
      addPathEntries(
        '$homeDirectory/.local/bin:'
        '$homeDirectory/.cargo/bin:'
        '$homeDirectory/bin:'
        '$homeDirectory/.local/share/mise/bin',
      );
      environment['HOME'] = homeDirectory;
    }

    environment['PATH'] = pathEntries.join(Platform.pathSeparator);
    return environment;
  }

  Future<ShellEnvironmentLoadResult> _loadShellEnvironment() {
    if (Platform.isWindows) {
      return Future.value(
        const ShellEnvironmentLoadResult(
          source: ShellEnvironmentSource.unsupported,
        ),
      );
    }
    return _readShellEnvironment();
  }

  Future<ShellEnvironmentLoadResult> _readShellEnvironment() async {
    final parent = Platform.environment;
    final shellPath = _shellPath(configuredShell: parent['SHELL']);
    final command = [
      "printf '%s\\0' ${_shellEscape(_shellEnvironmentStartMarker)}",
      'env -0',
      r'status=$?',
      "printf '%s\\0' ${_shellEscape(_shellEnvironmentEndMarker)}",
      r'exit $status',
    ].join('; ');

    try {
      final result = await Process.run(
        shellPath,
        ['-ilc', command],
        includeParentEnvironment: true,
        runInShell: false,
      );

      if (result.exitCode != 0) {
        return const ShellEnvironmentLoadResult(
          source: ShellEnvironmentSource.desktopFallback,
          detail: '登录 shell 返回了非零退出码，已回退到桌面进程环境。',
        );
      }

      final rawOutput = (result.stdout ?? '').toString();
      if (rawOutput.isEmpty) {
        return const ShellEnvironmentLoadResult(
          source: ShellEnvironmentSource.desktopFallback,
          detail: '登录 shell 没有返回可解析的环境变量，已回退到桌面进程环境。',
        );
      }

      final environment = parseShellEnvironmentOutput(rawOutput);
      if (environment.isEmpty) {
        return const ShellEnvironmentLoadResult(
          source: ShellEnvironmentSource.desktopFallback,
          detail: '未能可靠解析 shell 输出，已回退到桌面进程环境。',
        );
      }

      return ShellEnvironmentLoadResult(
        source: ShellEnvironmentSource.shell,
        environment: environment,
      );
    } catch (_) {
      return const ShellEnvironmentLoadResult(
        source: ShellEnvironmentSource.desktopFallback,
        detail: '读取登录 shell 环境时发生异常，已回退到桌面进程环境。',
      );
    }
  }

  String _shellPath({String? configuredShell}) {
    if (configuredShell != null && configuredShell.isNotEmpty) {
      return configuredShell;
    }
    return Platform.isMacOS ? '/bin/zsh' : '/bin/bash';
  }

  String _shellEscape(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  String _formatProcessException({
    required String executablePath,
    required String? environmentPath,
    required ProcessException error,
  }) {
    final details = <String>[
      'Command: ${[executablePath, ...error.arguments].join(' ')}',
      if (error.message.isNotEmpty) error.message,
    ];

    final path = environmentPath ?? Platform.environment['PATH'];
    if (path != null && path.isNotEmpty) {
      details.add('PATH: $path');
    }

    return details.join('\n');
  }

  String _normalizeWindowsPathEntry(String value) {
    var normalized = value.trim().replaceAll('/', '\\');
    while (normalized.endsWith('\\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  String _windowsShimPathFixCommand(String shimPath) {
    final escapedShimPath = shimPath.replaceAll("'", "''");
    return r'''$shimDir = '''
        "'$escapedShimPath'"
        r'''
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if ($userPath) {
  $entries += $userPath -split ';'
}
if ($entries -notcontains $shimDir) {
  $entries += $shimDir
  [Environment]::SetEnvironmentVariable(
    'Path',
    (($entries | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique) -join ';'),
    'User'
  )
}
mise reshim
Write-Host '已写入用户 PATH，请关闭并重新打开 cmd / PowerShell 后再执行工具命令。'
''';
  }
}

Map<String, String> parseShellEnvironmentOutput(
  String rawOutput, {
  String startMarker = _shellEnvironmentStartMarker,
  String endMarker = _shellEnvironmentEndMarker,
}) {
  final payload = _extractDelimitedShellPayload(
    rawOutput,
    startMarker: startMarker,
    endMarker: endMarker,
  );
  if (payload.isEmpty) {
    return const <String, String>{};
  }

  final environment = <String, String>{};
  for (final entry in payload.split('\u0000')) {
    final separatorIndex = entry.indexOf('=');
    if (separatorIndex <= 0) {
      continue;
    }
    final key = entry.substring(0, separatorIndex);
    final value = entry.substring(separatorIndex + 1);
    if (!_environmentKeyPattern.hasMatch(key) || value.isEmpty) {
      continue;
    }
    environment[key] = value;
  }

  return environment;
}

String _extractDelimitedShellPayload(
  String rawOutput, {
  required String startMarker,
  required String endMarker,
}) {
  final startIndex = rawOutput.indexOf(startMarker);
  if (startIndex == -1) {
    return rawOutput;
  }

  var payloadStart = startIndex + startMarker.length;
  while (payloadStart < rawOutput.length &&
      rawOutput.codeUnitAt(payloadStart) == 0) {
    payloadStart++;
  }

  final endIndex = rawOutput.indexOf(endMarker, payloadStart);
  final payload = endIndex == -1
      ? rawOutput.substring(payloadStart)
      : rawOutput.substring(payloadStart, endIndex);

  return payload.replaceFirst(RegExp(r'\u0000+$'), '');
}
