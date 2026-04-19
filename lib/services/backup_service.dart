import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../models/profile_model.dart';

/// BackupService — simple cloud & offline backup.
///
/// DESIGN PRINCIPLE:
///   • getCards() always returns DECRYPTED (plaintext) card data.
///   • Firestore stores plaintext card data — device-specific AES keys
///     must NEVER be used for cloud storage (cross-device restore would fail).
///   • Local SQLite stores number/CVV encrypted via EncryptionService (device key).
///   • For true E2EE cloud storage use BackupServiceEnhanced with a user password.
class BackupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ---------------------------------------------------------------------------
  // Online Backup (Firestore)
  // ---------------------------------------------------------------------------

  Future<void> onlineBackup() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();
    final profiles = await DatabaseHelper.instance.getProfiles();

    WriteBatch batch = _firestore.batch();
    int opCount = 0;

    // Helper to flush batch when approaching the 500-op limit
    Future<void> maybeFlush() async {
      if (opCount >= 499) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    // ── 1. Cards ────────────────────────────────────────────────────────────
    final userCardsRef =
        _firestore.collection('users').doc(user.uid).collection('cards');

    // Delete stale cloud docs
    final existingCards = await userCardsRef.get();
    for (final doc in existingCards.docs) {
      batch.delete(doc.reference);
      opCount++;
      await maybeFlush();
    }

    for (final card in cards) {
      // getCards() returns plaintext (already decrypted from SQLite).
      // Build the map and strip device-encrypted artefacts that may have
      // been written by a previous (buggy) version of this service.
      final cardMap = card.toMap();
      // Remove any stale enc_version metadata
      cardMap.remove('enc_version');
      // Remove any stale _enc fields (left over from buggy backup)
      cardMap.removeWhere((k, _) => k.endsWith('_enc'));

      final docRef = userCardsRef.doc(card.id.toString());
      batch.set(docRef, cardMap);
      opCount++;
      await maybeFlush();
    }

    // ── 2. Transactions ──────────────────────────────────────────────────────
    final userTxsRef =
        _firestore.collection('users').doc(user.uid).collection('transactions');

    final existingTxs = await userTxsRef.get();
    for (final doc in existingTxs.docs) {
      batch.delete(doc.reference);
      opCount++;
      await maybeFlush();
    }

    for (final tx in transactions) {
      // Use a stable, content-derived Firestore ID to avoid duplicates.
      final txId =
          '${tx.vendor}_${tx.amount}_${tx.date.millisecondsSinceEpoch}'
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final txMap = tx.toMap()..remove('id'); // ID is local-only
      batch.set(userTxsRef.doc(txId), txMap);
      opCount++;
      await maybeFlush();
    }

    // ── 3. Profiles ──────────────────────────────────────────────────────────
    final userProfilesRef =
        _firestore.collection('users').doc(user.uid).collection('profiles');

    final existingProfiles = await userProfilesRef.get();
    for (final doc in existingProfiles.docs) {
      batch.delete(doc.reference);
      opCount++;
      await maybeFlush();
    }

    for (final profile in profiles) {
      final docRef = userProfilesRef.doc(profile.id.toString());
      batch.set(docRef, profile.toMap()..remove('id'));
      opCount++;
      await maybeFlush();
    }

    if (opCount > 0) await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Online Restore (Firestore → local SQLite)
  // ---------------------------------------------------------------------------

  Future<void> onlineRestore() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // ── 0. Profiles ──────────────────────────────────────────────────────────
    final profileSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profiles')
        .get();

    final Map<int, int> profileIdMapping = {};
    if (profileSnapshot.docs.isNotEmpty) {
      await DatabaseHelper.instance.clearAllProfiles();
      for (final doc in profileSnapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final oldId = data['id'] as int?;
        data.remove('id'); // let SQLite assign a new local ID

        final profile = ProfileModel.fromMap(data);
        profile.id = null;
        final newId = await DatabaseHelper.instance.insertProfile(profile);
        if (oldId != null) profileIdMapping[oldId] = newId;
      }
    }

    // ── 1. Cards ────────────────────────────────────────────────────────────
    final cardSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cards')
        .get();

    if (cardSnapshot.docs.isEmpty) return;

    await DatabaseHelper.instance.clearAllCards();
    final Map<int, int> idMapping = {};

    for (final doc in cardSnapshot.docs) {
      final rawData = Map<String, dynamic>.from(doc.data());
      final oldId = rawData['id'] as int?;

      // ── Sanitise stale enc_version data written by the buggy backup ──
      // If a previous (broken) version stored `number_enc` instead of `number`,
      // try to recover the plaintext. If decryption fails (different device key
      // or corrupted data), fall back to an empty string so the card is still
      // usable — the user can edit it to add the correct value.
      rawData.remove('enc_version');
      const sensitiveFields = [
        'number', 'cvv', 'holder', 'expiry', 'bank', 'variant'
      ];
      for (final field in sensitiveFields) {
        final encKey = '${field}_enc';
        if (!rawData.containsKey(field) && rawData.containsKey(encKey)) {
          // Attempt to decrypt with the local key (works if same device).
          final encrypted = rawData[encKey] as String? ?? '';
          final decrypted =
              await DatabaseHelper.instance.tryDecryptField(encrypted);
          // If decryption succeeded, use it; otherwise fall back to empty.
          rawData[field] = decrypted ?? '';
          debugPrint(
              '[Restore] field=$field recovered=${decrypted != null}');
        }
        rawData.remove('${field}_enc');
      }

      final card = CardModel.fromMap(rawData);
      card.id = null; // let SQLite AUTOINCREMENT assign a new ID

      // Re-map profile ID to the new local ID after profile restore
      if (card.profileId != null &&
          profileIdMapping.containsKey(card.profileId)) {
        card.profileId = profileIdMapping[card.profileId];
      }

      final newId = await DatabaseHelper.instance.insertCard(card);
      if (oldId != null) idMapping[oldId] = newId;
    }

    // ── 2. Transactions ──────────────────────────────────────────────────────
    final txSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .get();

    for (final doc in txSnapshot.docs) {
      final tx = TransactionModel.fromMap(doc.data());
      if (idMapping.containsKey(tx.cardId)) {
        tx.cardId = idMapping[tx.cardId]!;
        // Raw insert: card.spent already contains the correct total.
        // ConflictAlgorithm.ignore silently skips duplicates.
        await DatabaseHelper.instance.insertTransactionRaw(tx);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Offline Backup (JSON file export)
  // ---------------------------------------------------------------------------

  Future<void> offlineBackup() async {
    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();

    final jsonData = jsonEncode({
      'backup_version': 2,
      'timestamp': DateTime.now().toIso8601String(),
      'cards': cards.map((c) {
        final m = c.toMap();
        m.remove('id'); // local ID is meaningless on another device
        return m;
      }).toList(),
      'transactions': transactions.map((t) {
        final m = t.toMap();
        m.remove('id');
        return m;
      }).toList(),
    });

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/cardvault_backup.json');
    await file.writeAsString(jsonData);
    await Share.shareXFiles([XFile(file.path)], text: 'CardVault Backup');
  }

  // ---------------------------------------------------------------------------
  // Offline Restore (JSON file import)
  // ---------------------------------------------------------------------------

  Future<void> offlineRestore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final dynamic decoded = jsonDecode(content);
    if (decoded is! Map) return;

    await DatabaseHelper.instance.clearAllCards();
    final Map<int, int> idMapping = {};

    if (decoded.containsKey('cards')) {
      for (final item in decoded['cards'] as List<dynamic>) {
        final cardData = Map<String, dynamic>.from(item as Map);
        final oldId = cardData['id'] as int?;
        cardData.remove('id');
        final card = CardModel.fromMap(cardData);
        card.id = null;
        final newId = await DatabaseHelper.instance.insertCard(card);
        if (oldId != null) idMapping[oldId] = newId;
      }
    }

    if (decoded.containsKey('transactions')) {
      for (final item in decoded['transactions'] as List<dynamic>) {
        final tx = TransactionModel.fromMap(Map<String, dynamic>.from(item as Map));
        if (idMapping.containsKey(tx.cardId)) {
          tx.cardId = idMapping[tx.cardId]!;
          await DatabaseHelper.instance.insertTransactionRaw(tx);
        }
      }
    }
  }
}
