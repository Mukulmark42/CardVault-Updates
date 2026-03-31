import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';

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

  Future<void> startUpdate(void Function() onInstallStart) async {
    if (_apkUrl.isEmpty || _isDownloading) return;

    // Request necessary permissions for OTA update
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      
      // On Android 13+, we might need to check for specific media permissions or just REQUEST_INSTALL_PACKAGES
      // but ota_update usually requires storage if it downloads to external.
      // However, if it downloads to internal, it might just need the Install permission.
      
      var installStatus = await Permission.requestInstallPackages.status;
      if (!installStatus.isGranted) {
        installStatus = await Permission.requestInstallPackages.request();
      }

      // If storage is still not granted, we might still try, but let's inform the user if possible
      // or check for manageExternalStorage on newer versions if it fails.
    }

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
          } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
            _isDownloading = false;
            debugPrint("OTA Update Error: Permission not granted");
            notifyListeners();
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
