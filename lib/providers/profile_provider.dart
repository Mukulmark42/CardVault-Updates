import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/profile_model.dart';
import '../services/backup_service.dart';

class ProfileProvider extends ChangeNotifier {
  List<ProfileModel> _profiles = [];
  ProfileModel? _activeProfile;
  final BackupService _backupService = BackupService();

  List<ProfileModel> get profiles => _profiles;
  ProfileModel? get activeProfile => _activeProfile;

  ProfileProvider() {
    _load();
  }

  Future<void> _load() async {
    await refresh();
  }

  Future<void> refresh() async {
    try {
      _profiles = await DatabaseHelper.instance.getProfiles();
      // Active = default profile, or first profile if none marked default
      _activeProfile = _profiles.isEmpty
          ? null
          : _profiles.firstWhere(
              (p) => p.isDefault,
              orElse: () => _profiles.first,
            );
      notifyListeners();
    } catch (e) {
      debugPrint('ProfileProvider: refresh error: $e');
    }
  }

  Future<void> addProfile(ProfileModel profile) async {
    // First profile is automatically set as default
    final isFirst = _profiles.isEmpty;
    final toInsert = profile.copyWith(isDefault: isFirst ? true : profile.isDefault);
    await DatabaseHelper.instance.insertProfile(toInsert);
    await refresh();
    _triggerCloudSync();
  }

  Future<void> updateProfile(ProfileModel profile) async {
    await DatabaseHelper.instance.updateProfile(profile);
    await refresh();
    _triggerCloudSync();
  }

  Future<void> deleteProfile(int id) async {
    await DatabaseHelper.instance.deleteProfile(id);
    await refresh();
    _triggerCloudSync();
  }

  Future<void> setDefault(int id) async {
    await DatabaseHelper.instance.setDefaultProfile(id);
    await refresh();
    _triggerCloudSync();
  }

  void _triggerCloudSync() {
    _backupService.onlineBackup().catchError((e) {
      debugPrint("Failed auto-sync for profiles: $e");
    });
  }

  /// Returns the best-matching profile for a given card holder name.
  /// Returns null if no profile scores above 0.5.
  ProfileModel? bestMatchForHolder(String holderName) {
    if (_profiles.isEmpty) return null;
    ProfileModel? best;
    double bestScore = 0.0;
    for (final p in _profiles) {
      final score = p.matchScore(holderName);
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }
}
