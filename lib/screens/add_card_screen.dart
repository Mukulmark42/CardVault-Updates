import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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

    numberController.addListener(_detectNetworkAndDuplicate);
    bankController.addListener(() => setState(() {}));
    variantController.addListener(() => setState(() {}));
    holderController.addListener(() => setState(() {}));
    expiryController.addListener(() => setState(() {}));
  }

  void _detectNetworkAndDuplicate() {
    String rawNumber = numberController.text.replaceAll(' ', '');
    String network = "VISA";

    // 1. Detect Network
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

    // 2. Detect Duplicate (Only if full number is entered, typically 16 digits, or 15 for AMEX)
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
      _showError("Cannot save: This card number is already in your vault");
      return;
    }

    String rawNumber = numberController.text.replaceAll(' ', '');
    double cardLimit = double.tryParse(limitController.text) ?? 0;

    final card = CardModel(
      id: widget.card?.id,
      bank: bankController.text.trim(),
      variant: variantController.text.trim(),
      network: _selectedNetwork,
      number: rawNumber,
      holder: holderController.text.trim(),
      expiry: expiryController.text.trim(),
      cvv: cvvController.text.trim(),
      creditLimit: cardLimit,
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
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: Text(widget.card == null ? "Add Card" : "Edit Card", 
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
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
                    const SizedBox(height: 10),
                    
                    _buildLabel("CARD NUMBER"),
                    _customTextField(
                      numberController,
                      "XXXX XXXX XXXX XXXX",
                      keyboard: TextInputType.number,
                      isError: _isDuplicate,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CardNumberFormatter(),
                        LengthLimitingTextInputFormatter(19),
                      ],
                      suffix: _getNetworkBadge(),
                    ),
                    if (_isDuplicate)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          "This card number is already in your vault",
                          style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel("BANK NAME"),
                              Autocomplete<String>(
                                optionsBuilder: (textValue) => banks.where((b) => b.toLowerCase().contains(textValue.text.toLowerCase())),
                                onSelected: (val) {
                                  setState(() {
                                    bankController.text = val;
                                    // Automatically set first variant if available
                                    List<String>? variants = bankVariants[val];
                                    if (variants != null && variants.isNotEmpty) {
                                      variantController.text = variants.first;
                                    } else {
                                      variantController.clear();
                                    }
                                  });
                                },
                                fieldViewBuilder: (ctx, ctrl, node, onFixed) {
                                  if (bankController.text != ctrl.text) {
                                    Future.microtask(() => ctrl.text = bankController.text);
                                  }
                                  return _customTextField(
                                    ctrl, 
                                    "Enter Bank Name", 
                                    node: node,
                                    onChanged: (val) {
                                      bankController.text = val;
                                      // Clear variant if bank name doesn't match a known bank exactly
                                      if (!banks.contains(val)) {
                                        variantController.clear();
                                      }
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    _buildLabel("CARD VARIANT (OPTIONAL)"),
                    Autocomplete<String>(
                      optionsBuilder: (textValue) {
                        List<String> variants = bankVariants[bankController.text.trim()] ?? [];
                        if (textValue.text.isEmpty) return variants;
                        return variants.where((v) => v.toLowerCase().contains(textValue.text.toLowerCase()));
                      },
                      onSelected: (val) => variantController.text = val,
                      fieldViewBuilder: (ctx, ctrl, node, onFixed) {
                        if (variantController.text != ctrl.text) {
                          Future.microtask(() => ctrl.text = variantController.text);
                        }
                        return _customTextField(
                          ctrl, 
                          "e.g. Amazon Pay, Regalia...", 
                          node: node,
                          onChanged: (val) => variantController.text = val,
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildLabel("CARD HOLDER"),
                    _customTextField(holderController, "FULL NAME", textCapitalization: TextCapitalization.characters),
                    const SizedBox(height: 20),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel("EXPIRY"),
                              _customTextField(
                                expiryController, 
                                "MM/YY", 
                                keyboard: TextInputType.number,
                                formatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                  ExpiryDateFormatter(),
                                ],
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
                                keyboard: TextInputType.number, 
                                obscureText: true,
                                formatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ]
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel("NETWORK"),
                              _buildNetworkDropdown(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildLabel("CREDIT LIMIT"),
                    _customTextField(limitController, "0.00", 
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 16, right: 8),
                        child: Text("₹", style: TextStyle(color: Colors.white60, fontSize: 16)),
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
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: saveCard,
                child: Text("SAVE CARD", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getNetworkBadge() {
    if (numberController.text.isEmpty) {
      return const Icon(Icons.credit_card, color: Colors.white24, size: 24);
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isDuplicate)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              "DUPLICATE",
              style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
          ),
          child: Text(
            _selectedNetwork,
            style: GoogleFonts.poppins(
              color: Colors.blueAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedNetwork,
          dropdownColor: const Color(0xFF1E293B),
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
          items: networks.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
          onChanged: (newValue) => setState(() => _selectedNetwork = newValue!),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text, style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }

  Widget _customTextField(TextEditingController ctrl, String hint, {
    TextInputType? keyboard, 
    List<TextInputFormatter>? formatters, 
    FocusNode? node, 
    Widget? suffix,
    Widget? prefix,
    bool obscureText = false,
    bool isError = false,
    TextCapitalization textCapitalization = TextCapitalization.none,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: node,
      keyboardType: keyboard,
      inputFormatters: formatters,
      obscureText: obscureText,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        prefixIcon: prefix,
        suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: suffix) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: isError ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: BorderSide(color: isError ? Colors.redAccent : Colors.blueAccent, width: 1.5),
        ),
      ),
    );
  }
}

class CardNumberFormatter extends TextInputFormatter {
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

class ExpiryDateFormatter extends TextInputFormatter {
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
