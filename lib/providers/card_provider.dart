import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/history_service.dart';
import '../services/gmail_service.dart';

class CardProvider extends ChangeNotifier {
  List<CardModel> _cards = [];
  List<CardModel> get cards => _cards;

  List<TransactionModel> _transactions = [];
  List<TransactionModel> get transactions => _transactions;

  final BackupService _backupService = BackupService();
  final HistoryService _historyService = HistoryService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

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
      await refreshTransactions();

      // If local vault is empty, attempt to restore from cloud (New Device Logic)
      if (_cards.isEmpty) {
        debugPrint("Local vault empty, attempting automatic cloud restore...");
        await _backupService.onlineRestore();
        await refreshCards();
        await refreshTransactions();
      }

      // ✅ Local notifications are now handled via Firebase Cloud Messaging
      // No local scheduling needed.
    } catch (e) {
      debugPrint("Vault initialization error: $e");
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> refreshCards() async {
    try {
      List<CardModel> allCards = await DatabaseHelper.instance.getCards();

      // Check for expired due dates and roll them automatically
      bool needsUpdate = false;
      List<CardModel> processedCards = [];

      for (var card in allCards) {
        if (card.dueDate != null) {
          DateTime dueDate = DateTime.parse(card.dueDate!);
          // If the due date passed more than 1 day ago, roll it —
          // BUT only if the user has NOT manually set the due date.
          final isOverdue = dueDate.isBefore(
            DateTime.now().subtract(const Duration(days: 1)),
          );
          if (isOverdue && !card.isManualDueDate) {
            // SAVE HISTORY BEFORE ROLLING
            await _historyService.saveBillHistory(card);

            CardModel rolled = card.rollToNextMonth();
            await DatabaseHelper.instance.updateCard(rolled);
            processedCards.add(rolled);
            needsUpdate = true;
          } else {
            processedCards.add(card);
          }
        } else {
          processedCards.add(card);
        }
      }

      _cards = processedCards;
      if (needsUpdate) {
        _triggerCloudSync();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing cards: $e");
    }
  }

  Future<void> refreshTransactions() async {
    try {
      _transactions = await DatabaseHelper.instance.getTransactions();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing transactions: $e");
    }
  }

  /// Manually triggers a Gmail sync for all cards and updates the UI
  Future<void> syncWithGmail() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      debugPrint("Starting manual Gmail sync...");
      await GmailService.instance.syncAllLinkedAccounts(isManual: true);
      await refreshCards(); // Pull the updated due dates and spent amounts from DB
      await refreshTransactions();
      debugPrint("Gmail sync completed successfully.");
    } catch (e) {
      debugPrint("Error during manual Gmail sync: $e");
      rethrow; // Re-throw so the UI can catch and show an error if needed
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Delinks the email from a specific card
  Future<void> delinkEmail(CardModel card) async {
    // ✅ FIX: Use the function callback pattern to explicitly set to null
    final updatedCard = card.copyWith(linkedEmail: () => null);
    await DatabaseHelper.instance.updateCard(updatedCard);
    await refreshCards();
    _triggerCloudSync();
  }

  bool isCardDuplicate(String cardNumber, {int? excludeId}) {
    final rawNumber = cardNumber.replaceAll(' ', '');
    return _cards.any((c) {
      final cNumber = c.number.replaceAll(' ', '');
      return cNumber == rawNumber && (excludeId == null || c.id != excludeId);
    });
  }

  Future<void> addCard(CardModel card) async {
    await DatabaseHelper.instance.insertCard(card);
    await refreshCards();
    _triggerCloudSync();
  }

  Future<void> updateCard(CardModel card) async {
    CardModel cardToUpdate = card;

    // If marking as paid, roll to next month automatically
    if (card.isPaid && card.dueDate != null) {
      // SAVE HISTORY BEFORE ROLLING
      await _historyService.saveBillHistory(card);
      cardToUpdate = card.rollToNextMonth();
    }

    await DatabaseHelper.instance.updateCard(cardToUpdate);
    await refreshCards();
    _triggerCloudSync();
  }

  Future<void> deleteCard(int id) async {
    await DatabaseHelper.instance.deleteCard(id);
    await refreshCards();
    _triggerCloudSync();
    await NotificationService().cancelNotification(id);
  }

  Future<void> clearAllCards() async {
    // Store IDs before deletion
    final ids = _cards.where((c) => c.id != null).map((c) => c.id!).toList();

    await DatabaseHelper.instance.clearAllCards();
    await refreshCards();
    await refreshTransactions();
    _triggerCloudSync();

    // Cancel notifications using stored IDs
    for (final id in ids) {
      await NotificationService().cancelNotification(id);
    }
  }

  Future<void> _triggerCloudSync() async {
    try {
      _backupService
          .onlineBackup()
          .then((_) {
            debugPrint("Instant Cloud Sync Successful");
          })
          .catchError((e) {
            debugPrint("Instant Cloud Sync Background Error: $e");
          });
    } catch (e) {
      debugPrint("Cloud Sync Trigger Failed: $e");
    }
  }
}
