import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mise_gui/models/app_models.dart';

class _RuntimeSettingDefinition {
  const _RuntimeSettingDefinition({
    required this.key,
    required this.label,
    required this.defaultValue,
    required this.detail,
    required this.type,
  });

  final String key;
  final String label;
  final String defaultValue;
  final String detail;
  final ConfigRuntimeSettingType type;
}

class _ProxySettingDefinition {
  const _ProxySettingDefinition({
    required this.key,
    required this.aliases,
    required this.label,
    required this.placeholder,
    required this.detail,
    this.requiresUri = true,
  });

  final String key;
  final List<String> aliases;
  final String label;
  final String placeholder;
  final String detail;
  final bool requiresUri;
}

abstract class ConfigService {
  Future<ConfigWorkspaceData> fetchWorkspace({
    String? projectPath,
    String? projectConfigPath,
    String? projectName,
    bool includeProjectConfig = true,
  });

  Future<ConfigSavePreview> previewDocumentSave({
    required ConfigDocumentData document,
    required String nextContent,
  });

  Future<ConfigSavePreview> previewRuntimeSettingsSave({
    required ConfigRuntimeSettingsUpdate update,
  });

  Future<ConfigSavePreview> previewProxySettingsSave({
    required ConfigProxySettingsUpdate update,
  });

  Future<void> saveDocument({
    required ConfigDocumentData document,
    required String nextContent,
  });
}

class LiveConfigService implements ConfigService {
  const LiveConfigService({String? globalConfigPath})
    : _globalConfigPathOverride = globalConfigPath;

  final String? _globalConfigPathOverride;

  static const List<_RuntimeSettingDefinition> _runtimeSettingDefinitions = [
    _RuntimeSettingDefinition(
      key: 'http_timeout',
      label: 'HTTP 超时',
      defaultValue: '30s',
      detail: '所有 HTTP 请求的超时时间。',
      type: ConfigRuntimeSettingType.string,
    ),
    _RuntimeSettingDefinition(
      key: 'fetch_remote_versions_timeout',
      label: '远端版本超时',
      defaultValue: '20s',
      detail: '获取远端工具版本列表时的超时时间。',
      type: ConfigRuntimeSettingType.string,
    ),
    _RuntimeSettingDefinition(
      key: 'http_retries',
      label: 'HTTP 重试',
      defaultValue: '3',
      detail: '网络临时失败时的重试次数，0 表示不重试。',
      type: ConfigRuntimeSettingType.integer,
    ),
    _RuntimeSettingDefinition(
      key: 'offline',
      label: '离线模式',
      defaultValue: 'false',
      detail: '开启后 mise 不会主动发起 HTTP 请求。',
      type: ConfigRuntimeSettingType.boolean,
    ),
    _RuntimeSettingDefinition(
      key: 'terminal_progress',
      label: '终端进度',
      defaultValue: 'true',
      detail: '控制 mise 是否输出终端进度指示。',
      type: ConfigRuntimeSettingType.boolean,
    ),
  ];

  static const List<_ProxySettingDefinition> _proxySettingDefinitions = [
    _ProxySettingDefinition(
      key: 'http_proxy',
      aliases: ['http_proxy', 'HTTP_PROXY'],
      label: 'HTTP 代理',
      placeholder: 'http://127.0.0.1:7890',
      detail: '用于 HTTP 下载请求，会同步写入 http_proxy 和 HTTP_PROXY。',
    ),
    _ProxySettingDefinition(
      key: 'https_proxy',
      aliases: ['https_proxy', 'HTTPS_PROXY'],
      label: 'HTTPS 代理',
      placeholder: 'http://127.0.0.1:7890',
      detail: '用于 HTTPS 下载请求，会同步写入 https_proxy 和 HTTPS_PROXY。',
    ),
    _ProxySettingDefinition(
      key: 'all_proxy',
      aliases: ['all_proxy', 'ALL_PROXY'],
      label: '通用代理',
      placeholder: 'socks5://127.0.0.1:7890',
      detail: '用于支持 ALL_PROXY 的下载器或工具链。',
    ),
    _ProxySettingDefinition(
      key: 'no_proxy',
      aliases: ['no_proxy', 'NO_PROXY'],
      label: '不代理清单',
      placeholder: 'localhost,127.0.0.1,*.local',
      detail: '逗号分隔的直连主机或域名，会同步写入 no_proxy 和 NO_PROXY。',
      requiresUri: false,
    ),
  ];

