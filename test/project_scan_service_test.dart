import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_query_service.dart';
import 'package:mise_gui/services/project_scan_service.dart';

class _FakeMiseQueryService implements MiseQueryService {
  const _FakeMiseQueryService();

  @override
  Future<Map<String, List<MiseInstalledToolVersionRef>>> fetchInstalledTools({
    String? workingDirectory,
  }) async {
    return const <String, List<MiseInstalledToolVersionRef>>{};
  }

  @override
  Future<List<MiseCurrentToolRef>> fetchCurrentTools({
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchEnvironment({String? workingDirectory}) {
    throw UnimplementedError();
  }

  @override
  Future<MiseResolvedExecutableRef> fetchExecutable(
    String subject, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchOutdated({String? workingDirectory}) {
    throw UnimplementedError();
  }

  @override
  Future<List<MiseRemoteToolVersionRef>> fetchRemoteVersions(
    String tool, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchSettings({String? workingDirectory}) {
    throw UnimplementedError();
  }

  @override
  Future<MiseResolvedExecutableRef> fetchShellExecutable(
    String subject, {
    String? workingDirectory,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('discovers projects from single-tool version files', () async {
    final root = await Directory.systemTemp.createTemp('mise-project-scan-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final app = Directory('${root.path}/app');
    final api = Directory('${root.path}/api');
    await app.create();
    await api.create();
    await File('${app.path}/.node-version').writeAsString('v20.18.0\n');
    await File('${api.path}/.python-version').writeAsString('3.12.4\n');

    const service = LiveProjectScanService(
      queryService: _FakeMiseQueryService(),
    );
    final projects = await service.fetchProjects([
      ScanDirectoryRecord(path: root.path),
    ]);

    expect(projects.map((project) => project.name), ['api', 'app']);
    final appProject = projects.firstWhere((project) => project.name == 'app');
    expect(appProject.configPath, '${app.path}/.node-version');
    expect(appProject.configPaths, ['${app.path}/.node-version']);
    expect(appProject.environment, 'Node 工作区');
    expect(
      appProject.commandPreview,
      contains('cat ${app.path}/.node-version'),
    );
    expect(appProject.bindings.single.name, 'node');
    expect(appProject.bindings.single.projectVersion, '20.18.0');
    expect(appProject.bindings.single.source, '项目 .node-version');
  });

  test('parses .tool-versions and keeps mise.toml precedence', () async {
    final root = await Directory.systemTemp.createTemp('mise-project-scan-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final project = Directory('${root.path}/web');
    await project.create();
    await File(
      '${project.path}/mise.toml',
    ).writeAsString('[tools]\nnode = "22.3.0"\n');
    await File('${project.path}/.tool-versions').writeAsString(
      '# compatible with asdf\n'
      'nodejs 20.18.0\n'
      'python 3.12.4\n',
    );

    const service = LiveProjectScanService(
      queryService: _FakeMiseQueryService(),
    );
    final projects = await service.fetchProjects([
      ScanDirectoryRecord(path: root.path),
    ]);

    expect(projects, hasLength(1));
    final bindings = {
      for (final binding in projects.single.bindings) binding.name: binding,
    };
    expect(projects.single.configPath, '${project.path}/mise.toml');
    expect(projects.single.configPaths, [
      '${project.path}/mise.toml',
      '${project.path}/.tool-versions',
    ]);
    expect(bindings['node']?.projectVersion, '22.3.0');
    expect(bindings['node']?.source, '项目');
    expect(bindings['python']?.projectVersion, '3.12.4');
    expect(bindings['python']?.source, '项目 .tool-versions');
  });
}
