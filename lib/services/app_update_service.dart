import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    final repo = await getRepo();
    final url = Uri.parse('https://api.github.com/repos/$repo/releases/latest');

    final response = await http.get(url, headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'AegisVaultApp/1.0',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rawTag = data['tag_name'] as String? ?? '';
    final latestVersion = rawTag.replaceAll(RegExp(r'^[vV]'), '').trim();

    if (!_isVersionGreater(latestVersion, currentVersion)) {
      return null; // Truly up to date
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
    } catch (e) {
      debugPrint('[AppUpdateService] Check update error: $e');
      if (!silent && onError != null) {
        onError('Unable to reach update server. Please check your internet connection.');
      }
    }
  }

  /// Display a sleek, high-end obsidian update dialog with live in-app download and native install prompt
  void showUpdateDialog(BuildContext context, AppUpdateInfo update) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    bool isDownloading = false;
    bool isDownloaded = false;
    double downloadProgress = 0.0;
    String progressText = '';
    String? downloadedFilePath;
    String? downloadError;
    HttpClient? downloadClient;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141416) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> startDownload() async {
              if (kIsWeb || !Platform.isAndroid) {
                final uri = Uri.parse(update.downloadUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }

              setModalState(() {
                isDownloading = true;
                isDownloaded = false;
                downloadError = null;
                downloadProgress = 0.0;
                progressText = 'Connecting to server...';
              });

              IOSink? sink;
              try {
                final tempDir = await getTemporaryDirectory();
                final filePath = '${tempDir.path}/aegis_v${update.latestVersion}.apk';
                final file = File(filePath);
                if (await file.exists()) {
                  await file.delete();
                }

                final client = HttpClient();
                downloadClient = client;

                final request = await client.getUrl(Uri.parse(update.downloadUrl));
                request.headers.set('User-Agent', 'AegisVaultApp/1.0');
                final response = await request.close();

                if (response.statusCode != 200) {
                  throw Exception('Server returned HTTP ${response.statusCode}');
                }

                sink = file.openWrite();
                final totalBytes = response.contentLength;
                int receivedBytes = 0;

                await for (final chunk in response) {
                  sink.add(chunk);
                  receivedBytes += chunk.length;

                  if (totalBytes > 0) {
                    final p = receivedBytes / totalBytes;
                    final mbRec = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                    final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
                    setModalState(() {
                      downloadProgress = p.clamp(0.0, 1.0);
                      progressText = '${(downloadProgress * 100).toInt()}% • $mbRec MB / $mbTotal MB';
                    });
                  } else {
                    final mbRec = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                    setModalState(() {
                      downloadProgress = -1.0;
                      progressText = '$mbRec MB downloaded...';
                    });
                  }
                }

                await sink.flush();
                await sink.close();
                sink = null;
                client.close();

                setModalState(() {
                  isDownloading = false;
                  isDownloaded = true;
                  downloadedFilePath = filePath;
                  progressText = 'Download complete! Opening installer...';
                });

                // Auto launch native Android package installer
                await OpenFilex.open(
                  filePath,
                  type: 'application/vnd.android.package-archive',
                );
              } catch (e) {
                if (sink != null) {
                  try {
                    await sink.close();
                  } catch (_) {}
                }
                setModalState(() {
                  isDownloading = false;
                  downloadError = 'Download failed: ${e.toString().replaceAll('Exception:', '').trim()}';
                });
              }
            }

            return PopScope(
              canPop: !isDownloading,
              child: SafeArea(
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
                                  'Current: v${update.currentVersion} • New version ready',
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
                        constraints: const BoxConstraints(maxHeight: 150),
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
                      const SizedBox(height: 20),

                      // Live download progress area
                      if (isDownloading || isDownloaded) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1F) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDownloaded
                                  ? Colors.greenAccent.withValues(alpha: 0.3)
                                  : Colors.blueAccent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isDownloaded
                                        ? Icons.check_circle_rounded
                                        : Icons.downloading_rounded,
                                    size: 18,
                                    color: isDownloaded ? Colors.greenAccent : Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      isDownloaded ? 'Downloaded Successfully' : 'Downloading Update...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  if (isDownloading)
                                    GestureDetector(
                                      onTap: () {
                                        downloadClient?.close(force: true);
                                        setModalState(() {
                                          isDownloading = false;
                                          downloadError = 'Download cancelled';
                                        });
                                      },
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: isDownloaded
                                      ? 1.0
                                      : (downloadProgress >= 0 ? downloadProgress : null),
                                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isDownloaded ? Colors.greenAccent : Colors.blueAccent,
                                  ),
                                  minHeight: 7,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                progressText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Error message container if download fails
                      if (downloadError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  downloadError!,
                                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Action buttons
                      Row(
                        children: [
                          if (!isDownloading) ...[
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
                                  isDownloaded ? 'Close' : 'Later',
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(0, 50),
                                backgroundColor: isDownloaded
                                    ? Colors.green
                                    : (isDark ? Colors.white : Colors.black),
                                foregroundColor: isDownloaded
                                    ? Colors.white
                                    : (isDark ? Colors.black : Colors.white),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              onPressed: isDownloading
                                  ? null
                                  : () async {
                                      if (isDownloaded && downloadedFilePath != null) {
                                        await OpenFilex.open(
                                          downloadedFilePath!,
                                          type: 'application/vnd.android.package-archive',
                                        );
                                      } else {
                                        await startDownload();
                                      }
                                    },
                              icon: isDownloading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                                      ),
                                    )
                                  : Icon(
                                      isDownloaded
                                          ? Icons.install_mobile_rounded
                                          : Icons.download_rounded,
                                      size: 20,
                                    ),
                              label: Text(
                                isDownloading
                                    ? 'Downloading...'
                                    : (isDownloaded ? 'Install Update Now' : 'Download Update'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Helper: compares semantic versions e.g. "1.0.1" > "1.0.0"
  bool _isVersionGreater(String remote, String local) {
    try {
      final cleanRemote = remote.replaceAll(RegExp(r'^[vV]'), '').split('+').first.split('-').first.trim();
      final cleanLocal = local.replaceAll(RegExp(r'^[vV]'), '').split('+').first.split('-').first.trim();

      final rParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = cleanLocal.split('.').map((e) => int.tryParse(e) ?? 0).toList();

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