  @override
  Future<ConfigWorkspaceData> fetchWorkspace({
    String? projectPath,
    String? projectConfigPath,
    String? projectName,
    bool includeProjectConfig = true,
  }) async {
    try {
      final sections = <ConfigSectionData>[];
      final globalPath = _globalConfigPath();
      final resolvedProjectPath = includeProjectConfig
          ? (projectPath ?? _directoryPathFor(projectConfigPath))
          : null;
      final resolvedProjectConfigPath =
          includeProjectConfig &&
              (projectConfigPath != null ||
                  (resolvedProjectPath != null &&
                      resolvedProjectPath.isNotEmpty))
          ? (projectConfigPath ??
                _projectConfigPath(projectPath: resolvedProjectPath!))
          : null;
      final projectDocumentName = resolvedProjectConfigPath == null
          ? null
          : _fileNameForPath(resolvedProjectConfigPath);
      final projectDocumentTarget = projectName == null || projectName.isEmpty
          ? '当前配置项目'
          : projectName;

      final globalConfig = await _readFileIfExists(globalPath);
      final projectConfig = resolvedProjectConfigPath == null
          ? null
          : await _readFileIfExists(resolvedProjectConfigPath);
      final globalDocument = _buildDocument(
        id: 'global',
        title: '全局 TOML',
        path: globalPath,
        content: globalConfig,
        description: '查看或编辑 ~/.config/mise/config.toml，这里通常决定全局默认工具链和基础设置。',
      );
      final documents = <ConfigDocumentData>[globalDocument];
      if (resolvedProjectConfigPath != null && projectDocumentName != null) {
        documents.add(
          _buildDocument(
            id: 'workspace',
            title: '项目配置',
            path: resolvedProjectConfigPath,
            content: projectConfig,
            description:
                '查看或编辑$projectDocumentTarget下的 $projectDocumentName，这里的版本声明会覆盖全局默认值。',
          ),
        );
      }

      sections.add(
        _buildToolsSection(
          title: '全局工具',
          description: '这里展示全局 [tools] 段里声明的版本策略，是大多数项目默认继承的起点。',
          path: globalPath,
          content: globalConfig,
          sectionName: 'tools',
        ),
      );

      sections.add(
        _buildSettingsSection(
          title: '运行时设置',
          description: '把 settings、settings.java 和 env 里的常用参数整理成更易读的卡片。',
          path: globalPath,
          content: globalConfig,
        ),
      );

      sections.add(_buildAliasSection(path: globalPath, content: globalConfig));

      if (resolvedProjectConfigPath != null) {
        sections.add(
          _buildToolsSection(
            title: '项目工具',
            description: '只展示当前配置项目里的 [tools] 声明，帮助你一眼看出哪些版本是项目级锁定。',
            path: resolvedProjectConfigPath,
            content: projectConfig,
            sectionName: 'tools',
          ),
        );
      }

      return ConfigWorkspaceData(
        sections: sections,
        documents: documents,
        runtimeSettings: _buildRuntimeSettings(
          document: globalDocument,
          content: globalConfig,
        ),
        proxySettings: _buildProxySettings(
          document: globalDocument,
          content: globalConfig,
        ),
      );
    } catch (error) {
      final globalPath = _globalConfigPath();
      final resolvedProjectPath = includeProjectConfig
          ? (projectPath ?? _directoryPathFor(projectConfigPath))
          : null;
      final resolvedProjectConfigPath =
          includeProjectConfig &&
              (projectConfigPath != null ||
                  (resolvedProjectPath != null &&
                      resolvedProjectPath.isNotEmpty))
          ? (projectConfigPath ??
                _projectConfigPath(projectPath: resolvedProjectPath!))
          : null;
      final projectDocumentName = resolvedProjectConfigPath == null
          ? null
          : _fileNameForPath(resolvedProjectConfigPath);
      final projectDocumentTarget = projectName == null || projectName.isEmpty
          ? '当前配置项目'
          : projectName;

      final documents = <ConfigDocumentData>[
        _buildDocument(
          id: 'global',
          title: '全局 TOML',
          path: globalPath,
          content: null,
          description: '查看或编辑 ~/.config/mise/config.toml，这里通常决定全局默认工具链和基础设置。',
        ),
      ];
      if (resolvedProjectConfigPath != null && projectDocumentName != null) {
        documents.add(
          _buildDocument(
            id: 'workspace',
            title: '项目配置',
            path: resolvedProjectConfigPath,
            content: null,
            description:
                '查看或编辑$projectDocumentTarget下的 $projectDocumentName，这里的版本声明会覆盖全局默认值。',
          ),
        );
      }

      return ConfigWorkspaceData(
        sections: [
          ConfigSectionData(
            title: '读取失败',
            description: '这次没有成功读取配置文件，先保留路径信息，方便继续排查。',
            rawSnippet: error.toString(),
            items: const [
              ConfigItem(
                label: '当前状态',
                value: '暂不可读',
                detail: '请确认配置文件权限、路径和磁盘状态后再刷新。',
                level: HealthLevel.warning,
                isEditable: false,
              ),
            ],
          ),
        ],
        documents: documents,
        runtimeSettings: null,
        proxySettings: null,
      );
    }
  }

