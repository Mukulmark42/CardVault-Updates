class CardModel {
  int? id;
  String bank;
  String variant;
  String network;
  String number; // This usually stores the full number or last 4
  String holder;
  String expiry;
  String cvv;
  double creditLimit;
  double spent;
  String? dueDate; // Stored as ISO8601 string
  bool isPaid;
  String? linkedEmail; // NEW: The Gmail account assigned to this card
  String? last4; // NEW: Explicit last 4 digits for better matching
  bool isManualDueDate; // If true, ignore auto-detection from emails
  int? profileId; // NEW: Links card to a profile (auto-matched by holder name)

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
    this.dueDate,
    this.isPaid = false,
    this.linkedEmail,
    this.last4,
    this.isManualDueDate = false,
    this.profileId,
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
    String? Function()? dueDate,
    bool? isPaid,
    String? Function()? linkedEmail,
    String? last4,
    bool? isManualDueDate,
    int? Function()? profileId,
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
      dueDate: dueDate != null ? dueDate() : this.dueDate,
      isPaid: isPaid ?? this.isPaid,
      linkedEmail: linkedEmail != null ? linkedEmail() : this.linkedEmail,
      last4: last4 ?? this.last4,
      isManualDueDate: isManualDueDate ?? this.isManualDueDate,
      profileId: profileId != null ? profileId() : this.profileId,
    );
  }

  /// Automatically rolls the due date to the same day of the next month.
  CardModel rollToNextMonth() {
    if (dueDate == null) return this;
    
    DateTime current = DateTime.parse(dueDate!);
    
    // Add 1 month. Handle end of month edge cases (e.g. Jan 31 -> Feb 28)
    int nextYear = current.year;
    int nextMonth = current.month + 1;
    if (nextMonth > 12) {
      nextMonth = 1;
      nextYear++;
    }
    
    // Check if the original day exists in the next month
    int lastDayOfNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
    int nextDay = current.day > lastDayOfNextMonth ? lastDayOfNextMonth : current.day;
    
    DateTime nextDueDate = DateTime(nextYear, nextMonth, nextDay, current.hour, current.minute);
    
    return copyWith(
      dueDate: () => nextDueDate.toIso8601String(),
      isPaid: false,
      spent: 0.0, // Reset spent amount for the new cycle
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
      'due_date': dueDate,
      'is_paid': isPaid ? 1 : 0,
      'linked_email': linkedEmail,
      'last4': last4 ?? (number.length >= 4 ? number.substring(number.length - 4) : number),
      'is_manual_due_date': isManualDueDate ? 1 : 0,
      'profile_id': profileId,
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
      dueDate: map['due_date'],
      isPaid: (map['is_paid'] ?? 0) == 1,
      linkedEmail: map['linked_email'],
      last4: map['last4'],
      isManualDueDate: (map['is_manual_due_date'] ?? 0) == 1,
      profileId: map['profile_id'] as int?,
    );
  }
}
