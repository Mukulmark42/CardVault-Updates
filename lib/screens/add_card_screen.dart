import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../models/card_model.dart';
import '../providers/card_provider.dart';

class AddCardScreen extends StatefulWidget {
  final CardModel? card;

  const AddCardScreen({super.key, this.card});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final bankController = TextEditingController();
  final variantController = TextEditingController();
  final numberController = TextEditingController();
  final holderController = TextEditingController();
  final expiryController = TextEditingController();
  final cvvController = TextEditingController();
  final limitController = TextEditingController();

  String _selectedNetwork = "VISA";
  bool _isDuplicate = false;
  String _lastDetectedBin = "";
  final List<String> networks = ["VISA", "MASTERCARD", "AMEX", "RUPAY"];

  final List<String> banks = [
    "HDFC Bank", "SBI Card", "ICICI Bank", "Axis Bank", "IDFC FIRST Bank",
    "Kotak Mahindra Bank", "IndusInd Bank", "RBL Bank", "YES Bank", "Federal Bank",
    "HSBC India", "Bank of Baroda (BOBCARD)", "Punjab National Bank (PNB)",
    "American Express (Amex)", "Standard Chartered Bank", "AU Small Finance Bank",
    "DBS Bank India", "Union Bank of India", "Canara Bank", "Bank of India (BOI)",
    "Indian Bank", "IDBI Bank", "South Indian Bank (SIB)", "Central Bank of India"
  ];

  final Map<String, List<String>> bankVariants = {
    "HDFC Bank": ["HDFC Infinia", "HDFC Diners Club Black", "HDFC Regalia Gold", "HDFC Millennia", "HDFC Pixel Play", "Tata Neu Infinity", "Swiggy HDFC", "Marriott Bonvoy HDFC", "IndianOil HDFC"],
    "SBI Card": ["SBI Cashback Card", "SBI SimplyCLICK", "SBI SimplySAVE", "SBI Card Prime", "SBI Card Elite", "BPCL SBI Card Octane", "Air India SBI Signature", "IRCTC SBI Platinum"],
    "ICICI Bank": ["Amazon Pay ICICI", "ICICI Coral", "ICICI Rubyx", "ICICI Sapphiro", "ICICI Emeralde", "MakeMyTrip ICICI Signature", "Manchester United ICICI"],
    "Axis Bank": ["Axis Magnus", "Axis Atlas", "Axis Reserve", "Axis ACE", "Flipkart Axis Bank", "Axis MyZone", "Airtel Axis Bank", "Vistara Axis Infinite"],
    "IDFC FIRST Bank": ["IDFC First Millennia", "IDFC First Classic", "IDFC First Select", "IDFC First Wealth", "IDFC Ashva", "IDFC Mayura", "HPCL IDFC First Power+"],
    "Kotak Mahindra Bank": ["Kotak League Platinum", "Kotak Zen Signature", "Kotak Mojo Card", "PVR INOX Kotak", "Kotak Myntra Card", "Kotak IndiGo Ka-ching", "Kotak White Card", "Kotak 811 #DreamDifferent"],
    "IndusInd Bank": ["IndusInd Legend", "IndusInd Platinum Aura Edge", "IndusInd EazyDiner Card", "IndusInd Pioneer Heritage", "IndusInd Nexxt Card", "IndusInd Club Vistara Cards", "IndusInd Tiger"],
    "RBL Bank": ["RBL Shoprite", "RBL World Safari", "RBL Edition Classic", "RBL SaveMax", "RBL Platinum Maxima"],
    "YES Bank": ["YES Marquee", "YES Reserv", "YES Premia", "YES Elite", "YES BYOC (Build Your Own Card)"],
    "Federal Bank": ["Federal Scapia", "Federal Celesta", "Federal Imperio", "Federal Signet"],
    "HSBC India": ["HSBC Travel One", "HSBC Live+", "HSBC Visa Platinum", "HSBC Premier"],
    "Bank of Baroda (BOBCARD)": ["BOBCARD Eterna", "BOBCARD Premier", "BOBCARD Select", "BOBCARD Easy", "BOBCARD Tiara", "HPCL BOBCARD ENERGIE", "Snapdeal BOBCARD"],
    "Punjab National Bank (PNB)": ["PNB RuPay Platinum", "PNB RuPay Select", "PNB RuPay Millennial", "PNB Visa Signature", "PNB Rakshak RuPay Select"],
    "American Express (Amex)": ["American Express Platinum Card", "American Express Platinum Travel", "American Express Gold Card", "American Express Membership Rewards", "American Express SmartEarn"],
    "Standard Chartered Bank": ["Standard Chartered Smart Card", "Standard Chartered Platinum Rewards", "Standard Chartered Ultimate", "Standard Chartered Super Value Titanium", "Standard Chartered EaseMyTrip"],
    "AU Small Finance Bank": ["AU Zenith+", "AU Zenith", "AU Vetta", "AU Altura Plus", "AU Altura", "AU LIT (Customizable Card)"],
    "DBS Bank India": ["DBS Vantage", "DBS Spark", "Bajaj Finserv DBS Network Cards"],
    "Union Bank of India": ["Union Bank Uni Carbon", "Union Bank Signature", "Union Bank Platinum", "Union Bank RuPay Select"],
    "Canara Bank": ["Canara Visa Classic / Gold / Platinum", "Canara RuPay Select", "Canara MasterCard Standard"],
    "Bank of India (BOI)": ["BOI RuPay Platinum", "BOI Visa Platinum", "BOI Swarnima"],
    "Indian Bank": ["Indian Bank RuPay Platinum", "Indian Bank Visa Platinum", "Indian Bank Bharat Credit Card"],
    "IDBI Bank": ["IDBI Winnings", "IDBI Aspire", "IDBI Imperium"],
    "South Indian Bank (SIB)": ["SIB OneCard (Co-branded)", "SIB RuPay Platinum", "SIB Visa Signature"],
    "Central Bank of India": ["Central Bank RuPay Select", "Central Bank RuPay Platinum"],
  };