  @override
  Future<ConfigSavePreview> previewDocumentSave({
    required ConfigDocumentData document,
    required String nextContent,
  }) async {
    final normalizedCurrent = _normalizeContent(document.content);
    final normalizedNext = _normalizeContent(nextContent);
    final hasChanges = normalizedCurrent != normalizedNext;

    return ConfigSavePreview(
      document: document,
      nextContent: normalizedNext,
      diffPreview: _buildDiffPreview(
        before: normalizedCurrent,
        after: normalizedNext,
        path: document.path,
      ),
      commandPreview: [
        'cat ${document.path}',
        '# 图形界面文件写回预览',
        '# 将直接写入 ${document.path}',
      ].join('\n'),
      hasChanges: hasChanges,
      createsFile: !document.exists,
    );
  }

  @override
  Future<ConfigSavePreview> previewRuntimeSettingsSave({
    required ConfigRuntimeSettingsUpdate update,
  }) {
    return previewDocumentSave(
      document: update.document,
      nextContent: _buildRuntimeSettingsContent(
        currentContent: update.document.content,
        values: update.values,
      ),
    );
  }

  @override
  Future<ConfigSavePreview> previewProxySettingsSave({
    required ConfigProxySettingsUpdate update,
  }) {
    return previewDocumentSave(
      document: update.document,
      nextContent: _buildProxySettingsContent(
        currentContent: update.document.content,
        values: update.values,
      ),
    );
  }

