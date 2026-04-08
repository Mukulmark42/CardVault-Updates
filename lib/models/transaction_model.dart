import 'package:intl/intl.dart';

class TransactionModel {
  int? id;
  int cardId;
  String bank;
  String vendor;
  double amount;
  DateTime date;
  String category;
  String rawSnippet;

  TransactionModel({
    this.id,
    required this.cardId,
    required this.bank,
    required this.vendor,
    required this.amount,
    required this.date,
    this.category = 'Other',
    this.rawSnippet = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'card_id': cardId,
      'bank': bank,
      'vendor': vendor,
      'amount': amount,
      'date': date.toIso8601String(),
      'category': category,
      'raw_snippet': rawSnippet,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      cardId: map['card_id'],
      bank: map['bank'] ?? '',
      vendor: map['vendor'] ?? 'Unknown',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.parse(map['date']),
      category: map['category'] ?? 'Other',
      rawSnippet: map['raw_snippet'] ?? '',
    );
  }

  String get formattedDate => DateFormat('dd MMM yyyy, hh:mm a').format(date);
}
