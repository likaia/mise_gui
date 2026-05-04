import 'dart:convert';
import 'dart:io';

import 'package:mise_gui/models/app_models.dart';

const _githubOwner = 'likaia';
const _githubRepo = 'mise_gui';
const _githubTagsPageUrl = 'https://github.com/likaia/mise_gui/tags';
const _githubReleasesPageUrl = 'https://github.com/likaia/mise_gui/releases';
const _githubApiBase =
    'https://api.github.com/repos/$_githubOwner/$_githubRepo';

String normalizeReleaseVersion(String raw) {
  var normalized = raw.trim();
  if (normalized.startsWith('refs/tags/')) {
    normalized = normalized.substring('refs/tags/'.length);
  }
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1);
  }
  final buildMetadataIndex = normalized.indexOf('+');
  if (buildMetadataIndex >= 0) {
    normalized = normalized.substring(0, buildMetadataIndex);
  }
  return normalized.trim();
}

int compareReleaseVersions(String left, String right) {
  final leftVersion = _ParsedVersion.parse(left);
  final rightVersion = _ParsedVersion.parse(right);
  return leftVersion.compareTo(rightVersion);
}

abstract class AppUpdateService {
  Future<AppUpdateInfo?> checkForUpdate({required String currentVersion});
}

class GitHubAppUpdateService implements AppUpdateService {
  const GitHubAppUpdateService();

  @override
  Future<AppUpdateInfo?> checkForUpdate({
    required String currentVersion,
  }) async {
    final tags = await _getJsonList('$_githubApiBase/tags?per_page=1');
    if (tags.isEmpty) {
      return null;
    }

    final latestTag = tags.first;
    final tagName = latestTag['name']?.toString().trim();
    if (tagName == null || tagName.isEmpty) {
      return null;
    }

    final latestVersion = normalizeReleaseVersion(tagName);
    final normalizedCurrentVersion = normalizeReleaseVersion(currentVersion);
    if (compareReleaseVersions(latestVersion, normalizedCurrentVersion) <= 0) {
      return null;
    }

    var releaseNotes = '发现新版本 $tagName，可前往 GitHub 查看更新详情。';
    var releaseUrl = '$_githubReleasesPageUrl/tag/$tagName';
    final commitSha = _resolveTagCommitSha(latestTag);

    final releaseJson = await _getJsonMap(
      '$_githubApiBase/releases/tags/${Uri.encodeComponent(tagName)}',
      allowNotFound: true,
    );
    if (releaseJson != null) {
      final body = releaseJson['body']?.toString().trim();
      final htmlUrl = releaseJson['html_url']?.toString().trim();
      if (body != null && body.isNotEmpty) {
        releaseNotes = body;
      }
      if (htmlUrl != null && htmlUrl.isNotEmpty) {
        releaseUrl = htmlUrl;
      }
    }

    if (releaseNotes == '发现新版本 $tagName，可前往 GitHub 查看更新详情。' &&
        commitSha != null) {
      final commitJson = await _getJsonMap(
        '$_githubApiBase/commits/$commitSha',
        allowNotFound: true,
      );
      final commitMessage = commitJson?['commit'] is Map
          ? (commitJson!['commit'] as Map)['message']?.toString().trim()
          : null;
      if (commitMessage != null && commitMessage.isNotEmpty) {
        releaseNotes = commitMessage;
      }
    }

    return AppUpdateInfo(
      currentVersion: normalizedCurrentVersion,
      latestVersion: latestVersion,
      tagName: tagName,
      releaseNotes: releaseNotes,
      releaseUrl: releaseUrl,
    );
  }

  Future<List<Map<String, dynamic>>> _getJsonList(String rawUrl) async {
    final response = await _get(rawUrl);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Unexpected response ${response.statusCode} for $rawUrl',
        uri: Uri.parse(rawUrl),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const <Map<String, dynamic>>[];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _getJsonMap(
    String rawUrl, {
    bool allowNotFound = false,
  }) async {
    final response = await _get(rawUrl);
    if (allowNotFound && response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Unexpected response ${response.statusCode} for $rawUrl',
        uri: Uri.parse(rawUrl),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return null;
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<_HttpResponse> _get(String rawUrl) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);

    try {
      final request = await client.getUrl(Uri.parse(rawUrl));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'mise_gui-update-checker',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _HttpResponse(statusCode: response.statusCode, body: body);
    } finally {
      client.close(force: true);
    }
  }

  String? _resolveTagCommitSha(Map<String, dynamic> latestTag) {
    final commit = latestTag['commit'];
    if (commit is Map) {
      final sha = commit['sha']?.toString().trim();
      if (sha != null && sha.isNotEmpty) {
        return sha;
      }
    }
    return null;
  }
}

class _HttpResponse {
  const _HttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class _ParsedVersion {
  const _ParsedVersion({required this.core, required this.preRelease});

  final List<int> core;
  final List<String> preRelease;

  factory _ParsedVersion.parse(String raw) {
    final normalized = normalizeReleaseVersion(raw);
    final separatorIndex = normalized.indexOf('-');
    final corePart = separatorIndex >= 0
        ? normalized.substring(0, separatorIndex)
        : normalized;
    final preReleasePart = separatorIndex >= 0
        ? normalized.substring(separatorIndex + 1)
        : null;
    final core = corePart
        .split('.')
        .where((item) => item.trim().isNotEmpty)
        .map((item) => int.tryParse(item) ?? 0)
        .toList(growable: false);
    final preRelease = preReleasePart == null || preReleasePart.isEmpty
        ? const <String>[]
        : preReleasePart
              .split('.')
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false);

    return _ParsedVersion(core: core, preRelease: preRelease);
  }

  int compareTo(_ParsedVersion other) {
    final maxLength = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var index = 0; index < maxLength; index += 1) {
      final left = index < core.length ? core[index] : 0;
      final right = index < other.core.length ? other.core[index] : 0;
      if (left != right) {
        return left.compareTo(right);
      }
    }

    final hasPreRelease = preRelease.isNotEmpty;
    final otherHasPreRelease = other.preRelease.isNotEmpty;
    if (hasPreRelease != otherHasPreRelease) {
      return hasPreRelease ? -1 : 1;
    }

    final maxPreReleaseLength = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < maxPreReleaseLength; index += 1) {
      if (index >= preRelease.length) {
        return -1;
      }
      if (index >= other.preRelease.length) {
        return 1;
      }

      final left = preRelease[index];
      final right = other.preRelease[index];
      final leftNumeric = int.tryParse(left);
      final rightNumeric = int.tryParse(right);
      if (leftNumeric != null && rightNumeric != null) {
        if (leftNumeric != rightNumeric) {
          return leftNumeric.compareTo(rightNumeric);
        }
        continue;
      }
      if (leftNumeric != null) {
        return -1;
      }
      if (rightNumeric != null) {
        return 1;
      }

      final compared = left.compareTo(right);
      if (compared != 0) {
        return compared;
      }
    }

    return 0;
  }
}
