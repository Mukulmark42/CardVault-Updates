import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/card_model.dart';

class CardProvider extends ChangeNotifier {
  List<CardModel> _cards = [];
  List<CardModel> get cards => _cards;

  CardProvider();

  Future<void> refreshCards() async {
    try {
      _cards = await DatabaseHelper.instance.getCards();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing cards: $e");
    }
  }

  bool isCardDuplicate(String cardNumber, {int? excludeId}) {
    final rawNumber = cardNumber.replaceAll(' ', '');
    return _cards.any((c) => c.number.replaceAll(' ', '') == rawNumber && c.id != excludeId);
  }

  Future<void> addCard(CardModel card) async {
    await DatabaseHelper.instance.insertCard(card);
    await refreshCards();
  }

  Future<void> updateCard(CardModel card) async {
    await DatabaseHelper.instance.updateCard(card);
    await refreshCards();
  }

  Future<void> deleteCard(int id) async {
    await DatabaseHelper.instance.deleteCard(id);
    await refreshCards();
  }

  Future<void> clearAllCards() async {
    await DatabaseHelper.instance.clearAllCards();
    await refreshCards();
  }
}
