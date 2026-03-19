import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/card_model.dart';
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
    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
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
        spent REAL
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
  }

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

    // Optimization: Parallel Decryption using Future.wait
    return await Future.wait(result.map((map) async {
      final mutableMap = Map<String, dynamic>.from(map);
      try {
        final decryptedNumber = await EncryptionService.instance.decryptData(map['number'] as String);
        final decryptedCvv = await EncryptionService.instance.decryptData(map['cvv'] as String);
        mutableMap['number'] = decryptedNumber;
        mutableMap['cvv'] = decryptedCvv;
      } catch (e) {
        // Fallback or log if needed
      }
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

  Future<int> clearAllCards() async {
    final db = await instance.database;
    return await db.delete('cards');
  }
}
