import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import '../database/database_helper.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../models/profile_model.dart';
import '../services/enhanced_encryption_service.dart';

/// Enhanced backup service with end-to-end encryption for Firebase
class BackupServiceEnhanced {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- User Encryption Setup ---

  /// Setup user encryption with password for cross-device compatibility
  /// Returns the salt that should be stored in Firebase user document
  Future<String> setupUserEncryption(String password) async {
    // Generate new salt
    final random = encrypt.Key.fromSecureRandom(16);
    final salt = random.base64;

    await EnhancedEncryptionService.instance.setupUserEncryptionKey(
      password,
      salt: salt,
    );
    return salt;
  }

  /// Restore user encryption from stored salt
  Future<void> restoreUserEncryption(String password, String salt) async {
    await EnhancedEncryptionService.instance.setupUserEncryptionKey(
      password,
      salt: salt,
    );
  }

  /// Check if user encryption is ready
  bool isUserEncryptionReady() {
    return EnhancedEncryptionService.instance.isUserEncryptionReady();
  }

  // --- Encrypted Firebase Backup ---

  /// Encrypt card data for Firebase storage
  Future<Map<String, dynamic>> _encryptCardForFirebase(CardModel card) async {
    final cardMap = card.toMap();

    // Encrypt all sensitive fields
    final encryptedFields = {};

    try {
      // Encrypt each sensitive field individually
      final fieldsToEncrypt = [
        'number',
        'cvv',
        'holder',
        'expiry',
        'bank',
        'variant',
        'linked_email',
      ];

      for (final field in fieldsToEncrypt) {
        if (cardMap[field] != null && cardMap[field] is String) {
          final value = cardMap[field] as String;
          if (value.isNotEmpty) {
            final encrypted = await EnhancedEncryptionService.instance
                .encryptForFirebase(value);
            encryptedFields['${field}_encrypted'] = encrypted;
            // Remove plaintext field
            cardMap.remove(field);
          }
        }
      }

      // Add non-sensitive fields as plaintext for querying
      final safeCardData = {
        'id': cardMap['id'],
        'credit_limit': cardMap['credit_limit'],
        'spent': cardMap['spent'],
        'due_date': cardMap['due_date'],
        'is_paid': cardMap['is_paid'],
        'last4':
            cardMap['last4'] ??
            (card.number.length >= 4
                ? card.number.substring(card.number.length - 4)
                : card.number),
        'is_manual_due_date': cardMap['is_manual_due_date'],
        'profile_id': cardMap['profile_id'],
        'encrypted_fields': encryptedFields,
        'encryption_version': '2', // Version 2: field-level encryption
        'created_at': FieldValue.serverTimestamp(),
      };

      return safeCardData;
    } catch (e) {
      print("Card encryption error: $e");
      // Fallback to storing without encryption (shouldn't happen)
      return cardMap;
    }
  }

  /// Decrypt card data from Firebase
  Future<CardModel> _decryptCardFromFirebase(
    Map<String, dynamic> firebaseData,
  ) async {
    final version = firebaseData['encryption_version'] ?? '1';
    final cardMap = Map<String, dynamic>.from(firebaseData);

    if (version == '2') {
      // New format with field-level encryption
      final encryptedFields =
          firebaseData['encrypted_fields'] as Map<String, dynamic>? ?? {};

      // Decrypt each encrypted field
      for (final entry in encryptedFields.entries) {
        final fieldName = entry.key.replaceFirst('_encrypted', '');
        final encryptedData = entry.value as Map<String, dynamic>;

        try {
          final decrypted = await EnhancedEncryptionService.instance
              .decryptFromFirebase(encryptedData);
          cardMap[fieldName] = decrypted;
        } catch (e) {
          print("Failed to decrypt field $fieldName: $e");
          cardMap[fieldName] = '';
        }
      }

      // Remove encryption metadata
      cardMap.remove('encrypted_fields');
      cardMap.remove('encryption_version');
      cardMap.remove('created_at');
    }
    // Version 1: plaintext (no decryption needed)

    return CardModel.fromMap(cardMap);
  }

  /// Encrypt transaction for Firebase
  Future<Map<String, dynamic>> _encryptTransactionForFirebase(
    TransactionModel tx,
  ) async {
    final txMap = tx.toMap();

    try {
      final encryptedVendor = await EnhancedEncryptionService.instance
          .encryptForFirebase(tx.vendor);
      final encryptedSnippet =
          tx.rawSnippet != null && tx.rawSnippet!.isNotEmpty
          ? await EnhancedEncryptionService.instance.encryptForFirebase(
              tx.rawSnippet!,
            )
          : null;

      return {
        'id': txMap['id'],
        'card_id': txMap['card_id'],
        'bank': txMap['bank'],
        'vendor_encrypted': encryptedVendor,
        'amount': txMap['amount'],
        'date': txMap['date'],
        'category': txMap['category'],
        'raw_snippet_encrypted': encryptedSnippet,
        'encryption_version': '2',
        'created_at': FieldValue.serverTimestamp(),
      };
    } catch (e) {
      print("Transaction encryption error: $e");
      return txMap;
    }
  }

