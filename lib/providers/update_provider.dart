import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateProvider extends ChangeNotifier {
  // ── Platform channels ────────────────────────────────────────────────────────
  static const _methodChannel = MethodChannel('com.cardvault/ota');
  static const _eventChannel  = EventChannel('com.cardvault/ota_progress');

  // ── State ────────────────────────────────────────────────────────────────────
  bool _isUpdateAvailable = false;
  bool _updateIgnored = false;
  bool get isUpdateAvailable => _isUpdateAvailable && !_updateIgnored;

  String _updateMessage = '';
  String get updateMessage => _updateMessage;

  String _apkUrl = '';
  String get apkUrl => _apkUrl;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  String _downloadStatus = '';
  String get downloadStatus => _downloadStatus;   // 'pending' | 'downloading' | 'paused' | 'done' | 'installing' | 'error'

  String _remoteVersion = '';
  String get remoteVersion => _remoteVersion;

  String _releaseNotes = '';
  String get releaseNotes => _releaseNotes;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;
  bool get hasError => _errorMessage.isNotEmpty;

  StreamSubscription? _progressSubscription;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  void ignoreUpdate() {
    _updateIgnored = true;
    notifyListeners();
  }

  /// Compares semantic versions (e.g. "1.2.3" vs "1.2.4").
  /// Returns 1 if remote > local, 0 if equal, -1 if remote < local.
  int _compareSemanticVersions(String local, String remote) {
    List<int> localParts  = local.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    List<int> remoteParts = remote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (localParts.length < 3)  { localParts.add(0); }
    while (remoteParts.length < 3) { remoteParts.add(0); }
    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > localParts[i]) return 1;
      if (remoteParts[i] < localParts[i]) return -1;
    }
    return 0;
  }

  // ── Check for updates ─────────────────────────────────────────────────────────

  Future<void> checkForUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version;

      const githubApiUrl =
          'https://api.github.com/repos/Mukulmark42/CardVault-Updates/releases/latest';

      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'CardVault-App',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        String remoteVersion = data['tag_name'] as String? ?? '';
        if (remoteVersion.startsWith('v')) remoteVersion = remoteVersion.substring(1);

        final body  = data['body'] as String? ?? '';
        String apkAssetUrl = '';
        final assets = data['assets'] as List? ?? [];
        for (var asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            apkAssetUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }

        _remoteVersion = remoteVersion;
        _releaseNotes  = body;
        _apkUrl        = apkAssetUrl;

        if (remoteVersion.isNotEmpty && apkAssetUrl.isNotEmpty) {
          final cmp = _compareSemanticVersions(localVersion, remoteVersion);
          if (cmp == 1) {
            _isUpdateAvailable = true;
            _updateMessage = 'New version $remoteVersion is available!';
          } else {
            _isUpdateAvailable = false;
            _updateMessage = 'You are on the latest version.';
          }
        } else {
          _isUpdateAvailable = false;
          _updateMessage = 'No compatible update found.';
        }
        notifyListeners();
      } else {
        debugPrint('GitHub update check failed: ${response.statusCode}');
        _isUpdateAvailable = false;
        _updateMessage = 'Update server unavailable.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      _isUpdateAvailable = false;
      _updateMessage = 'Failed to check for updates.';
      notifyListeners();
    }
  }

  // ── Start download (via Android DownloadManager — survives screen-off) ───────

  Future<void> startUpdate(void Function() onInstallStart) async {
    if (_apkUrl.isEmpty || _isDownloading) return;

    _clearError();

    if (Platform.isAndroid) {
      // REQUEST_INSTALL_PACKAGES permission is always required
      var installStatus = await Permission.requestInstallPackages.status;
      if (!installStatus.isGranted) {
        installStatus = await Permission.requestInstallPackages.request();
        if (!installStatus.isGranted) {
          _errorMessage = "Please allow 'Install unknown apps' in Settings to update.";
          notifyListeners();
          return;
        }
      }
    }

    _isDownloading    = true;
    _downloadProgress = 0;
    _downloadStatus   = 'pending';
    _errorMessage     = '';
    notifyListeners();

    try {
      // Tell the native side to start downloading via DownloadManager
      await _methodChannel.invokeMethod('startDownload', {'url': _apkUrl});

      // Listen to progress events streamed from the native side
      _progressSubscription = _eventChannel
          .receiveBroadcastStream()
          .listen(
        (dynamic event) {
          final Map<String, dynamic> data = Map<String, dynamic>.from(event as Map);
          final status  = data['status'] as String? ?? 'unknown';
          final percent = (data['percent'] as num?)?.toDouble() ?? 0.0;

          _downloadProgress = percent;
          _downloadStatus   = status;

          switch (status) {
            case 'downloading':
            case 'pending':
            case 'paused':
              _isDownloading = true;
              break;

            case 'installing':
              _isDownloading     = false;
              _isUpdateAvailable = false;
              _errorMessage      = '';
              notifyListeners();
              onInstallStart();
              return;

            case 'done':
              // DownloadManager finished — native side will trigger the installer
              _isDownloading = false;
              break;

            case 'error':
              _isDownloading = false;
              _errorMessage  = 'Download failed. Please check your connection and try again.';
              break;
          }
          notifyListeners();
        },
        onError: (Object e) {
          debugPrint('OTA progress error: $e');
          _isDownloading = false;
          _errorMessage  = 'Download error: ${e.toString()}';
          notifyListeners();
        },
      );
    } on PlatformException catch (e) {
      debugPrint('Platform channel error: $e');
      _isDownloading = false;
      _errorMessage  = 'Failed to start download: ${e.message}';
      notifyListeners();
    } catch (e) {
      debugPrint('startUpdate error: $e');
      _isDownloading = false;
      _errorMessage  = 'Failed to start download: ${e.toString()}';
      notifyListeners();
    }
  }

  // ── Cancel ────────────────────────────────────────────────────────────────────

  void cancelUpdate() {
    _progressSubscription?.cancel();
    _progressSubscription = null;
    try {
      _methodChannel.invokeMethod('cancelDownload');
    } catch (_) {}
    _isDownloading    = false;
    _downloadProgress = 0;
    _downloadStatus   = '';
    _errorMessage     = '';
    notifyListeners();
  }

  // ── Retry ─────────────────────────────────────────────────────────────────────

  Future<void> retryUpdate(void Function() onInstallStart) async {
    _clearError();
    await startUpdate(onInstallStart);
  }
}