  @override
  void initState() {
    super.initState();
    if (widget.card != null) {
      bankController.text = widget.card!.bank;
      variantController.text = widget.card!.variant;
      _selectedNetwork = widget.card!.network;
      numberController.text = _formatNumber(widget.card!.number);
      holderController.text = widget.card!.holder;
      expiryController.text = widget.card!.expiry;
      cvvController.text = widget.card!.cvv;
      limitController.text = widget.card!.creditLimit.toString();
    }

    numberController.addListener(_handleNumberChange);
    bankController.addListener(() => setState(() {}));
    variantController.addListener(() => setState(() {}));
    holderController.addListener(() => setState(() {}));
    expiryController.addListener(() => setState(() {}));
  }

  void _handleNumberChange() {
    _detectNetworkAndDuplicate();
    _autoDetectBank();
  }

  void _autoDetectBank() {
    String raw = numberController.text.replaceAll(' ', '');
    if (raw.length < 4) {
      _lastDetectedBin = "";
      return;
    }

    // Try 6 digits first for precision, then fallback to 4
    String currentBin = raw.substring(0, math.min(raw.length, 6));
    if (currentBin == _lastDetectedBin && raw.length < 6) return;

    String detectedBank = "";
    String detectedVariant = "";

    // Comprehensive India-focused BIN mapping (Specific 6-digit BINs first)
    final List<Map<String, dynamic>> detectionRules = [
      // HDFC Bank
      {'prefixes': ['431581', '456859'], 'bank': 'HDFC Bank', 'variant': 'HDFC Infinia'},
      {'prefixes': ['405887', '524315'], 'bank': 'HDFC Bank', 'variant': 'HDFC Millennia'},
      {'prefixes': ['486232', '424283'], 'bank': 'HDFC Bank', 'variant': 'HDFC Regalia Gold'},
      {'prefixes': ['369110', '304381'], 'bank': 'HDFC Bank', 'variant': 'HDFC Diners Club Black'},
      {'prefixes': ['4315', '4568', '4058', '4862', '4242', '4001', '4032', '4412', '4160', '5243', '5477', '5289'], 'bank': 'HDFC Bank'},
      
      // ICICI Bank
      {'prefixes': ['433919', '433920', '433921'], 'bank': 'ICICI Bank', 'variant': 'Amazon Pay ICICI'},
      {'prefixes': ['472642'], 'bank': 'ICICI Bank', 'variant': 'ICICI Coral'},
      {'prefixes': ['447746'], 'bank': 'ICICI Bank', 'variant': 'ICICI Sapphiro'},
      {'prefixes': ['4339', '4726', '4477', '5176', '5546', '4629', '4623', '4055', '4213', '4053'], 'bank': 'ICICI Bank'},
      
      // SBI Card
      {'prefixes': ['459149'], 'bank': 'SBI Card', 'variant': 'SBI Cashback Card'},
      {'prefixes': ['459246'], 'bank': 'SBI Card', 'variant': 'SBI SimplyCLICK'},
      {'prefixes': ['4591', '4592', '5432', '5522', '6070', '5021', '4166', '4037', '4256', '4724'], 'bank': 'SBI Card'},
      
      // Axis Bank
      {'prefixes': ['422338'], 'bank': 'Axis Bank', 'variant': 'Axis Magnus'},
      {'prefixes': ['438587'], 'bank': 'Axis Bank', 'variant': 'Axis Ace'},
      {'prefixes': ['512540'], 'bank': 'Axis Bank', 'variant': 'Flipkart Axis Bank'},
      {'prefixes': ['4223', '4385', '5125', '5326', '5245', '4054', '4160', '4623'], 'bank': 'Axis Bank'},
      
      // Amex
      {'prefixes': ['3712'], 'bank': 'American Express (Amex)', 'variant': 'American Express Gold Card'},
      {'prefixes': ['3711'], 'bank': 'American Express (Amex)', 'variant': 'American Express Platinum Card'},
      {'prefixes': ['34', '37'], 'bank': 'American Express (Amex)'},
      
      // Others
      {'prefixes': ['4166', '4386', '4413', '5262', '4037'], 'bank': 'Kotak Mahindra Bank'},
      {'prefixes': ['4835', '4111', '4514', '4213'], 'bank': 'IDFC FIRST Bank'},
      {'prefixes': ['5245', '5548', '4014', '4835'], 'bank': 'RBL Bank'},
      {'prefixes': ['5521', '4262', '4451'], 'bank': 'YES Bank'},
      {'prefixes': ['4413', '5241', '4037'], 'bank': 'AU Small Finance Bank'},
      {'prefixes': ['4514', '4001', '4005', '4006'], 'bank': 'Federal Bank'},
      {'prefixes': ['4000', '4001', '4005', '4006', '4514'], 'bank': 'HSBC India'},
      {'prefixes': ['4037', '4054', '4315', '4514'], 'bank': 'Standard Chartered Bank'},
      {'prefixes': ['4037', '4315', '4381', '5044', '5245', '5520'], 'bank': 'Bank of Baroda (BOBCARD)'},
      {'prefixes': ['4037', '4111', '4262', '4315', '4514', '5217', '5241'], 'bank': 'Punjab National Bank (PNB)'},
      {'prefixes': ['4001', '4037', '4262', '4315', '4514', '5241'], 'bank': 'Canara Bank'},
      {'prefixes': ['4037', '4262', '4315', '4514', '5241'], 'bank': 'Union Bank of India'},
      {'prefixes': ['4037', '4262', '4315', '4514', '5241'], 'bank': 'Indian Bank'},
      {'prefixes': ['4037', '4262', '4315', '4514', '5241'], 'bank': 'IDBI Bank'},
    ];

    for (var rule in detectionRules) {
      if ((rule['prefixes'] as List<String>).any((prefix) => raw.startsWith(prefix))) {
        detectedBank = rule['bank'] as String;
        detectedVariant = rule['variant'] as String? ?? "";
        break;
      }
    }

    if (detectedBank.isNotEmpty) {
      _lastDetectedBin = currentBin;
      
      // If the user has manually entered a bank that's NOT in our list, we don't overwrite it.
      // If it IS in our list or empty, we update it.
      bool isManualCustomBank = bankController.text.isNotEmpty && !banks.contains(bankController.text);
      
      if (!isManualCustomBank) {
        setState(() {
          if (bankController.text != detectedBank) {
            bankController.text = detectedBank;
          }
          // Auto-fill variant ONLY if it's currently empty
          if (detectedVariant.isNotEmpty && variantController.text.isEmpty) {
            variantController.text = detectedVariant;
          }
        });
      }
    }
  }

