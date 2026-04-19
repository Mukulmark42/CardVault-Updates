import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateProvider extends ChangeNotifier {
  bool _isUpdateAvailable = false;
  bool _updateIgnored = false;
  bool get isUpdateAvailable => _isUpdateAvailable && !_updateIgnored;

  String _updateMessage = "";
  String get updateMessage => _updateMessage;

  String _apkUrl = "";
  String get apkUrl => _apkUrl;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  String _remoteVersion = "";
  String get remoteVersion => _remoteVersion;

  String _releaseNotes = "";
  String get releaseNotes => _releaseNotes;

  // Error handling
  String _errorMessage = "";
  String get errorMessage => _errorMessage;
  bool get hasError => _errorMessage.isNotEmpty;

  // Clear error
  void _clearError() {
    _errorMessage = "";
    notifyListeners();
  }

  // Compare semantic versions (e.g., "1.2.3" vs "1.2.4")
  // Returns: 1 if remote > local, 0 if equal, -1 if remote < local
  int _compareSemanticVersions(String local, String remote) {
    List<int> localParts = local
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    List<int> remoteParts = remote
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();

    // Ensure both have at least 3 parts (major.minor.patch)
    while (localParts.length < 3) {
      localParts.add(0);
    }
    while (remoteParts.length < 3) {
      remoteParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (remoteParts[i] > localParts[i]) return 1;
      if (remoteParts[i] < localParts[i]) return -1;
    }
    return 0;
  }

  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final osVersion = Platform.operatingSystemVersion;
      // Try to find API level first: "Android 13 (API 33)"
      final apiMatch = RegExp(r'API (\d+)').firstMatch(osVersion);
      if (apiMatch != null) {
        return int.tryParse(apiMatch.group(1)!) ?? 0;
      }
      // Fallback to Android version: "Android 12"
      final androidMatch = RegExp(r'Android (\d+)').firstMatch(osVersion);
      if (androidMatch != null) {
        int ver = int.tryParse(androidMatch.group(1)!) ?? 0;
        if (ver >= 10) return 29; // API 29 is Android 10
        if (ver == 9) return 28;
      }
    } catch (e) {
      debugPrint("Failed to get Android version: $e");
    }
    return 30; // Default to modern API if detection fails
  }

  void ignoreUpdate() {
    _updateIgnored = true;
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersion = info.version; // e.g., "2.0.0"

      // GitHub API URL for latest release
      const githubApiUrl =
          'https://api.github.com/repos/Mukulmark42/CardVault-Updates/releases/latest';

      // Fetch version info from GitHub
      final response = await http.get(
        Uri.parse(githubApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'CardVault-App', // GitHub API requires a User-Agent
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // GitHub uses 'tag_name' for version, often with 'v' prefix (e.g., "v2.1.0")
        String remoteVersion = data['tag_name'] as String? ?? '';
        if (remoteVersion.startsWith('v')) {
          remoteVersion = remoteVersion.substring(1);
        }

        final body = data['body'] as String? ?? '';

        // Find APK in assets
        String apkAssetUrl = "";
        final assets = data['assets'] as List? ?? [];
        for (var asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            apkAssetUrl = asset['browser_download_url'] as String? ?? '';
            break;
          }
        }

        _remoteVersion = remoteVersion;
        _releaseNotes = body;
        _apkUrl = apkAssetUrl;

        // Compare versions
        if (remoteVersion.isNotEmpty && apkAssetUrl.isNotEmpty) {
          int comparison = _compareSemanticVersions(
            localVersion,
            remoteVersion,
          );
          if (comparison == 1) {
            _isUpdateAvailable = true;
            _updateMessage = "New version $remoteVersion is available!";
          } else {
            _isUpdateAvailable = false;
            _updateMessage = "You are on the latest version.";
          }
        } else {
          _isUpdateAvailable = false;
          _updateMessage = "No compatible update found.";
        }
        notifyListeners();
      } else {
        debugPrint("GitHub Update check failed: ${response.statusCode}");
        _isUpdateAvailable = false;
        _updateMessage = "Update server unavailable.";
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
      _isUpdateAvailable = false;
      _updateMessage = "Failed to check for updates.";
      notifyListeners();
    }
  }

  // Subscription for OTA update to allow cancellation
  StreamSubscription? _otaSubscription;

  Future<void> startUpdate(void Function() onInstallStart) async {
    if (_apkUrl.isEmpty || _isDownloading) return;

    // Clear any previous error
    _clearError();

    // Request necessary permissions for OTA update
    if (Platform.isAndroid) {
      final androidVersion = await _getAndroidVersion();
      
      // Storage permission is ONLY needed for Android 9 (API 28) and below.
      // Android 10+ (API 29+) uses scoped storage/internal app dirs which don't need it.
      if (androidVersion < 29) {
        var storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          storageStatus = await Permission.storage.request();
          if (!storageStatus.isGranted) {
            _errorMessage = "Storage permission is required to download the update.";
            notifyListeners();
            return;
          }
        }
      }

      // Install unknown apps permission (always needed)
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

    _isDownloading = true;
    _downloadProgress = 0;
    _errorMessage = "";
    notifyListeners();

    try {
      // Removing destinationFilename allows the plugin to use the safest internal path
      _otaSubscription = OtaUpdate()
          .execute(_apkUrl)
          .listen(
            (OtaEvent event) {
              _downloadProgress = double.tryParse(event.value ?? "0") ?? 0;
              notifyListeners();

              if (event.status == OtaStatus.INSTALLING) {
                _isDownloading = false;
                _isUpdateAvailable = false;
                _errorMessage = "";
                notifyListeners();
                onInstallStart();
              } else if (event.status ==
                  OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
                _isDownloading = false;
                _errorMessage =
                    "Permission not granted. Please allow storage and install permissions.";
                notifyListeners();
              } else if (event.status == OtaStatus.INTERNAL_ERROR) {
                _isDownloading = false;
                _errorMessage =
                    "Internal error during update. Please check your internet connection.";
                notifyListeners();
              } else if (event.status == OtaStatus.DOWNLOADING) {
                // Progress already updated
              }
            },
            onError: (e) {
              debugPrint("OTA Update Error: $e");
              _isDownloading = false;
              _errorMessage = "Download failed: ${e.toString()}";
              notifyListeners();
            },
            onDone: () {
              // Stream completed without error
              if (!_isDownloading && _downloadProgress < 100) {
                // Download didn't complete successfully
                _errorMessage = "Download was interrupted.";
                notifyListeners();
              }
            },
          );
    } catch (e) {
      debugPrint("Failed to execute update: $e");
      _isDownloading = false;
      _errorMessage = "Failed to start update: ${e.toString()}";
      notifyListeners();
    }
  }

  // Cancel ongoing update
  void cancelUpdate() {
    _otaSubscription?.cancel();
    _isDownloading = false;
    _downloadProgress = 0;
    _errorMessage =
        ""; // Clear error on cancellation - it's user action, not an error
    notifyListeners();
  }

  // Retry update after error
  Future<void> retryUpdate(void Function() onInstallStart) async {
    _clearError();
    await startUpdate(onInstallStart);
  }
}
