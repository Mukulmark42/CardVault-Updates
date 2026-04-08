import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/card_provider.dart';
import '../providers/security_provider.dart';
import '../providers/profile_provider.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  final LocalAuthentication auth = LocalAuthentication();
  late AnimationController _pulseController;
  final TextEditingController _pinController = TextEditingController();
  bool _showPinInput = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Automatically ask for biometric on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final security = context.read<SecurityProvider>();
    
    // If biometric is disabled, go straight to PIN if set
    if (!security.isBiometricEnabled) {
      if (security.isPinSet) {
        setState(() => _showPinInput = true);
      }
      return;
    }

    try {
      bool ok = await auth.authenticate(
        localizedReason: "Unlock CardVault",
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (ok) {
        _onUnlockSuccess();
      } else {
        // If biometric failed or was cancelled, show PIN fallback if available
        if (security.isPinSet) {
          setState(() => _showPinInput = true);
        }
      }
    } catch (e) {
      debugPrint("Authentication error: $e");
      // On error (e.g. no sensor), show PIN fallback if available
      if (security.isPinSet) {
        setState(() => _showPinInput = true);
      }
    }
  }

  Future<void> _onUnlockSuccess() async {
    if (!mounted) return;
    await context.read<CardProvider>().initializeVault();
    if (!mounted) return;
    await context.read<ProfileProvider>().refresh();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  void _handlePinInput(String value) {
    if (value.length == 4) {
      final security = context.read<SecurityProvider>();
      if (security.verifyPin(value)) {
        _onUnlockSuccess();
      } else {
        _pinController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Incorrect PIN"), 
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    final security = Provider.of<SecurityProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -50,
              child: _AmbientGlow(color: const Color(0xFF818CF8).withOpacity(0.05), size: 300),
            ),
            Positioned(
              bottom: 100,
              left: -100,
              child: _AmbientGlow(color: Colors.deepPurpleAccent.withOpacity(0.05), size: 400),
            ),
            
            SafeArea(
              child: Consumer<CardProvider>(
                builder: (context, provider, child) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  children: [
                                    const SizedBox(height: 40),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            RichText(
                                              text: TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: "Cardvault",
                                                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                                  ),
                                                  TextSpan(
                                                    text: ".secured",
                                                    style: GoogleFonts.poppins(color: const Color(0xFF818CF8), fontSize: 22, fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(user?.email ?? "Identity Verification", style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
                                          ],
                                        ),
                                        _StatusBadge(),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                Column(
                                  children: [
                                    if (!_showPinInput) ...[
                                      const SizedBox(height: 40),
                                      GestureDetector(
                                        onTap: _authenticate,
                                        child: ScaleTransition(
                                          scale: Tween(begin: 1.0, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              FadeTransition(
                                                opacity: Tween(begin: 0.1, end: 0.3).animate(_pulseController),
                                                child: Container(
                                                  width: 160,
                                                  height: 160,
                                                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF818CF8), width: 1.5)),
                                                ),
                                              ),
                                              Container(
                                                width: 130,
                                                height: 130,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.white.withOpacity(0.03),
                                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                                  boxShadow: [BoxShadow(color: const Color(0xFF818CF8).withOpacity(0.1), blurRadius: 30, spreadRadius: 2)],
                                                ),
                                                child: Center(
                                                  child: Icon(Icons.fingerprint_rounded, size: 70, color: const Color(0xFF818CF8).withOpacity(0.9)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 50),
                                      Text("Touch to Authenticate", style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20),
                                        child: Text("Place your finger on the sensor to unlock your secure vault.", textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.white38, fontSize: 14, height: 1.5)),
                                      ),
                                      const SizedBox(height: 40),
                                      const Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Divider(color: Colors.white10, thickness: 1)),
                                      const SizedBox(height: 40),
                                      if (security.isPinSet)
                                        _ActionButton(
                                          onPressed: () => setState(() => _showPinInput = true),
                                          icon: Icons.grid_3x3_rounded,
                                          label: "Use PIN Instead",
                                        ),
                                    ] else ...[
                                      const SizedBox(height: 20),
                                      Text("Enter 4-Digit PIN", style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 30),
                                      SizedBox(
                                        width: 240,
                                        child: TextField(
                                          controller: _pinController,
                                          obscureText: true,
                                          autofocus: true,
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          maxLength: 4,
                                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 32, letterSpacing: 20, fontWeight: FontWeight.bold),
                                          onChanged: _handlePinInput,
                                          decoration: const InputDecoration(
                                            counterText: "",
                                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 40),
                                      _ActionButton(
                                        onPressed: () {
                                          setState(() => _showPinInput = false);
                                          _authenticate();
                                        },
                                        icon: Icons.fingerprint_rounded,
                                        label: "Use Biometric",
                                      ),
                                    ],
                                  ],
                                ),
                                
                                Column(
                                  children: [
                                    const SizedBox(height: 40),
                                    Text("Protected by 256-bit AES Encryption.", style: GoogleFonts.poppins(color: Colors.white24, fontSize: 11)),
                                    Text("Biometric data is stored locally on device.", style: GoogleFonts.poppins(color: Colors.white24, fontSize: 11)),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _ActionButton({required this.onPressed, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 12),
              Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B).withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text("Cloud Synced", style: GoogleFonts.poppins(color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  final Color color;
  final double size;
  const _AmbientGlow({required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: size / 2, spreadRadius: size / 4)]));
  }
}