  void _detectNetworkAndDuplicate() {
    String rawNumber = numberController.text.replaceAll(' ', '');
    String network = "VISA";

    if (rawNumber.isNotEmpty) {
      if (rawNumber.startsWith('4')) {
        network = "VISA";
      } else if (RegExp(r'^5[1-5]').hasMatch(rawNumber) || 
                 RegExp(r'^222[1-9]|22[3-9]|2[3-6]|27[0-1]|2720').hasMatch(rawNumber)) {
        network = "MASTERCARD";
      } else if (RegExp(r'^3[47]').hasMatch(rawNumber)) {
        network = "AMEX";
      } else if (RegExp(r'^6(?:011|5|4[4-9]|22)').hasMatch(rawNumber) || 
                 rawNumber.startsWith('60') || 
                 rawNumber.startsWith('65') || 
                 rawNumber.startsWith('81') || 
                 rawNumber.startsWith('82') || 
                 rawNumber.startsWith('508')) {
        network = "RUPAY";
      }
    }

    bool isDup = false;
    final int targetLength = (network == "AMEX") ? 15 : 16;
    
    if (rawNumber.length == targetLength) {
      final cardProvider = context.read<CardProvider>();
      isDup = cardProvider.isCardDuplicate(rawNumber, excludeId: widget.card?.id);
    }

    if (_selectedNetwork != network || _isDuplicate != isDup) {
      setState(() {
        _selectedNetwork = network;
        _isDuplicate = isDup;
      });
    }
  }

