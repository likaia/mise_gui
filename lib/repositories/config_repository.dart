import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/config_service.dart';

class ConfigRepository {
  const ConfigRepository(this._configService);

  final ConfigService _configService;

  Future<ConfigWorkspaceData> loadWorkspace({
    String? projectPath,
    String? projectConfigPath,
    String? projectName,
    bool includeProjectConfig = true,
  }) {
    return _configService.fetchWorkspace(
      projectPath: projectPath,
      projectConfigPath: projectConfigPath,
      projectName: projectName,
      includeProjectConfig: includeProjectConfig,
    );
  }

  Future<ConfigSavePreview> previewSave({
    required ConfigDocumentData document,
    required String nextContent,
  }) {
    return _configService.previewDocumentSave(
      document: document,
      nextContent: nextContent,
    );
  }

  Future<ConfigSavePreview> previewRuntimeSettingsSave({
    required ConfigRuntimeSettingsUpdate update,
  }) {
    return _configService.previewRuntimeSettingsSave(update: update);
  }

  Future<ConfigSavePreview> previewProxySettingsSave({
    required ConfigProxySettingsUpdate update,
  }) {
    return _configService.previewProxySettingsSave(update: update);
  }

  Future<void> saveDocument({
    required ConfigDocumentData document,
    required String nextContent,
  }) {
    return _configService.saveDocument(
      document: document,
      nextContent: nextContent,
    );
  }
}