  /// Decrypt transaction from Firebase
  Future<TransactionModel> _decryptTransactionFromFirebase(
    Map<String, dynamic> firebaseData,
  ) async {
    final version = firebaseData['encryption_version'] ?? '1';
    final txMap = Map<String, dynamic>.from(firebaseData);

    if (version == '2') {
      try {
        final vendorEncrypted =
            firebaseData['vendor_encrypted'] as Map<String, dynamic>;
        txMap['vendor'] = await EnhancedEncryptionService.instance
            .decryptFromFirebase(vendorEncrypted);

        if (firebaseData['raw_snippet_encrypted'] != null) {
          final snippetEncrypted =
              firebaseData['raw_snippet_encrypted'] as Map<String, dynamic>;
          txMap['raw_snippet'] = await EnhancedEncryptionService.instance
              .decryptFromFirebase(snippetEncrypted);
        }
      } catch (e) {
        print("Transaction decryption error: $e");
      }

      txMap.remove('vendor_encrypted');
      txMap.remove('raw_snippet_encrypted');
      txMap.remove('encryption_version');
      txMap.remove('created_at');
    }

    return TransactionModel.fromMap(txMap);
  }

  // --- Online Backup (Firestore with Encryption) ---

  Future<void> onlineBackup() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    if (!isUserEncryptionReady()) {
      throw Exception(
        "User encryption not set up. Call setupUserEncryption first.",
      );
    }

    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();
    final profiles = await DatabaseHelper.instance.getProfiles();

    // Batch limit is 500 operations
    WriteBatch batch = _firestore.batch();
    int opCount = 0;

