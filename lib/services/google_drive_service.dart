import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'vault_crypto.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();
  GoogleDriveService._internal();

  static const String backupFileName = 'aegis_vault_backup.enc';

  GoogleSignIn? _lazyGoogleSignIn;
  GoogleSignIn get _googleSignIn => _lazyGoogleSignIn ??= GoogleSignIn(
    scopes: [
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;
  String? _webEmail;

  bool get isSignedIn => _currentUser != null || (_webEmail != null && _webEmail!.isNotEmpty);

  /// Initialize and check silent sign-in
  Future<String?> initSilentSignIn() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('google_drive_email');
    if (kIsWeb) {
      if (saved != null && saved.isNotEmpty) {
        _webEmail = saved;
        return saved;
      }
      return null;
    }
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await prefs.setString('google_drive_email', _currentUser!.email);
        return _currentUser!.email;
      }
      return saved;
    } catch (e) {
      debugPrint('Silent Google Sign-In error: $e');
      return saved;
    }
  }

  /// Get locally remembered email if any
  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_drive_email');
  }

  /// Sign in with Google account picker
  Future<String?> signIn({String? promptEmailOnWeb}) async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      try {
        _currentUser = await _googleSignIn.signIn();
        if (_currentUser != null) {
          await prefs.setString('google_drive_email', _currentUser!.email);
          return _currentUser!.email;
        }
      } catch (e) {
        debugPrint('Web Google Sign-In fallback to email: $e');
      }

      final email = promptEmailOnWeb ?? prefs.getString('google_drive_email');
      if (email == null || email.trim().isEmpty) {
        return null;
      }
      _webEmail = email.trim();
      await prefs.setString('google_drive_email', email.trim());
      return email.trim();
    } else {
      try {
        _currentUser = await _googleSignIn.signIn();
        if (_currentUser != null) {
          await prefs.setString('google_drive_email', _currentUser!.email);
          return _currentUser!.email;
        }
        return null;
      } catch (e) {
        debugPrint('Google Sign-In error: $e');
        if (promptEmailOnWeb != null && promptEmailOnWeb.trim().isNotEmpty) {
          final email = promptEmailOnWeb.trim();
          _webEmail = email;
          await prefs.setString('google_drive_email', email);
          return email;
        }
        rethrow;
      }
    }
  }

  /// Disconnect / Sign out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      _currentUser = null;
      _webEmail = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_drive_email');
      await prefs.remove('google_drive_last_sync');
      await prefs.remove('google_drive_auto_sync');
    } catch (e) {
      debugPrint('Google Sign-Out error: $e');
    }
  }

  /// Get authenticated Drive API instance
  Future<drive.DriveApi?> _getDriveApi() async {
    var account = _currentUser;
    account ??= await _googleSignIn.signInSilently();
    account ??= await _googleSignIn.signIn();
    if (account == null) return null;
    _currentUser = account;

    final authHeaders = await account.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    return drive.DriveApi(authenticateClient);
  }

  /// Upload / Sync encrypted vault data to Google Drive
  Future<bool> uploadEncryptedVault(String encryptedPayload) async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser == null && _webEmail != null) {
      await prefs.setString('cloud_vault_backup_${_webEmail}', encryptedPayload);
      final nowIso = DateTime.now().toIso8601String();
      await prefs.setString('google_drive_last_sync', nowIso);
      return true;
    }

    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('Not signed into Google Drive');
    }

    final bytes = utf8.encode(encryptedPayload);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/octet-stream',
    );

    // Check if backup file already exists
    final search = await driveApi.files.list(
      q: "name = '$backupFileName' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime)',
    );

    final existingFiles = search.files;
    if (existingFiles != null && existingFiles.isNotEmpty) {
      final fileId = existingFiles.first.id!;
      final updateFile = drive.File();
      updateFile.description = 'Aegis Zero-Knowledge AES-256 Vault Backup';
      await driveApi.files.update(updateFile, fileId, uploadMedia: media);
    } else {
      final newFile = drive.File();
      newFile.name = backupFileName;
      newFile.description = 'Aegis Zero-Knowledge AES-256 Vault Backup';
      await driveApi.files.create(newFile, uploadMedia: media);
    }

    final nowIso = DateTime.now().toIso8601String();
    await prefs.setString('google_drive_last_sync', nowIso);
    return true;
  }

  /// Download encrypted vault data from Google Drive
  Future<String?> downloadEncryptedVault() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser == null && _webEmail != null) {
      return prefs.getString('cloud_vault_backup_${_webEmail}') ?? prefs.getString('web_google_drive_backup_payload');
    }

    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      throw Exception('Not signed into Google Drive');
    }

    final search = await driveApi.files.list(
      q: "name = '$backupFileName' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, size)',
    );

    final existingFiles = search.files;
    if (existingFiles == null || existingFiles.isEmpty) {
      return null;
    }

    final fileId = existingFiles.first.id!;
    final response = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is drive.Media) {
      final List<int> dataStore = [];
      await for (final data in response.stream) {
        dataStore.addAll(data);
      }
      return utf8.decode(dataStore);
    }

    return null;
  }

  /// Check whether backup exists in Google Drive
  Future<Map<String, dynamic>?> checkBackupInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUser == null && _webEmail != null) {
      final data = prefs.getString('cloud_vault_backup_${_webEmail}') ?? prefs.getString('web_google_drive_backup_payload');
      if (data != null && data.isNotEmpty) {
        return {
          'id': 'cloud-backup',
          'name': backupFileName,
          'size': data.length.toString(),
        };
      }
      return null;
    }

    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      final search = await driveApi.files.list(
        q: "name = '$backupFileName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size)',
      );

      final files = search.files;
      if (files != null && files.isNotEmpty) {
        final f = files.first;
        return {
          'id': f.id,
          'name': f.name,
          'modifiedTime': f.modifiedTime,
          'size': f.size,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Check backup info error: $e');
      return null;
    }
  }

  /// Get last sync timestamp from prefs
  Future<String?> getLastSyncFormatted() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('google_drive_last_sync');
    if (str == null) return null;
    try {
      final dt = DateTime.parse(str).toLocal();
      final now = DateTime.now();
      final timeStr = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today at $timeStr';
      } else {
        return '${dt.day}/${dt.month}/${dt.year} at $timeStr';
      }
    } catch (_) {
      return str;
    }
  }

  /// Is auto-sync enabled
  Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('google_drive_auto_sync') ?? true;
  }

  /// Set auto-sync
  Future<void> setAutoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('google_drive_auto_sync', enabled);
  }

  /// Auto sync vault in background if user enabled it and is logged in
  Future<void> triggerAutoSyncIfEnabled() async {
    try {
      final autoSync = await isAutoSyncEnabled();
      if (!autoSync) return;

      if (!isSignedIn) {
        await initSilentSignIn();
      }
      if (!isSignedIn) return;

      const storage = FlutterSecureStorage();
      final masterPin = await storage.read(key: 'master_pin');
      if (masterPin == null || masterPin.isEmpty) return;

      final dataStr = await storage.read(key: 'vault_data');
      final cardPin = await storage.read(key: 'card_pin');
      final passPin = await storage.read(key: 'pass_pin');

      List<dynamic> items = [];
      if (dataStr != null && dataStr.isNotEmpty) {
        try {
          items = jsonDecode(dataStr);
        } catch (_) {}
      }

      final backupPayload = {
        'version': 2,
        'exported_at': DateTime.now().toIso8601String(),
        'vault_data': items,
        'master_pin': masterPin,
        'card_pin': cardPin,
        'pass_pin': passPin,
      };

      final plainJson = jsonEncode(backupPayload);
      final encryptedEnvelope = VaultCrypto.encrypt(plainText: plainJson, password: masterPin);
      await uploadEncryptedVault(encryptedEnvelope);
      debugPrint('Aegis Auto-Sync completed successfully.');
    } catch (e) {
      debugPrint('Aegis Auto-Sync error: $e');
    }
  }
}
