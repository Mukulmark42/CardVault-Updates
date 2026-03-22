import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';

class BackupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- Online Backup (Firestore) ---

  Future<void> onlineBackup() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final cards = await DatabaseHelper.instance.getCards();
    final batch = _firestore.batch();
    
    final userCardsRef = _firestore.collection('users').doc(user.uid).collection('cards');

    // Clear existing online cards before backup to avoid duplicates or keep in sync
    final existingCards = await userCardsRef.get();
    for (var doc in existingCards.docs) {
      batch.delete(doc.reference);
    }

    for (var card in cards) {
      final docRef = userCardsRef.doc();
      batch.set(docRef, card.toMap());
    }

    await batch.commit();
  }

  Future<void> onlineRestore() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final querySnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cards')
        .get();

    if (querySnapshot.docs.isEmpty) return;

    // Clear local data before restore
    await DatabaseHelper.instance.clearAllCards();

    for (var doc in querySnapshot.docs) {
      final card = CardModel.fromMap(doc.data());
      await DatabaseHelper.instance.insertCard(card);
    }
  }

  // --- Offline Backup (Local File) ---

  Future<void> offlineBackup() async {
    final cards = await DatabaseHelper.instance.getCards();
    final jsonData = jsonEncode(cards.map((e) => e.toMap()).toList());
    
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
      List<dynamic> jsonData = jsonDecode(content);

      await DatabaseHelper.instance.clearAllCards();
      for (var item in jsonData) {
        await DatabaseHelper.instance.insertCard(CardModel.fromMap(item));
      }
    }
  }
}