  String _formatNumber(String number) {
    var text = number.replaceAll(' ', '');
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  void saveCard() async {
    if (bankController.text.trim().isEmpty ||
        numberController.text.trim().isEmpty ||
        holderController.text.trim().isEmpty ||
        expiryController.text.trim().isEmpty ||
        cvvController.text.trim().isEmpty ||
        limitController.text.trim().isEmpty) {
      _showError("Please fill all fields");
      return;
    }

    if (_isDuplicate) {
      _showError("Cannot save: Duplicate card number");
      return;
    }

    final card = CardModel(
      id: widget.card?.id,
      bank: bankController.text.trim(),
      variant: variantController.text.trim(),
      network: _selectedNetwork,
      number: numberController.text.replaceAll(' ', ''),
      holder: holderController.text.trim().toUpperCase(),
      expiry: expiryController.text.trim(),
      cvv: cvvController.text.trim(),
      creditLimit: double.tryParse(limitController.text) ?? 0,
      spent: widget.card?.spent ?? 0,
    );

    try {
      final cardProvider = context.read<CardProvider>();
      if (widget.card == null) {
        await cardProvider.addCard(card);
      } else {
        await cardProvider.updateCard(card);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError("Error saving card");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.card == null ? "New Card" : "Edit Details", 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    
                    _buildSectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel("CARD NUMBER"),
                          _customTextField(
                            numberController,
                            "0000 0000 0000 0000",
                            keyboard: TextInputType.number,
                            isError: _isDuplicate,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _CardNumberFormatter(),
                              LengthLimitingTextInputFormatter(19),
                            ],
                            suffix: _getNetworkBadge(),
                          ),
                          const SizedBox(height: 20),
                          _buildLabel("BANK NAME"),
                          Autocomplete<String>(
                            optionsBuilder: (textValue) => banks.where((b) => b.toLowerCase().contains(textValue.text.toLowerCase())),
                            onSelected: (val) {
                              setState(() {
                                bankController.text = val;
                              });
                            },
                            fieldViewBuilder: (ctx, ctrl, node, onFixed) {
                              if (bankController.text != ctrl.text && bankController.text.isNotEmpty && ctrl.text.isEmpty) {
                                 Future.microtask(() => ctrl.text = bankController.text);
                              }
                              return _customTextField(
                                ctrl, "e.g. HDFC Bank", node: node,
                                onChanged: (val) {
                                  bankController.text = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildSectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel("VARIANT & HOLDER"),
                          Autocomplete<String>(
                            optionsBuilder: (textValue) {
                              List<String> variants = bankVariants[bankController.text.trim()] ?? [];
                              if (textValue.text.isEmpty) return variants;
                              return variants.where((v) => v.toLowerCase().contains(textValue.text.toLowerCase()));
                            },
                            onSelected: (val) => setState(() => variantController.text = val),
                            fieldViewBuilder: (ctx, ctrl, node, onFixed) {
                              if (variantController.text != ctrl.text && variantController.text.isNotEmpty && ctrl.text.isEmpty) {
                                Future.microtask(() => ctrl.text = variantController.text);
                              }
                              return _customTextField(
                                ctrl, "e.g. Regalia Gold", node: node,
                                onChanged: (val) => variantController.text = val,
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _customTextField(holderController, "FULL NAME ON CARD", textCapitalization: TextCapitalization.characters),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildSectionContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel("EXPIRY"),
                                    _customTextField(expiryController, "MM/YY", 
                                      keyboard: TextInputType.number,
                                      formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4), _ExpiryDateFormatter()]
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel("CVV"),
                                    _customTextField(cvvController, "•••", 
                                      keyboard: TextInputType.number, obscureText: true,
                                      formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildLabel("CREDIT LIMIT (₹)"),
                          _customTextField(limitController, "5,00,000", 
                            keyboard: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                ),
                onPressed: saveCard,
                child: Text("SAVE TO VAULT", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionContainer({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(text, style: GoogleFonts.poppins(color: Theme.of(context).hintColor.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _customTextField(TextEditingController ctrl, String hint, {
    TextInputType? keyboard, 
    List<TextInputFormatter>? formatters, 
    FocusNode? node, 
    Widget? suffix,
    bool obscureText = false,
    bool isError = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
    void Function(String)? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: ctrl,
      focusNode: node,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscureText,
      textCapitalization: (textCapitalization == TextCapitalization.none && ctrl == holderController) ? TextCapitalization.characters : textCapitalization,
      onChanged: onChanged,
      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), 
          borderSide: BorderSide(color: isError ? Colors.redAccent.withOpacity(0.5) : Theme.of(context).dividerColor.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), 
          borderSide: BorderSide(color: isError ? Colors.redAccent : Theme.of(context).colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _getNetworkBadge() {
    if (numberController.text.isEmpty) return Icon(Icons.credit_card, color: Theme.of(context).hintColor.withOpacity(0.2));
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
      ),
      child: Text(_selectedNetwork, style: GoogleFonts.poppins(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.replaceAll(' ', '');
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) {
        buffer.write(' ');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length && !text.contains('/')) {
        buffer.write('/');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}
