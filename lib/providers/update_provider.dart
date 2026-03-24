import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class UpdateProvider extends ChangeNotifier {
  bool _isUpdateAvailable = false;
  bool get isUpdateAvailable => _isUpdateAvailable;

  String _updateMessage = "";
  String get updateMessage => _updateMessage;

  String _apkUrl = "";
  String get apkUrl => _apkUrl;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  Future<void> checkForUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localVersionCode = int.tryParse(info.buildNumber) ?? 0;

      final response = await http.get(
        Uri.parse("https://raw.githubusercontent.com/Mukulmark42/CardVault-Updates/main/version.json"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        int remoteVersionCode = data["version"];

        if (remoteVersionCode > localVersionCode) {
          _isUpdateAvailable = true;
          _updateMessage = data["message"];
          _apkUrl = data["apk_url"];
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  void startUpdate(void Function() onInstallStart) {
    if (_apkUrl.isEmpty || _isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0;
    notifyListeners();

    try {
      OtaUpdate().execute(_apkUrl, destinationFilename: 'cardvault_update.apk').listen(
        (OtaEvent event) {
          _downloadProgress = double.tryParse(event.value ?? "0") ?? 0;
          notifyListeners();
          
          if (event.status == OtaStatus.INSTALLING) {
            _isDownloading = false;
            _isUpdateAvailable = false;
            notifyListeners();
            onInstallStart();
          }
        },
        onError: (e) {
          debugPrint("OTA Update Error: $e");
          _isDownloading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint("Failed to execute update: $e");
      _isDownloading = false;
      notifyListeners();
    }
  }
}