  @override
  Future<void> saveDocument({
    required ConfigDocumentData document,
    required String nextContent,
  }) async {
    final file = File(document.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(_normalizeContent(nextContent));
  }

  String _globalConfigPath() {
    if (_globalConfigPathOverride case final path?) {
      return path;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '.config/mise/config.toml';
    }
    return '$home/.config/mise/config.toml';
  }

  ConfigRuntimeSettingsData _buildRuntimeSettings({
    required ConfigDocumentData document,
    required String? content,
  }) {
    final settings = _parseAssignments(_extractSection(content, 'settings'));
    return ConfigRuntimeSettingsData(
      document: document,
      settings: [
        for (final definition in _runtimeSettingDefinitions)
          ConfigRuntimeSetting(
            key: definition.key,
            label: definition.label,
            value: settings[definition.key] ?? '',
            defaultValue: definition.defaultValue,
            detail: definition.detail,
            type: definition.type,
            isSet: settings.containsKey(definition.key),
          ),
      ],
    );
  }

  ConfigProxySettingsData _buildProxySettings({
    required ConfigDocumentData document,
    required String? content,
  }) {
    final env = _parseAssignments(_extractSection(content, 'env'));
    return ConfigProxySettingsData(
      document: document,
      settings: [
        for (final definition in _proxySettingDefinitions)
          _buildProxySetting(env, definition),
      ],
    );
  }

  ConfigProxySetting _buildProxySetting(
    Map<String, String> env,
    _ProxySettingDefinition definition,
  ) {
    final value = _firstEnvValue(env, definition.aliases);
    return ConfigProxySetting(
      key: definition.key,
      label: definition.label,
      value: value,
      placeholder: definition.placeholder,
      detail: definition.detail,
      requiresUri: definition.requiresUri,
      isSet: value.isNotEmpty,
    );
  }

  String _firstEnvValue(Map<String, String> env, List<String> aliases) {
    for (final alias in aliases) {
      final value = env[alias]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _projectConfigPath({required String projectPath}) =>
      '$projectPath/mise.toml';

  String? _directoryPathFor(String? filePath) {
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    return File(filePath).parent.path;
  }

  String _fileNameForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Future<String?> _readFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  ConfigDocumentData _buildDocument({
    required String id,
    required String title,
    required String path,
    required String? content,
    required String description,
  }) {
    return ConfigDocumentData(
      id: id,
      title: title,
      path: path,
      content: content ?? '',
      description: description,
      commandPreview: ['cat $path', '# 通过图形界面直接编辑文件'].join('\n'),
      exists: content != null,
    );
  }

  ConfigSectionData _buildToolsSection({
    required String title,
    required String description,
    required String path,
    required String? content,
    required String sectionName,
  }) {
    final section = _extractSection(content, sectionName);
    final entries = _parseAssignments(section);
    final summary = entries.isEmpty
        ? '该文件里暂时没有 [$sectionName] 段。'
        : entries.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join(', ');

    return ConfigSectionData(
      title: title,
      description: description,
      rawSnippet:
          section ?? '# 未找到 [$sectionName] 段\n${content?.trim() ?? path}',
      items: [
        ConfigItem(
          label: '已声明工具',
          value: '${entries.length}',
          detail: summary,
          level: entries.isEmpty ? HealthLevel.info : HealthLevel.healthy,
          isEditable: content != null,
        ),
      ],
    );
  }

  ConfigSectionData _buildSettingsSection({
    required String title,
    required String description,
    required String path,
    required String? content,
  }) {
    final settings = _parseAssignments(_extractSection(content, 'settings'));
    final javaSettings = _parseAssignments(
      _extractSection(content, 'settings.java'),
    );
    final env = _parseAssignments(_extractSection(content, 'env'));

    final snippetParts = <String>[
      if (_extractSection(content, 'settings') case final section?)
        section.trim(),
      if (_extractSection(content, 'settings.java') case final section?)
        section.trim(),
      if (_extractSection(content, 'env') case final section?) section.trim(),
    ];

    return ConfigSectionData(
      title: title,
      description: description,
      rawSnippet: snippetParts.isEmpty
          ? '# 未找到 [settings] 相关配置\n${content?.trim() ?? path}'
          : snippetParts.join('\n\n'),
      items: [
        ConfigItem(
          label: 'HTTP 超时',
          value: settings['http_timeout'] ?? '未设置',
          detail: '控制下载类请求的超时时间，后续保存前会提供差异预览。',
          level: settings.containsKey('http_timeout')
              ? HealthLevel.healthy
              : HealthLevel.info,
          isEditable: content != null,
        ),
        ConfigItem(
          label: 'HTTP 重试',
          value: settings['http_retries'] ?? '未设置',
          detail: '决定网络失败时的自动重试次数。',
          level: settings.containsKey('http_retries')
              ? HealthLevel.healthy
              : HealthLevel.info,
          isEditable: content != null,
        ),
        ConfigItem(
          label: 'Java 发行版',
          value: javaSettings['shorthand_vendor'] ?? '未设置',
          detail: javaSettings.containsKey('shorthand_vendor')
              ? '当前默认 JDK 发行版已从文件直接读出。'
              : '当前没有在 settings.java 中声明 shorthand_vendor。',
          level: javaSettings.containsKey('shorthand_vendor')
              ? HealthLevel.healthy
              : HealthLevel.info,
          isEditable: content != null,
        ),
        ConfigItem(
          label: '代理环境变量',
          value: env.isEmpty ? '未配置' : '${env.length} 项',
          detail: env.isEmpty
              ? '当前配置文件没有 env 代理项。'
              : env.entries
                    .map((entry) => '${entry.key}=${entry.value}')
                    .join(', '),
          level: env.isEmpty ? HealthLevel.info : HealthLevel.warning,
          isEditable: content != null,
        ),
      ],
    );
  }

  ConfigSectionData _buildAliasSection({
    required String path,
    required String? content,
  }) {
    final aliases = _parseAssignments(
      _extractSection(content, 'tool_alias.java.versions'),
    );
    final preview = aliases.entries
        .take(5)
        .map((entry) {
          return '${entry.key} -> ${entry.value}';
        })
        .join(', ');

    return ConfigSectionData(
      title: 'Java 别名',
      description: '别名决定了像 java@17 这样的写法最终会落到哪个发行版，是很适合做可视化说明的一层配置。',
      rawSnippet:
          _extractSection(content, 'tool_alias.java.versions') ??
          '# 未找到 [tool_alias.java.versions] 段\n${content?.trim() ?? path}',
      items: [
        ConfigItem(
          label: '别名数量',
          value: '${aliases.length}',
          detail: aliases.isEmpty ? '当前没有配置 Java 版本别名。' : preview,
          level: aliases.isEmpty ? HealthLevel.info : HealthLevel.healthy,
          isEditable: content != null,
        ),
      ],
    );
  }

  String? _extractSection(String? content, String sectionName) {
    if (content == null || content.trim().isEmpty) {
      return null;
    }

    final lines = content.split('\n');
    final buffer = <String>[];
    final header = '[$sectionName]';
    var collecting = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        if (collecting) {
          break;
        }
        if (trimmed == header) {
          collecting = true;
          buffer.add(line);
          continue;
        }
      }

      if (collecting) {
        buffer.add(line);
      }
    }

    if (buffer.isEmpty) {
      return null;
    }
    return buffer.join('\n').trimRight();
  }

  Map<String, String> _parseAssignments(String? section) {
    if (section == null || section.trim().isEmpty) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    final lines = section.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('[') ||
          !trimmed.contains('=')) {
        continue;
      }

      final separatorIndex = trimmed.indexOf('=');
      final key = trimmed
          .substring(0, separatorIndex)
          .trim()
          .replaceAll('"', '');
      final value = _stripTomlQuotes(trimmed.substring(separatorIndex + 1));
      result[key] = value;
    }

