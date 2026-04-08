import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/card_model.dart';
import '../models/transaction_model.dart';
import '../models/profile_model.dart';
import '../services/encryption_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cards.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 8, onCreate: _createDB, onUpgrade: _onUpgrade);
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

    await _createTransactionsTable(db);
  }

  Future _createTransactionsTable(Database db) async {
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

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE cards ADD COLUMN variant TEXT DEFAULT ''");
    }
    if (oldVersion < 3) {
      await db.execute("ALTER TABLE cards ADD COLUMN network TEXT DEFAULT 'VISA'");
    }
    if (oldVersion < 4) {
      await db.execute("ALTER TABLE cards ADD COLUMN due_date TEXT");
      await db.execute("ALTER TABLE cards ADD COLUMN is_paid INTEGER DEFAULT 0");
    }
    if (oldVersion < 5) {
      await db.execute("ALTER TABLE cards ADD COLUMN linked_email TEXT");
      await db.execute("ALTER TABLE cards ADD COLUMN last4 TEXT");
      
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
    }
    if (oldVersion < 6) {
      var columns = await db.rawQuery("PRAGMA table_info(cards)");
      var hasManualCol = columns.any((c) => c['name'] == 'is_manual_due_date');
      if (!hasManualCol) {
        await db.execute("ALTER TABLE cards ADD COLUMN is_manual_due_date INTEGER DEFAULT 0");
      }
    }
    if (oldVersion < 7) {
      await _createTransactionsTable(db);
    }
    if (oldVersion < 8) {
      // Add profiles table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS profiles(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          dob TEXT,
          email TEXT,
          is_default INTEGER DEFAULT 0,
          created_at TEXT
        )
      ''');
      // Add profile_id to cards
      var cardCols = await db.rawQuery('PRAGMA table_info(cards)');
      if (!cardCols.any((c) => c['name'] == 'profile_id')) {
        await db.execute('ALTER TABLE cards ADD COLUMN profile_id INTEGER');
      }
    }
  }

  // --- Profile Operations ---

  Future<int> insertProfile(ProfileModel profile) async {
    final db = await instance.database;
    // If this is the first profile or marked as default, clear existing defaults
    if (profile.isDefault) {
      await db.update('profiles', {'is_default': 0});
    }
    return await db.insert('profiles', profile.toMap()..remove('id'));
  }

  Future<List<ProfileModel>> getProfiles() async {
    final db = await instance.database;
    final result = await db.query('profiles', orderBy: 'is_default DESC, created_at ASC');
    return result.map((m) => ProfileModel.fromMap(m)).toList();
  }

  Future<ProfileModel?> getDefaultProfile() async {
    final db = await instance.database;
    final result = await db.query('profiles', where: 'is_default = 1', limit: 1);
    if (result.isEmpty) {
      // Return first profile as fallback
      final all = await db.query('profiles', orderBy: 'created_at ASC', limit: 1);
      return all.isEmpty ? null : ProfileModel.fromMap(all.first);
    }
    return ProfileModel.fromMap(result.first);
  }

  Future<int> updateProfile(ProfileModel profile) async {
    final db = await instance.database;
    if (profile.isDefault) {
      await db.update('profiles', {'is_default': 0});
    }
    return await db.update(
      'profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<int> deleteProfile(int id) async {
    final db = await instance.database;
    return await db.delete('profiles', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setDefaultProfile(int id) async {
    final db = await instance.database;
    await db.update('profiles', {'is_default': 0});
    await db.update('profiles', {'is_default': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clearAllProfiles() async {
    final db = await instance.database;
    return await db.delete('profiles');
  }

  // --- Email Account Operations ---

  Future<int> insertEmailAccount(Map<String, dynamic> account) async {
    final db = await instance.database;
    return await db.insert(
      'email_accounts', 
      account, 
      conflictAlgorithm: ConflictAlgorithm.replace
    );
  }

  Future<List<Map<String, dynamic>>> getEmailAccounts() async {
    final db = await instance.database;
    return await db.query('email_accounts');
  }

  Future<int> deleteEmailAccount(String email) async {
    final db = await instance.database;
    await db.update('cards', {'linked_email': null}, where: 'linked_email = ?', whereArgs: [email]);
    return await db.delete('email_accounts', where: 'email = ?', whereArgs: [email]);
  }

  Future<int> updateEmailAccountSyncTime(String email) async {
    final db = await instance.database;
    return await db.update(
      'email_accounts',
      {'last_sync_time': DateTime.now().toIso8601String()},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  // --- Card Operations ---

  Future<int> insertCard(CardModel card) async {
    final db = await instance.database;
    final encryptedNumber = await EncryptionService.instance.encryptData(card.number);
    final encryptedCvv = await EncryptionService.instance.encryptData(card.cvv);

    final map = card.toMap();
    map['number'] = encryptedNumber;
    map['cvv'] = encryptedCvv;

    return await db.insert('cards', map);
  }

  Future<List<CardModel>> getCards() async {
    final db = await instance.database;
    final result = await db.query('cards');

    return await Future.wait(result.map((map) async {
      final mutableMap = Map<String, dynamic>.from(map);
      try {
        final decryptedNumber = await EncryptionService.instance.decryptData(map['number'] as String);
        final decryptedCvv = await EncryptionService.instance.decryptData(map['cvv'] as String);
        mutableMap['number'] = decryptedNumber;
        mutableMap['cvv'] = decryptedCvv;
      } catch (e) {}
      return CardModel.fromMap(mutableMap);
    }));
  }

  Future<int> updateCard(CardModel card) async {
    final db = await instance.database;
    final encryptedNumber = await EncryptionService.instance.encryptData(card.number);
    final encryptedCvv = await EncryptionService.instance.encryptData(card.cvv);

    final map = card.toMap();
    map['number'] = encryptedNumber;
    map['cvv'] = encryptedCvv;

    return await db.update(
      'cards',
      map,
      where: 'id=?',
      whereArgs: [card.id],
    );
  }

  Future<int> deleteCard(int id) async {
    final db = await instance.database;
    return await db.delete(
      'cards',
      where: 'id=?',
      whereArgs: [id],
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

    final id = await db.insert('transactions', tx.toMap());
    
    // Update card spent amount
    if (id != -1) {
      await db.rawUpdate(
        'UPDATE cards SET spent = spent + ? WHERE id = ?',
        [tx.amount, tx.cardId]
      );
    }
    
    return id;
  }

  Future<List<TransactionModel>> getTransactions({int? cardId}) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> maps = cardId != null
        ? await db.query('transactions', where: 'card_id = ?', whereArgs: [cardId], orderBy: 'date DESC')
        : await db.query('transactions', orderBy: 'date DESC');

    return List.generate(maps.length, (i) => TransactionModel.fromMap(maps[i]));
  }

  Future<Map<String, double>> getSpendingByCategory() async {
    final db = await instance.database;
    final List<Map<String, dynamic>> result = await db.rawQuery(
      'SELECT category, SUM(amount) as total FROM transactions GROUP BY category'
    );
    
    Map<String, double> spending = {};
    for (var row in result) {
      spending[row['category'] as String] = (row['total'] as num).toDouble();
    }
    return spending;
  }

  Future<int> clearAllCards() async {
    final db = await instance.database;
    await db.delete('transactions');
    return await db.delete('cards');
  }
}
