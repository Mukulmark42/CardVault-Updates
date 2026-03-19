class CardModel {
  int? id;
  String bank;
  String variant;
  String network;
  String number;
  String holder;
  String expiry;
  String cvv;
  double creditLimit;
  double spent;

  CardModel({
    this.id,
    required this.bank,
    required this.variant,
    required this.network,
    required this.number,
    required this.holder,
    required this.expiry,
    required this.cvv,
    required this.creditLimit,
    required this.spent,
  });

  CardModel copyWith({
    int? id,
    String? bank,
    String? variant,
    String? network,
    String? number,
    String? holder,
    String? expiry,
    String? cvv,
    double? creditLimit,
    double? spent,
  }) {
    return CardModel(
      id: id ?? this.id,
      bank: bank ?? this.bank,
      variant: variant ?? this.variant,
      network: network ?? this.network,
      number: number ?? this.number,
      holder: holder ?? this.holder,
      expiry: expiry ?? this.expiry,
      cvv: cvv ?? this.cvv,
      creditLimit: creditLimit ?? this.creditLimit,
      spent: spent ?? this.spent,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank': bank,
      'variant': variant,
      'network': network,
      'number': number,
      'holder': holder,
      'expiry': expiry,
      'cvv': cvv,
      'credit_limit': creditLimit,
      'spent': spent,
    };
  }

  factory CardModel.fromMap(Map<String, dynamic> map) {
    return CardModel(
      id: map['id'],
      bank: map['bank'] ?? '',
      variant: map['variant'] ?? '',
      network: map['network'] ?? 'VISA',
      number: map['number'] ?? '',
      holder: map['holder'] ?? '',
      expiry: map['expiry'] ?? '',
      cvv: map['cvv'] ?? '',
      creditLimit: (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
      spent: (map['spent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
