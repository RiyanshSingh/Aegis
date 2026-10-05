import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String title;
  final String changelog;
  final String downloadUrl;
  final String htmlUrl;
  final DateTime? publishedAt;

  AppUpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
    required this.htmlUrl,
    this.publishedAt,
  });
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  // Configurable GitHub repo path: "owner/repo"
  static const String defaultRepo = 'RiyanshSingh/Aegis';
  static const String _prefRepoKey = 'custom_github_repo';

  Future<String> getRepo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefRepoKey) ?? defaultRepo;
  }

  Future<void> setRepo(String repo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRepoKey, repo.trim());
  }

  /// Check GitHub releases for an update
  Future<AppUpdateInfo?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final repo = await getRepo();
      final url = Uri.parse('https://api.github.com/repos/$repo/releases/latest');

      final response = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[AppUpdateService] GitHub API status: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTag = data['tag_name'] as String? ?? '';
      final latestVersion = rawTag.replaceAll(RegExp(r'^[vV]'), '').trim();

      if (!_isVersionGreater(latestVersion, currentVersion)) {
        return null; // Already up to date
      }

      final releaseName = data['name'] as String? ?? 'Version $latestVersion';
      final changelog = data['body'] as String? ?? 'Performance improvements and bug fixes.';
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$repo/releases/latest';

      String downloadUrl = htmlUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String? ?? downloadUrl;
          break;
        }
      }

      DateTime? published;
      if (data['published_at'] != null) {
        published = DateTime.tryParse(data['published_at']);
      }

      return AppUpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        title: releaseName,
        changelog: changelog,
        downloadUrl: downloadUrl,
        htmlUrl: htmlUrl,
        publishedAt: published,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking for updates: $e');
      return null;
    }
  }

  /// Shows the update popup dialog if a new version is found
  Future<void> checkForUpdate(
    BuildContext context, {
    bool silent = true,
    VoidCallback? onUpToDate,
    void Function(String message)? onError,
  }) async {
    try {
      final update = await checkUpdate();
      if (!context.mounted) return;

      if (update != null) {
        showUpdateDialog(context, update);
      } else if (!silent) {
        if (onUpToDate != null) {
          onUpToDate();
        }
      }
    } catch (_) {
      if (!silent && onError != null) {
        onError('Unable to check for updates. Please check your internet connection.');
      }
    }
  }

  /// Display a sleek, high-end obsidian update dialog
  void showUpdateDialog(BuildContext context, AppUpdateInfo update) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141416) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Colors.blueAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Update Available',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'v${update.latestVersion}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Current: v${update.currentVersion} • Tap update to upgrade',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'What\'s New:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      update.changelog.trim().isNotEmpty
                          ? update.changelog.trim()
                          : '• Performance improvements and bug fixes.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Later',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final uri = Uri.parse(update.downloadUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: const Text(
                          'Download Update',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Helper: compares semantic versions e.g. "1.0.1" > "1.0.0"
  bool _isVersionGreater(String remote, String local) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      while (rParts.length < 3) {
        rParts.add(0);
      }
      while (lParts.length < 3) {
        lParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (rParts[i] > lParts[i]) return true;
        if (rParts[i] < lParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
