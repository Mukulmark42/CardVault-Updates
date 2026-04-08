import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';

class TransactionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final TransactionService instance = TransactionService._internal();
  factory TransactionService() => instance;
  TransactionService._internal();

  /// Saves a transaction to Firestore for cross-device sync and backup.
  Future<void> saveTransactionToFirebase(TransactionModel tx) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint("No authenticated user. Skipping Firebase transaction sync.");
        return;
      }

      // Check if this transaction already exists in Firestore to prevent duplicates
      // We query by vendor, amount, and date.
      final existing = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('transactions')
          .where('vendor', isEqualTo: tx.vendor)
          .where('amount', isEqualTo: tx.amount)
          .where('date', isEqualTo: tx.date.toIso8601String())
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        debugPrint("Transaction already exists in Firebase. Skipping.");
        return;
      }

      // Use an auto-generated ID for better reliability
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('transactions')
          .add({
        ...tx.toMap(),
        'syncedAt': FieldValue.serverTimestamp(),
      });

      debugPrint("Transaction synced to Firebase: ${tx.vendor} - ${tx.amount}");
    } catch (e) {
      debugPrint("Error syncing transaction to Firebase: $e");
    }
  }

  /// Streams transactions from Firestore
  Stream<List<TransactionModel>> getTransactionsStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('transactions')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => TransactionModel.fromMap(doc.data())).toList();
    });
  }
}
