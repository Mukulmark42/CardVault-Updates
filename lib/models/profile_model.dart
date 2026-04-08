class ProfileModel {
  int? id;
  String name;
  String? dob; // ISO8601 date string e.g. "1992-01-05"
  String? email;
  bool isDefault;
  DateTime createdAt;

  ProfileModel({
    this.id,
    required this.name,
    this.dob,
    this.email,
    this.isDefault = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Generates candidate passwords for PDF unlocking based on common Indian
  /// bank statement password formats.
  ///
  /// Formats tried (in order):
  ///  1. first4Letters + DDMM       e.g. "suji0501"  (most common)
  ///  2. first4Letters + DDMMYYYY   e.g. "suji05011992"
  ///  3. DDMMYYYY                   e.g. "05011992"
  ///  4. first4Letters + YYYY       e.g. "suji1992"
  ///  5. first4Letters              e.g. "suji"
  List<String> get pdfPasswordCandidates {
    final candidates = <String>[];
    final cleanName = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final prefix = cleanName.length >= 4 ? cleanName.substring(0, 4) : cleanName;

    if (dob != null) {
      try {
        final dt = DateTime.parse(dob!);
        final dd = dt.day.toString().padLeft(2, '0');
        final mm = dt.month.toString().padLeft(2, '0');
        final yyyy = dt.year.toString();

        candidates.addAll([
          '$prefix$dd$mm',
          '${prefix.toUpperCase()}$dd$mm',
          '$prefix$dd$mm$yyyy',
          '${prefix.toUpperCase()}$dd$mm$yyyy',
          '$dd$mm$yyyy',
          '$prefix$yyyy',
          '${prefix.toUpperCase()}$yyyy'
        ]);
      } catch (_) {}
    }

    candidates.add(prefix);
    candidates.add(prefix.toUpperCase());
    return candidates;
  }

  /// Matches profile name against a card holder name.
  /// Returns a score 0.0–1.0 (higher = better match).
  double matchScore(String holderName) {
    final profNorm = name.toLowerCase().trim();
    final holdNorm = holderName.toLowerCase().trim();

    if (profNorm == holdNorm) return 1.0;

    // Check if all profile name words appear in holder name
    final profWords = profNorm.split(RegExp(r'\s+'));
    final holdWords = holdNorm.split(RegExp(r'\s+'));
    final matchingWords = profWords.where((w) => holdWords.any((h) => h.startsWith(w) || w.startsWith(h))).length;
    if (matchingWords == profWords.length) return 0.9;

    // Prefix match: first 4 chars of first name match
    final profFirst = profWords.first;
    final holdFirst = holdWords.first;
    final prefixLen = profFirst.length < 4 ? profFirst.length : 4;
    if (profFirst.substring(0, prefixLen) == holdFirst.substring(0, holdFirst.length < prefixLen ? holdFirst.length : prefixLen)) {
      return 0.7;
    }

    return 0.0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dob': dob,
      'email': email,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'],
      name: map['name'] ?? '',
      dob: map['dob'],
      email: map['email'],
      isDefault: (map['is_default'] ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  ProfileModel copyWith({
    int? id,
    String? name,
    String? Function()? dob,
    String? Function()? email,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      dob: dob != null ? dob() : this.dob,
      email: email != null ? email() : this.email,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