    // Store encryption salt in user document
    final salt = await EnhancedEncryptionService.instance
        .getKeyDerivationSalt();
    if (salt != null) {
      final userDocRef = _firestore.collection('users').doc(user.uid);
      batch.set(userDocRef, {
        'encryption_salt': salt,
        'encryption_version': '2',
        'last_backup': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      opCount++;
    }

    // 1. Clear and Backup Cards
    final userCardsRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cards');
    final existingCards = await userCardsRef.get();
    for (var doc in existingCards.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    for (var card in cards) {
      final docRef = userCardsRef.doc(card.id.toString());
      final encryptedCard = await _encryptCardForFirebase(card);
      batch.set(docRef, encryptedCard);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    // 2. Clear and Backup Transactions
    final userTxsRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('transactions');
    final existingTxs = await userTxsRef.get();
    for (var doc in existingTxs.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    for (var tx in transactions) {
      final String txId =
          "${tx.vendor}_${tx.amount}_${tx.date.millisecondsSinceEpoch}"
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final docRef = userTxsRef.doc(txId);
      final encryptedTx = await _encryptTransactionForFirebase(tx);
      batch.set(docRef, encryptedTx);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    // 3. Clear and Backup Profiles
    final userProfilesRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('profiles');
    final existingProfiles = await userProfilesRef.get();
    for (var doc in existingProfiles.docs) {
      batch.delete(doc.reference);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    for (var profile in profiles) {
      final docRef = userProfilesRef.doc(profile.id.toString());
      // Encrypt sensitive profile fields
      final profileMap = profile.toMap();
      if (profile.name.isNotEmpty) {
        final encryptedName = await EnhancedEncryptionService.instance
            .encryptForFirebase(profile.name);
        profileMap['name_encrypted'] = encryptedName;
        profileMap.remove('name');
      }
      if (profile.email != null && profile.email!.isNotEmpty) {
        final encryptedEmail = await EnhancedEncryptionService.instance
            .encryptForFirebase(profile.email!);
        profileMap['email_encrypted'] = encryptedEmail;
        profileMap.remove('email');
      }
      profileMap['encryption_version'] = '2';
      profileMap['created_at'] = FieldValue.serverTimestamp();

      batch.set(docRef, profileMap);
      opCount++;
      if (opCount >= 500) {
        await batch.commit();
        batch = _firestore.batch();
        opCount = 0;
      }
    }

    if (opCount > 0) {
      await batch.commit();
    }
  }

  Future<void> onlineRestore() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    if (!isUserEncryptionReady()) {
      throw Exception(
        "User encryption not set up. Call setupUserEncryption first.",
      );
    }

    // Get encryption salt from user document
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final salt = userDoc.data()?['encryption_salt'] as String?;
    if (salt == null) {
      throw Exception(
        "No encryption salt found in user document. Cannot restore encrypted data.",
      );
    }

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
        final version = profileData['encryption_version'] ?? '1';
        final oldId = profileData['id'] as int?;

        // Decrypt profile data
        final decryptedData = Map<String, dynamic>.from(profileData);
        if (version == '2') {
          if (profileData['name_encrypted'] != null) {
            final encryptedName =
                profileData['name_encrypted'] as Map<String, dynamic>;
            decryptedData['name'] = await EnhancedEncryptionService.instance
                .decryptFromFirebase(encryptedName);
            decryptedData.remove('name_encrypted');
          }
          if (profileData['email_encrypted'] != null) {
            final encryptedEmail =
                profileData['email_encrypted'] as Map<String, dynamic>;
            decryptedData['email'] = await EnhancedEncryptionService.instance
                .decryptFromFirebase(encryptedEmail);
            decryptedData.remove('email_encrypted');
          }
        }

        decryptedData.remove('encryption_version');
        decryptedData.remove('created_at');

        final profile = ProfileModel.fromMap(decryptedData);
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
      final card = await _decryptCardFromFirebase(cardData);
      final oldId = card.id;

      card.id = null; // Reset to let SQLite auto-increment

      // Update profileId if we mapped it to a new local ID
      if (card.profileId != null &&
          profileIdMapping.containsKey(card.profileId)) {
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
      final tx = await _decryptTransactionFromFirebase(txData);

      // Map old card ID to new card ID on this device
      if (idMapping.containsKey(tx.cardId)) {
        tx.cardId = idMapping[tx.cardId]!;

        // We use a raw insert to avoid the "spent" amount incrementing twice
        await _insertTransactionRaw(tx);
      }
    }
  }

  /// Helper to insert transaction without affecting card spent amount (used during restore)
  /// Delegates to DatabaseHelper which strips the ID and uses ConflictAlgorithm.ignore.
  Future<void> _insertTransactionRaw(TransactionModel tx) async {
    await DatabaseHelper.instance.insertTransactionRaw(tx);
  }

  // --- Offline Backup (Local File with Encryption) ---

  Future<void> offlineBackup() async {
    final cards = await DatabaseHelper.instance.getCards();
    final transactions = await DatabaseHelper.instance.getTransactions();

    // Encrypt sensitive data for offline backup
    final encryptedCards = await Future.wait(
      cards.map((card) async {
        final cardMap = card.toMap();
        // Encrypt sensitive fields
        cardMap['number'] = await EnhancedEncryptionService.instance
            .encryptData(card.number);
        cardMap['cvv'] = await EnhancedEncryptionService.instance.encryptData(
          card.cvv,
        );
        cardMap['holder'] = await EnhancedEncryptionService.instance
            .encryptData(card.holder);
        cardMap['expiry'] = await EnhancedEncryptionService.instance
            .encryptData(card.expiry);
        return cardMap;
      }),
    );

    final jsonData = jsonEncode({
      'cards': encryptedCards,
      'transactions': transactions.map((e) => e.toMap()).toList(),
      'backup_version': '2',
      'timestamp': DateTime.now().toIso8601String(),
    });

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/cardvault_backup_encrypted.json');
    await file.writeAsString(jsonData);

    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'CardVault Encrypted Backup');
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
          final cardData = Map<String, dynamic>.from(item);
          // Decrypt fields if encrypted
          if (cardData['number'] is String) {
            try {
              cardData['number'] = await EnhancedEncryptionService.instance
                  .decryptData(cardData['number'] as String);
            } catch (e) {
              print("Failed to decrypt number: $e");
            }
          }
          if (cardData['cvv'] is String) {
            try {
              cardData['cvv'] = await EnhancedEncryptionService.instance
                  .decryptData(cardData['cvv'] as String);
            } catch (e) {
              print("Failed to decrypt cvv: $e");
            }
          }
          await DatabaseHelper.instance.insertCard(CardModel.fromMap(cardData));
        }
      } else if (decoded is Map) {
        // New format: cards and transactions
        if (decoded.containsKey('cards')) {
          List<dynamic> cardList = decoded['cards'];
          for (var item in cardList) {
            final cardData = Map<String, dynamic>.from(item);
            final oldId = cardData['id'] as int?;

            // Decrypt encrypted fields
            final fieldsToDecrypt = ['number', 'cvv', 'holder', 'expiry'];
            for (final field in fieldsToDecrypt) {
              if (cardData[field] is String) {
                try {
                  cardData[field] = await EnhancedEncryptionService.instance
                      .decryptData(cardData[field] as String);
                } catch (e) {
                  print("Failed to decrypt $field: $e");
                }
              }
            }

            final card = CardModel.fromMap(cardData);
            card.id = null;
            int newId = await DatabaseHelper.instance.insertCard(card);
            if (oldId != null) idMapping[oldId] = newId;
          }
        }

        if (decoded.containsKey('transactions')) {
          List<dynamic> txList = decoded['transactions'];
          for (var item in txList) {
            final tx = TransactionModel.fromMap(
              Map<String, dynamic>.from(item),
            );
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
