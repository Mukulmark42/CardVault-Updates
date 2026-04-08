import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/card_model.dart';

class HistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final HistoryService instance = HistoryService._internal();
  factory HistoryService() => instance;
  HistoryService._internal();

  Future<void> saveBillHistory(CardModel card) async {
    try {
      final user = _auth.currentUser;
      if (user == null || card.dueDate == null) return;

      // Unique ID for each bill cycle: CardID + DueDate string
      final String historyId = "${card.id}_${card.dueDate!.replaceAll(RegExp(r'[^0-9]'), '')}";

      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('bill_history')
          .doc(historyId);

      // Skip if already processed
      final doc = await docRef.get();
      if (doc.exists) {
        debugPrint("Bill history for ${card.bank} ($historyId) already exists. Skipping.");
        return;
      }

      await docRef.set({
        'bank': card.bank,
        'amount': card.spent,
        'dueDate': card.dueDate,
        'createdAt': FieldValue.serverTimestamp(),
        'cardId': card.id,
        'last4': card.last4 ?? (card.number.length >= 4 ? card.number.substring(card.number.length - 4) : card.number),
      });
      
      debugPrint("Bill history saved for ${card.bank}");
    } catch (e) {
      debugPrint("Error saving bill history: $e");
    }
  }
}