    return result;
  }

  String _stripTomlQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return trimmed;
    }
    final quote = trimmed[0];
    if ((quote != '"' && quote != "'") ||
        trimmed[trimmed.length - 1] != quote) {
      return trimmed;
    }
    return trimmed
        .substring(1, trimmed.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'");
  }

  String _buildRuntimeSettingsContent({
    required String currentContent,
    required Map<String, String?> values,
  }) {
    final normalized = _normalizeContent(currentContent);
    final lines = normalized.isEmpty
        ? <String>[]
        : const LineSplitter().convert(normalized);
    final settingsStart = _findSectionStart(lines, 'settings');
    final nextValues = Map<String, String?>.from(values);

    if (settingsStart == -1) {
      final nextLines = <String>[...lines];
      if (nextLines.isNotEmpty && nextLines.last.trim().isNotEmpty) {
        nextLines.add('');
      }
      nextLines.add('[settings]');
      for (final definition in _runtimeSettingDefinitions) {
        final value = nextValues[definition.key]?.trim();
        if (value == null || value.isEmpty) {
          continue;
        }
        nextLines.add(
          '${definition.key} = ${_formatSettingValue(definition, value)}',
        );
      }
      return _normalizeContent(nextLines.join('\n'));
    }

    final settingsEnd = _findSectionEnd(lines, settingsStart);
    final sectionKeyPattern = RegExp(r'^([A-Za-z0-9_.-]+)\s*=');
    final handledKeys = <String>{};
    final nextLines = <String>[];

    nextLines.addAll(lines.take(settingsStart + 1));
    for (final line in lines.sublist(settingsStart + 1, settingsEnd)) {
      final match = sectionKeyPattern.firstMatch(line.trimLeft());
      final key = match?.group(1);
      if (key != null && nextValues.containsKey(key)) {
        handledKeys.add(key);
        final definition = _definitionForKey(key);
        final value = nextValues[key]?.trim();
        if (definition == null || value == null || value.isEmpty) {
          continue;
        }
        nextLines.add('$key = ${_formatSettingValue(definition, value)}');
        continue;
      }
      nextLines.add(line);
    }

    for (final definition in _runtimeSettingDefinitions) {
      if (handledKeys.contains(definition.key)) {
        continue;
      }
      final value = nextValues[definition.key]?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      nextLines.add(
        '${definition.key} = ${_formatSettingValue(definition, value)}',
      );
    }

    nextLines.addAll(lines.skip(settingsEnd));
    return _normalizeContent(nextLines.join('\n'));
  }

  String _buildProxySettingsContent({
    required String currentContent,
    required Map<String, String?> values,
  }) {
    final normalized = _normalizeContent(currentContent);
    final lines = normalized.isEmpty
        ? <String>[]
        : const LineSplitter().convert(normalized);
    final envStart = _findSectionStart(lines, 'env');

    final hasAnyProxyValue = values.values.any(
      (value) => value != null && value.trim().isNotEmpty,
    );
    if (envStart == -1) {
      if (!hasAnyProxyValue) {
        return normalized;
      }
      final nextLines = <String>[...lines];
      if (nextLines.isNotEmpty && nextLines.last.trim().isNotEmpty) {
        nextLines.add('');
      }
      nextLines.add('[env]');
      _appendProxySettingLines(nextLines, values);
      return _normalizeContent(nextLines.join('\n'));
    }

    final envEnd = _findSectionEnd(lines, envStart);
    final proxyAliases = _proxySettingDefinitions
        .expand((definition) => definition.aliases)
        .toSet();
    final sectionKeyPattern = RegExp(r'^([A-Za-z0-9_.-]+)\s*=');
    final nextLines = <String>[];

    nextLines.addAll(lines.take(envStart + 1));
    for (final line in lines.sublist(envStart + 1, envEnd)) {
      final match = sectionKeyPattern.firstMatch(line.trimLeft());
      final key = match?.group(1);
      if (key != null && proxyAliases.contains(key)) {
        continue;
      }
      nextLines.add(line);
    }

    _appendProxySettingLines(nextLines, values);
    nextLines.addAll(lines.skip(envEnd));
    return _normalizeContent(nextLines.join('\n'));
  }

  void _appendProxySettingLines(
    List<String> lines,
    Map<String, String?> values,
  ) {
    for (final definition in _proxySettingDefinitions) {
      final value = values[definition.key]?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      for (final alias in definition.aliases) {
        lines.add('$alias = "${_escapeTomlString(value)}"');
      }
    }
  }

  int _findSectionStart(List<String> lines, String sectionName) {
    final header = '[$sectionName]';
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim() == header) {
        return index;
      }
    }
    return -1;
  }

  int _findSectionEnd(List<String> lines, int sectionStart) {
    for (var index = sectionStart + 1; index < lines.length; index++) {
      final trimmed = lines[index].trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        return index;
      }
    }
    return lines.length;
  }

  _RuntimeSettingDefinition? _definitionForKey(String key) {
    for (final definition in _runtimeSettingDefinitions) {
      if (definition.key == key) {
        return definition;
      }
    }
    return null;
  }

  String _formatSettingValue(
    _RuntimeSettingDefinition definition,
    String value,
  ) {
    return switch (definition.type) {
      ConfigRuntimeSettingType.string => '"${_escapeTomlString(value)}"',
      ConfigRuntimeSettingType.integer => value,
      ConfigRuntimeSettingType.boolean => value,
    };
  }

  String _escapeTomlString(String value) {
    return value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  }

  String _normalizeContent(String value) {
    final normalized = value.replaceAll('\r\n', '\n').trimRight();
    return normalized.isEmpty ? '' : '$normalized\n';
  }

  String _buildDiffPreview({
    required String before,
    required String after,
    required String path,
  }) {
    if (before == after) {
      return ['--- $path', '+++ $path', '# 内容没有变化'].join('\n');
    }

    final beforeLines = const LineSplitter().convert(before);
    final afterLines = const LineSplitter().convert(after);

    var prefix = 0;
    while (prefix < beforeLines.length &&
        prefix < afterLines.length &&
        beforeLines[prefix] == afterLines[prefix]) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < beforeLines.length - prefix &&
        suffix < afterLines.length - prefix &&
        beforeLines[beforeLines.length - 1 - suffix] ==
            afterLines[afterLines.length - 1 - suffix]) {
      suffix += 1;
    }

    final changedBefore = beforeLines.sublist(
      prefix,
      beforeLines.length - suffix,
    );
    final changedAfter = afterLines.sublist(prefix, afterLines.length - suffix);

    final diff = <String>[
      '--- $path',
      '+++ $path',
      if (prefix > 0) '@@ ... 前面还有 $prefix 行未变化 @@',
      ...changedBefore.map((line) => '- $line'),
      ...changedAfter.map((line) => '+ $line'),
      if (suffix > 0) '@@ ... 后面还有 $suffix 行未变化 @@',
    ];

    return diff.join('\n');
  }
}

