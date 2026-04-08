import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../models/profile_model.dart';

class BackupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- Online Backup (Firestore) ---

  Future<void> onlineBackup() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();
    final profiles = await DatabaseHelper.instance.getProfiles();
    
    // Batch limit is 500 operations
    WriteBatch batch = _firestore.batch();
    int opCount = 0;

    // 1. Clear and Backup Cards
    final userCardsRef = _firestore.collection('users').doc(user.uid).collection('cards');
    final existingCards = await userCardsRef.get();
    for (var doc in existingCards.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    for (var card in cards) {
      final docRef = userCardsRef.doc(card.id.toString());
      batch.set(docRef, card.toMap());
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    // 2. Clear and Backup Transactions
    final userTxsRef = _firestore.collection('users').doc(user.uid).collection('transactions');
    final existingTxs = await userTxsRef.get();
    for (var doc in existingTxs.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    for (var tx in transactions) {
      // Create a stable ID for Firestore
      final String txId = "${tx.vendor}_${tx.amount}_${tx.date.millisecondsSinceEpoch}"
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final docRef = userTxsRef.doc(txId);
      batch.set(docRef, tx.toMap());
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    // 3. Clear and Backup Profiles
    final userProfilesRef = _firestore.collection('users').doc(user.uid).collection('profiles');
    final existingProfiles = await userProfilesRef.get();
    for (var doc in existingProfiles.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    for (var profile in profiles) {
      final docRef = userProfilesRef.doc(profile.id.toString());
      batch.set(docRef, profile.toMap());
      opCount++;
      if (opCount >= 500) { await batch.commit(); batch = _firestore.batch(); opCount = 0; }
    }

    if (opCount > 0) {
      await batch.commit();
    }
  }

  Future<void> onlineRestore() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    // 0. Restore Profiles
    final profileSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profiles')
        .get();

    Map<int, int> profileIdMapping = {};
    if (profileSnapshot.docs.isNotEmpty) {
      await DatabaseHelper.instance.clearAllProfiles();
      for (var doc in profileSnapshot.docs) {
        final profileData = doc.data();
        final oldId = profileData['id'] as int?;
        
        final profile = ProfileModel.fromMap(profileData);
        profile.id = null;
        
        int newId = await DatabaseHelper.instance.insertProfile(profile);
        if (oldId != null) {
          profileIdMapping[oldId] = newId;
        }
      }
    }

    // 1. Restore Cards
    final cardSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cards')
        .get();

    if (cardSnapshot.docs.isEmpty) return;

    // Clear local data before restore
    await DatabaseHelper.instance.clearAllCards();
    
    Map<int, int> idMapping = {};

    for (var doc in cardSnapshot.docs) {
      final cardData = doc.data();
      final oldId = cardData['id'] as int?;
      
      final card = CardModel.fromMap(cardData);
      card.id = null; // Reset to let SQLite auto-increment
      
      // Update profileId if we mapped it to a new local ID
      if (card.profileId != null && profileIdMapping.containsKey(card.profileId)) {
        card.profileId = profileIdMapping[card.profileId];
      }
      
      int newId = await DatabaseHelper.instance.insertCard(card);
      if (oldId != null) {
        idMapping[oldId] = newId;
      }
    }

    // 2. Restore Transactions
    final txSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .get();
    
    for (var doc in txSnapshot.docs) {
      final txData = doc.data();
      final tx = TransactionModel.fromMap(txData);
      
      // Map old card ID to new card ID on this device
      if (idMapping.containsKey(tx.cardId)) {
        tx.cardId = idMapping[tx.cardId]!;
        
        // We use a raw insert to avoid the "spent" amount incrementing twice
        // because the CardModel already came with the correct "spent" value.
        await _insertTransactionRaw(tx);
      }
    }
  }
  
  /// Helper to insert transaction without affecting card spent amount (used during restore)
  Future<void> _insertTransactionRaw(TransactionModel tx) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('transactions', tx.toMap());
  }

  // --- Offline Backup (Local File) ---

  Future<void> offlineBackup() async {
    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();
    
    final jsonData = jsonEncode({
      'cards': cards.map((e) => e.toMap()).toList(),
      'transactions': transactions.map((e) => e.toMap()).toList(),
    });
    
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/cardvault_backup.json');
    await file.writeAsString(jsonData);

    await Share.shareXFiles([XFile(file.path)], text: 'CardVault Backup');
  }

  Future<void> offlineRestore() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      dynamic decoded = jsonDecode(content);

      await DatabaseHelper.instance.clearAllCards();
      Map<int, int> idMapping = {};

      if (decoded is List) {
        // Legacy format: just cards
        for (var item in decoded) {
          await DatabaseHelper.instance.insertCard(CardModel.fromMap(item));
        }
      } else if (decoded is Map) {
        // New format: cards and transactions
        if (decoded.containsKey('cards')) {
          List<dynamic> cardList = decoded['cards'];
          for (var item in cardList) {
            final cardData = Map<String, dynamic>.from(item);
            final oldId = cardData['id'] as int?;
            final card = CardModel.fromMap(cardData);
            card.id = null;
            int newId = await DatabaseHelper.instance.insertCard(card);
            if (oldId != null) idMapping[oldId] = newId;
          }
        }

        if (decoded.containsKey('transactions')) {
          List<dynamic> txList = decoded['transactions'];
          for (var item in txList) {
            final tx = TransactionModel.fromMap(Map<String, dynamic>.from(item));
            if (idMapping.containsKey(tx.cardId)) {
              tx.cardId = idMapping[tx.cardId]!;
              await _insertTransactionRaw(tx);
            }
          }
        }
      }
    }
  }
}
