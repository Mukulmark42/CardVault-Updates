import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../models/card_model.dart';

class CreditCardWidget extends StatefulWidget {
  final CardModel card;
  final bool showControls;

  const CreditCardWidget({
    super.key, 
    required this.card, 
    this.showControls = true,
  });

  @override
  State<CreditCardWidget> createState() => _CreditCardWidgetState();
}

class _CreditCardWidgetState extends State<CreditCardWidget> {
  bool _showCvv = false;
  bool _showNumber = false;
  Timer? _numberHideTimer;
  Timer? _cvvHideTimer;

  late List<Color> _bankColors;
  late String _bankDomain;
  late String _network;

  @override
  void initState() {
    super.initState();
    _bankColors = _getBankGradient(widget.card.bank);
    _bankDomain = _getDomainForBank(widget.card.bank);
    _network = widget.card.network.toUpperCase();
  }

  @override
  void didUpdateWidget(CreditCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.bank != widget.card.bank) {
      _bankColors = _getBankGradient(widget.card.bank);
      _bankDomain = _getDomainForBank(widget.card.bank);
    }
    if (oldWidget.card.network != widget.card.network) {
      _network = widget.card.network.toUpperCase();
    }
  }

  @override
  void dispose() {
    _numberHideTimer?.cancel();
    _cvvHideTimer?.cancel();
    super.dispose();
  }

  void _toggleNumberVisibility() {
    if (!widget.showControls) return;
    setState(() => _showNumber = !_showNumber);
    _numberHideTimer?.cancel();
    if (_showNumber) {
      _numberHideTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showNumber = false);
      });
    }
  }

  void _toggleCvvVisibility() {
    if (!widget.showControls) return;
    setState(() => _showCvv = !_showCvv);
    _cvvHideTimer?.cancel();
    if (_showCvv) {
      _cvvHideTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showCvv = false);
      });
    }
  }

  List<Color> _getBankGradient(String bankName) {
    String bank = bankName.toLowerCase();
    if (bank.contains("hdfc")) return [const Color(0xFF004C8F), const Color(0xFF002E56)];
    if (bank.contains("icici")) return [const Color(0xFFF27020), const Color(0xFFB34A00)];
    if (bank.contains("sbi") || bank.contains("state bank")) return [const Color(0xFF25A8E0), const Color(0xFF006699)];
    if (bank.contains("axis")) return [const Color(0xFF97144D), const Color(0xFF5A0C2E)];
    if (bank.contains("kotak")) return [const Color(0xFFED1C24), const Color(0xFF990000)];
    if (bank.contains("amex") || bank.contains("american")) return [const Color(0xFF007BC1), const Color(0xFF004B76)];
    if (bank.contains("idfc")) return [const Color(0xFF91171A), const Color(0xFF4D0C0E)];
    if (bank.contains("rbl")) return [const Color(0xFF005697), const Color(0xFF002B4B)];
    if (bank.contains("yes")) return [const Color(0xFF0054A6), const Color(0xFF003366)];
    if (bank.contains("indusind")) return [const Color(0xFF622424), const Color(0xFF3B1515)];
    if (bank.contains("federal")) return [const Color(0xFF004082), const Color(0xFF00264D)];
    if (bank.contains("baroda") || bank.contains("bob")) return [const Color(0xFFFF6600), const Color(0xFFB34700)];
    if (bank.contains("pnb") || bank.contains("punjab")) return [const Color(0xFFA12830), const Color(0xFF7D1F25)];
    if (bank.contains("canara")) return [const Color(0xFF0091D5), const Color(0xFF006B9E)];
    if (bank.contains("idbi")) return [const Color(0xFF00613F), const Color(0xFF004029)];
    if (bank.contains("hsbc")) return [const Color(0xFFDB0011), const Color(0xFFAA000D)];
    if (bank.contains("standard") || bank.contains("sc ")) return [const Color(0xFF008540), const Color(0xFF00612F)];
    if (bank.contains("citi")) return [const Color(0xFF056DAE), const Color(0xFF034B79)];
    if (bank.contains("au small") || bank.contains("au bank")) return [const Color(0xFFE31E24), const Color(0xFFA1151A)];
    return [const Color(0xFF1E293B), const Color(0xFF0F172A)];
  }

  String _getDomainForBank(String bank) {
    String b = bank.toLowerCase();
    
    if (b.contains("axis")) return "axisbank.com";
    if (b.contains("federal")) return "federalbank.co.in";
    if (b.contains("hdfc")) return "hdfcbank.com";
    if (b.contains("icici")) return "icicibank.com";
    if (b.contains("indusind")) return "indusind.com";
    if (b.contains("idfc")) return "idfcfirstbank.com";
    if (b.contains("kotak")) return "kotak.com";
    if (b.contains("rbl")) return "rblbank.com";
    if (b.contains("yes")) return "yesbank.in";

    if (b.contains("baroda") || b.contains("bob")) return "bankofbaroda.in";
    if (b.contains("bank of india") || b.contains("boi")) return "bankofindia.co.in";
    if (b.contains("canara")) return "canarabank.com";
    if (b.contains("central bank")) return "centralbankofindia.co.in";
    if (b.contains("indian bank")) return "indianbank.in";
    if (b.contains("pnb") || b.contains("punjab national")) return "pnbindia.in";
    if (b.contains("sbi") || b.contains("state bank")) return "sbi.co.in";
    if (b.contains("uco")) return "ucobank.com"; 
    if (b.contains("union bank")) return "unionbankofindia.co.in";

    if (b.contains("dbs")) return "dbs.com";
    if (b.contains("deutsche")) return "db.com";
    if (b.contains("hsbc")) return "hsbc.co.in";
    if (b.contains("standard") || bank.contains("sc ")) return "sc.com";
    if (b.contains("au small") || b.contains("au bank")) return "aubank.in";
    
    return "";
  }

  Widget _buildBankLogo() {
    if (_bankDomain.isEmpty) return _buildInitialsFallback();
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(5)),
      child: CachedNetworkImage(
        imageUrl: "https://logo.clearbit.com/$_bankDomain",
        height: 20, width: 20, memCacheHeight: 40, memCacheWidth: 40, fit: BoxFit.contain,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _buildInitialsFallback(),
        errorWidget: (context, url, error) => CachedNetworkImage(
          imageUrl: "https://www.google.com/s2/favicons?sz=64&domain=$_bankDomain",
          height: 20, width: 20, placeholder: (c, u) => _buildInitialsFallback(),
          errorWidget: (c, u, e) => _buildInitialsFallback(),
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
        ),
      ),
    );
  }

  Widget _buildInitialsFallback() {
    String iconText = widget.card.bank.split(' ').first.toUpperCase();
    if (iconText.length > 4) iconText = iconText.substring(0, 4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(iconText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
    );
  }

  Widget _buildNetworkLogo() {
    String url = ""; double height = 16;
    if (_network == "VISA") url = "https://resources.checkout.com/docs/images/payment-methods/visa.png";
    else if (_network == "MASTERCARD") url = "https://resources.checkout.com/docs/images/payment-methods/mastercard.png";
    else if (_network == "AMEX") { url = "https://resources.checkout.com/docs/images/payment-methods/american-express.png"; height = 13; }
    else if (_network == "RUPAY") { 
      url = "https://www.vectorlogo.zone/logos/rupay/rupay-ar21.png"; 
      height = 14; 
    }

    if (url.isEmpty) return Text(_network, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic));
    return CachedNetworkImage(
      imageUrl: url, 
      height: height, 
      fit: BoxFit.contain,
      memCacheHeight: (height * 2).toInt(),
      cacheKey: url,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      color: _network == "RUPAY" ? Colors.white : null,
      placeholder: (context, url) => Text(_network, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
      errorWidget: (context, url, error) => Text(_network, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
    );
  }

  void _copyToClipboard(String text, String message) {
    if (!widget.showControls) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1)));
  }

  String _formatLimit(num limit) {
    if (limit <= 0) return "0L";
    double lakhs = limit.toDouble() / 100000;
    String formatted = lakhs.toStringAsFixed(1);
    if (formatted.endsWith('.0')) formatted = formatted.substring(0, formatted.length - 2);
    return "${formatted}L";
  }

  @override
  Widget build(BuildContext context) {
    double percent = widget.card.creditLimit > 0 ? (widget.card.spent / widget.card.creditLimit).clamp(0.0, 1.0) : 0.0;

    return Container(
      constraints: const BoxConstraints(minHeight: 172),
      margin: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [_bankColors[0], _bankColors[1], _bankColors[1].withBlue(math.min(255, _bankColors[1].blue + 25))],
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 7, offset: const Offset(0, 3.5))],
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(painter: CardNoisePainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.card.bank.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.9), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (widget.card.variant.isNotEmpty)
                            Text(widget.card.variant.toUpperCase(), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w500, fontSize: 10.5, letterSpacing: 0.4), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildBankLogo(),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 30, height: 20,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE5B567), Color(0xFFC09040)]), borderRadius: BorderRadius.circular(3.5)),
                    ),
                    if (widget.showControls)
                      IconButton(
                        onPressed: () => _copyToClipboard(widget.card.number, "Card number copied"),
                        icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 17),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _showNumber ? widget.card.number : widget.card.number.length >= 4 ? "**** **** **** ${widget.card.number.substring(widget.card.number.length - 4)}" : widget.card.number,
                        style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 20, letterSpacing: 1.1, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.showControls)
                      IconButton(
                        icon: Icon(_showNumber ? Icons.visibility_off : Icons.visibility, color: Colors.white38, size: 20),
                        onPressed: _toggleNumberVisibility,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        onTap: () => _copyToClipboard(widget.card.holder, "Card holder name copied"),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("CARD HOLDER", style: TextStyle(fontSize: 8.5, color: Colors.white38, fontWeight: FontWeight.bold, letterSpacing: 0.9)),
                            Text(widget.card.holder.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: () => _copyToClipboard(widget.card.expiry, "Expiry date copied"),
                        child: Column(
                          children: [
                            const Text("EXPIRY", style: TextStyle(fontSize: 8.5, color: Colors.white38, fontWeight: FontWeight.bold, letterSpacing: 0.9)),
                            Text(widget.card.expiry, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildNetworkLogo(),
                          const SizedBox(height: 5),
                          GestureDetector(
                            onTap: () {
                              if (widget.showControls) {
                                _copyToClipboard(widget.card.cvv, "CVV copied");
                              }
                            },
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(_showCvv ? widget.card.cvv : "***", style: const TextStyle(color: Colors.white, fontSize: 13)),
                                if (widget.showControls) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(onTap: _toggleCvvVisibility, child: Icon(_showCvv ? Icons.visibility_off : Icons.visibility, size: 15, color: Colors.white38)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: LinearProgressIndicator(value: percent, backgroundColor: Colors.white.withOpacity(0.1), color: Colors.white.withOpacity(0.6), minHeight: 1.8),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text("Limit: ${_formatLimit(widget.card.creditLimit)}", style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CardNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint()..color = Colors.white.withOpacity(0.012)..strokeWidth = 1.0;
    final List<Offset> points = List.generate(80, (_) => Offset(random.nextDouble() * size.width, random.nextDouble() * size.height));
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
