import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../models/profile_model.dart';
import '../services/enhanced_encryption_service.dart';

/// Enhanced database helper with improved encryption for all sensitive fields
class DatabaseHelperEnhanced {
  static final DatabaseHelperEnhanced instance = DatabaseHelperEnhanced._init();
  static Database? _database;

  DatabaseHelperEnhanced._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cards_enhanced.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dob TEXT,
        email TEXT,
        is_default INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cards(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bank TEXT,
        variant TEXT,
        network TEXT,
        number TEXT,
        holder TEXT,
        expiry TEXT,
        cvv TEXT,
        credit_limit REAL,
        spent REAL,
        due_date TEXT,
        is_paid INTEGER DEFAULT 0,
        linked_email TEXT,
        last4 TEXT,
        is_manual_due_date INTEGER DEFAULT 0,
        profile_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE email_accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE,
        display_name TEXT,
        profile_pic TEXT,
        refresh_token TEXT,
        last_sync_time TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_id INTEGER,
        bank TEXT,
        vendor TEXT,
        amount REAL,
        date TEXT,
        category TEXT,
        raw_snippet TEXT,
        FOREIGN KEY (card_id) REFERENCES cards (id) ON DELETE CASCADE
      )
    ''');
  }

  // --- Card Operations with Enhanced Encryption ---

  /// Encrypt all sensitive fields of a card
  Future<Map<String, dynamic>> _encryptCardFields(CardModel card) async {
    final map = card.toMap();

    // Encrypt sensitive fields
    try {
      map['number'] = await EnhancedEncryptionService.instance.encryptData(
        card.number,
      );
      map['cvv'] = await EnhancedEncryptionService.instance.encryptData(
        card.cvv,
      );
      map['holder'] = await EnhancedEncryptionService.instance.encryptData(
        card.holder,
      );
      map['expiry'] = await EnhancedEncryptionService.instance.encryptData(
        card.expiry,
      );
      map['bank'] = await EnhancedEncryptionService.instance.encryptData(
        card.bank,
      );
      map['variant'] = await EnhancedEncryptionService.instance.encryptData(
        card.variant,
      );
      if (card.linkedEmail != null && card.linkedEmail!.isNotEmpty) {
        map['linked_email'] = await EnhancedEncryptionService.instance
            .encryptData(card.linkedEmail!);
      }
    } catch (e) {
      print("Encryption error: $e");
      // Fallback to encrypting only critical fields
      map['number'] = await EnhancedEncryptionService.instance.encryptData(
        card.number,
      );
      map['cvv'] = await EnhancedEncryptionService.instance.encryptData(
        card.cvv,
      );
    }

    return map;
  }

  /// Decrypt all encrypted fields of a card
  Future<Map<String, dynamic>> _decryptCardFields(
    Map<String, dynamic> map,
  ) async {
    final mutableMap = Map<String, dynamic>.from(map);

    try {
      // Decrypt all potentially encrypted fields
      final fieldsToDecrypt = [
        'number',
        'cvv',
        'holder',
        'expiry',
        'bank',
        'variant',
        'linked_email',
      ];

      for (final field in fieldsToDecrypt) {
        if (mutableMap[field] != null && mutableMap[field] is String) {
          final encryptedValue = mutableMap[field] as String;
          if (encryptedValue.isNotEmpty) {
            mutableMap[field] = await EnhancedEncryptionService.instance
                .decryptData(encryptedValue);
          }
        }
      }
    } catch (e) {
      print("Decryption error: $e");
      // Try to decrypt at least number and cvv with legacy method
      try {
        if (mutableMap['number'] != null) {
          mutableMap['number'] = await EnhancedEncryptionService.instance
              .decryptData(mutableMap['number'] as String);
        }
        if (mutableMap['cvv'] != null) {
          mutableMap['cvv'] = await EnhancedEncryptionService.instance
              .decryptData(mutableMap['cvv'] as String);
        }
      } catch (e2) {
        print("Fallback decryption also failed: $e2");
      }
    }

    return mutableMap;
  }

  Future<int> insertCard(CardModel card) async {
    final db = await instance.database;
    final encryptedMap = await _encryptCardFields(card);

    // Remove id for auto-increment
    encryptedMap.remove('id');

    return await db.insert('cards', encryptedMap);
  }

  Future<List<CardModel>> getCards() async {
    final db = await instance.database;
    final result = await db.query('cards');

    return await Future.wait(
      result.map((map) async {
        final decryptedMap = await _decryptCardFields(map);
        return CardModel.fromMap(decryptedMap);
      }),
    );
  }

  Future<int> updateCard(CardModel card) async {
    final db = await instance.database;
    final encryptedMap = await _encryptCardFields(card);

    return await db.update(
      'cards',
      encryptedMap,
      where: 'id=?',
      whereArgs: [card.id],
    );
  }

  Future<int> deleteCard(int id) async {
    final db = await instance.database;
    return await db.delete('cards', where: 'id=?', whereArgs: [id]);
  }

  // --- Profile Operations ---

  Future<int> insertProfile(ProfileModel profile) async {
    final db = await instance.database;
    final map = profile.toMap();
    map.remove('id');

    // Encrypt sensitive profile fields
    try {
      if (profile.name.isNotEmpty) {
        map['name'] = await EnhancedEncryptionService.instance.encryptData(
          profile.name,
        );
      }
      if (profile.email != null && profile.email!.isNotEmpty) {
        map['email'] = await EnhancedEncryptionService.instance.encryptData(
          profile.email!,
        );
      }
    } catch (e) {
      print("Profile encryption error: $e");
    }

    return await db.insert('profiles', map);
  }

  Future<List<ProfileModel>> getProfiles() async {
    final db = await instance.database;
    final result = await db.query(
      'profiles',
      orderBy: 'is_default DESC, created_at ASC',
    );

    return await Future.wait(
      result.map((map) async {
        final mutableMap = Map<String, dynamic>.from(map);

        // Decrypt encrypted fields
        try {
          if (mutableMap['name'] != null) {
            mutableMap['name'] = await EnhancedEncryptionService.instance
                .decryptData(mutableMap['name'] as String);
          }
          if (mutableMap['email'] != null) {
            mutableMap['email'] = await EnhancedEncryptionService.instance
                .decryptData(mutableMap['email'] as String);
          }
        } catch (e) {
          print("Profile decryption error: $e");
        }

        return ProfileModel.fromMap(mutableMap);
      }),
    );
  }

  // --- Email Account Operations ---

  Future<int> insertEmailAccount(Map<String, dynamic> account) async {
    final db = await instance.database;
    final encryptedAccount = Map<String, dynamic>.from(account);

    // Encrypt sensitive email account data
    try {
      if (account['refresh_token'] != null) {
        encryptedAccount['refresh_token'] = await EnhancedEncryptionService
            .instance
            .encryptData(account['refresh_token'] as String);
      }
    } catch (e) {
      print("Email account encryption error: $e");
    }

    return await db.insert(
      'email_accounts',
      encryptedAccount,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getEmailAccounts() async {
    final db = await instance.database;
    final result = await db.query('email_accounts');

    return await Future.wait(
      result.map((map) async {
        final mutableMap = Map<String, dynamic>.from(map);

        // Decrypt refresh token
        try {
          if (mutableMap['refresh_token'] != null) {
            mutableMap['refresh_token'] = await EnhancedEncryptionService
                .instance
                .decryptData(mutableMap['refresh_token'] as String);
          }
        } catch (e) {
          print("Email account decryption error: $e");
        }

        return mutableMap;
      }),
    );
  }

  // --- Transaction Operations ---

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await instance.database;

    // Check if transaction already exists by vendor, amount and date (simple deduplication)
    final existing = await db.query(
      'transactions',
      where: 'vendor = ? AND amount = ? AND date = ?',
      whereArgs: [tx.vendor, tx.amount, tx.date.toIso8601String()],
    );

    if (existing.isNotEmpty) return -1;

    final map = tx.toMap();

    // Encrypt sensitive transaction fields
    try {
      if (tx.vendor.isNotEmpty) {
        map['vendor'] = await EnhancedEncryptionService.instance.encryptData(
          tx.vendor,
        );
      }
      if (tx.rawSnippet != null && tx.rawSnippet!.isNotEmpty) {
        map['raw_snippet'] = await EnhancedEncryptionService.instance
            .encryptData(tx.rawSnippet!);
      }
    } catch (e) {
      print("Transaction encryption error: $e");
    }

    final id = await db.insert('transactions', map);

    // Update card spent amount
    if (id != -1) {
      await db.rawUpdate('UPDATE cards SET spent = spent + ? WHERE id = ?', [
        tx.amount,
        tx.cardId,
      ]);
    }

    return id;
  }

  Future<List<TransactionModel>> getTransactions({int? cardId}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = cardId != null
        ? await db.query(
            'transactions',
            where: 'card_id = ?',
            whereArgs: [cardId],
            orderBy: 'date DESC',
          )
        : await db.query('transactions', orderBy: 'date DESC');

    return await Future.wait(
      maps.map((map) async {
        final mutableMap = Map<String, dynamic>.from(map);

        // Decrypt encrypted fields
        try {
          if (mutableMap['vendor'] != null) {
            mutableMap['vendor'] = await EnhancedEncryptionService.instance
                .decryptData(mutableMap['vendor'] as String);
          }
          if (mutableMap['raw_snippet'] != null) {
            mutableMap['raw_snippet'] = await EnhancedEncryptionService.instance
                .decryptData(mutableMap['raw_snippet'] as String);
          }
        } catch (e) {
          print("Transaction decryption error: $e");
        }

        return TransactionModel.fromMap(mutableMap);
      }),
    );
  }

  // --- Utility Methods ---

  Future<int> clearAllCards() async {
    final db = await instance.database;
    await db.delete('transactions');
    return await db.delete('cards');
  }

  Future<int> clearAllProfiles() async {
    final db = await instance.database;
    return await db.delete('profiles');
  }

  /// Migrate data from old database to new encrypted format
  Future<void> migrateFromOldDatabase(Database oldDb) async {
    // This would be implemented to migrate from the old database
    // For now, it's a placeholder
    print("Migration from old database not implemented");
  }
}
