import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';

class CardProvider extends ChangeNotifier {
  List<CardModel> _cards = [];
  List<CardModel> get cards => _cards;

  final BackupService _backupService = BackupService();
  bool _isInitializing = false;
  bool get isInitializing => _isInitializing;

  CardProvider();

  // Called during app startup/login to ensure data is present
  Future<void> initializeVault() async {
    if (_isInitializing) return;
    _isInitializing = true;
    notifyListeners();

    try {
      await refreshCards();
      
      // If local vault is empty, attempt to restore from cloud (New Device Logic)
      if (_cards.isEmpty) {
        debugPrint("Local vault empty, attempting automatic cloud restore...");
        await _backupService.onlineRestore();
        await refreshCards();
      }
      
      // Schedule all notifications for the loaded cards
      await NotificationService().scheduleAllPendingNotifications();
      
    } catch (e) {
      debugPrint("Vault initialization error: $e");
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> refreshCards() async {
    try {
      _cards = await DatabaseHelper.instance.getCards();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing cards: $e");
    }
  }

  bool isCardDuplicate(String cardNumber, {int? excludeId}) {
    final rawNumber = cardNumber.replaceAll(' ', '');
    return _cards.any((c) => c.number.replaceAll(' ', '') == rawNumber && c.id != excludeId);
  }

  Future<void> addCard(CardModel card) async {
    await DatabaseHelper.instance.insertCard(card);
    await refreshCards();
    _triggerCloudSync();
    // Schedule notification for the new card
    final newCard = _cards.firstWhere((c) => c.number == card.number);
    await NotificationService().scheduleDueDateNotification(newCard);
  }

  Future<void> updateCard(CardModel card) async {
    await DatabaseHelper.instance.updateCard(card);
    await refreshCards();
    _triggerCloudSync();
    
    // Update notification
    if (card.isPaid) {
      await NotificationService().cancelNotification(card.id ?? 0);
    } else {
      await NotificationService().scheduleDueDateNotification(card);
    }
  }

  Future<void> deleteCard(int id) async {
    await DatabaseHelper.instance.deleteCard(id);
    await refreshCards();
    _triggerCloudSync();
    await NotificationService().cancelNotification(id);
  }

  Future<void> clearAllCards() async {
    await DatabaseHelper.instance.clearAllCards();
    await refreshCards();
    _triggerCloudSync();
    // Cancel all notifications (simplified by ID tracking or just clear all if plugin allows)
    for (var card in _cards) {
      if (card.id != null) await NotificationService().cancelNotification(card.id!);
    }
  }

  Future<void> _triggerCloudSync() async {
    try {
      _backupService.onlineBackup().then((_) {
        debugPrint("Instant Cloud Sync Successful");
      }).catchError((e) {
        debugPrint("Instant Cloud Sync Background Error: $e");
      });
    } catch (e) {
      debugPrint("Cloud Sync Trigger Failed: $e");
    }
  }
}