class MockConfigService implements ConfigService {
  const MockConfigService();

  @override
  Future<ConfigWorkspaceData> fetchWorkspace({
    String? projectPath,
    String? projectConfigPath,
    String? projectName,
    bool includeProjectConfig = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));

    return const ConfigWorkspaceData(
      documents: [
        ConfigDocumentData(
          id: 'global',
          title: '全局 TOML',
          path: '~/.config/mise/config.toml',
          content:
              '[tools]\npython = "3.11"\njava = "21"\n\n[settings]\nidiomatic_version_file_enable = false\n',
          description: '示例全局配置文件。',
          commandPreview: 'cat ~/.config/mise/config.toml',
          exists: true,
        ),
        ConfigDocumentData(
          id: 'workspace',
          title: '项目配置',
          path: './mise.toml',
          content: '[tools]\nflutter = "3.41.4"\n',
          description: '示例项目配置文件。',
          commandPreview: 'cat ./mise.toml',
          exists: true,
        ),
      ],
      sections: [
        ConfigSectionData(
          title: '基础设置',
          description: '控制 mise 的基础行为，让界面与命令行的默认行为保持一致。',
          rawSnippet:
              '[settings]\nidiomatic_version_file_enable = false\nlegacy_version_file = false',
          items: [
            ConfigItem(
              label: '惯用版本文件',
              value: '关闭',
              detail: '当前只信任 mise.toml，避免与 .nvmrc/.python-version 混用。',
              level: HealthLevel.healthy,
              isEditable: true,
            ),
            ConfigItem(
              label: '旧版文件回退',
              value: '关闭',
              detail: '关闭后更容易解释版本来源。',
              level: HealthLevel.info,
              isEditable: true,
            ),
          ],
        ),
        ConfigSectionData(
          title: 'Java',
          description: '把发行版、别名和默认 JDK 的关系说明清楚。',
          rawSnippet:
              '[java]\ndefault_packages = []\n[settings.java]\nvendor = "temurin"\naliases = ["lts=21"]',
          items: [
            ConfigItem(
              label: '默认发行版',
              value: 'temurin',
              detail: '优先拉取 Temurin，兼顾通用性和稳定性。',
              level: HealthLevel.healthy,
              isEditable: true,
            ),
            ConfigItem(
              label: '别名 lts',
              value: '21',
              detail: '减少命令心智负担，命令预览里会展示别名解析链路。',
              level: HealthLevel.info,
              isEditable: true,
            ),
          ],
        ),
        ConfigSectionData(
          title: '网络与镜像',
          description: '把代理、镜像和下载异常集中到同一个排查入口。',
          rawSnippet:
              '[env]\nhttp_proxy = "http://127.0.0.1:7890"\nhttps_proxy = "http://127.0.0.1:7890"',
          items: [
            ConfigItem(
              label: 'HTTP 代理',
              value: '127.0.0.1:7890',
              detail: '当前已配置，但未做健康检测回填。',
              level: HealthLevel.warning,
              isEditable: true,
            ),
            ConfigItem(
              label: '镜像策略',
              value: '部分覆盖',
              detail: '只有部分工具链使用统一镜像源，建议在配置页明确指出这些差异。',
              level: HealthLevel.warning,
              isEditable: false,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<ConfigSavePreview> previewDocumentSave({
    required ConfigDocumentData document,
    required String nextContent,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return ConfigSavePreview(
      document: document,
      nextContent: nextContent,
      diffPreview: '--- ${document.path}\n+++ ${document.path}\n# 模拟预览',
      commandPreview: 'cat ${document.path}\n# mock direct file save',
      hasChanges: document.content != nextContent,
      createsFile: !document.exists,
    );
  }

  @override
  Future<ConfigSavePreview> previewRuntimeSettingsSave({
    required ConfigRuntimeSettingsUpdate update,
  }) {
    return previewDocumentSave(
      document: update.document,
      nextContent: update.document.content,
    );
  }

  @override
  Future<ConfigSavePreview> previewProxySettingsSave({
    required ConfigProxySettingsUpdate update,
  }) {
    return previewDocumentSave(
      document: update.document,
      nextContent: update.document.content,
    );
  }

  @override
  Future<void> saveDocument({
    required ConfigDocumentData document,
    required String nextContent,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
}
