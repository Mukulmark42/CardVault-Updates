import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/profile_model.dart';
import '../providers/profile_provider.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF020617) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Card Holder Profiles',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: Consumer<ProfileProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              // ── Info banner ──────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.deepPurpleAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Profiles help auto-unlock PDF bank statements and match bills to the right card holder.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Profile list ─────────────────────────────────────────────
              Expanded(
                child: provider.profiles.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: provider.profiles.length,
                        itemBuilder: (ctx, i) =>
                            _ProfileCard(profile: provider.profiles[i]),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProfileForm(context, null),
        backgroundColor: Colors.deepPurpleAccent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Add Profile',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline_rounded,
                color: Colors.deepPurpleAccent, size: 52),
          ),
          const SizedBox(height: 20),
          Text(
            'No Profiles Yet',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Profile" to create your\nfirst card holder profile.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  static void _showProfileForm(BuildContext context, ProfileModel? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileFormSheet(existing: existing),
    );
  }
}

// ─── Profile Card Tile ────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final ProfileModel profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.read<ProfileProvider>();

    final initials = profile.name
        .trim()
        .split(RegExp(r'\s+'))
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    final dobFormatted = profile.dob != null
        ? () {
            try {
              return DateFormat('dd MMM yyyy').format(DateTime.parse(profile.dob!));
            } catch (_) {
              return profile.dob!;
            }
          }()
        : null;

    // Generate password preview for the most common format
    String? passwordPreview;
    if (profile.pdfPasswordCandidates.isNotEmpty) {
      passwordPreview = profile.pdfPasswordCandidates.first;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: profile.isDefault
              ? Colors.deepPurpleAccent.withValues(alpha: 0.5)
              : isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.06),
          width: profile.isDefault ? 1.5 : 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          if (profile.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'DEFAULT',
                                style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurpleAccent,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (profile.email != null)
                        Text(
                          profile.email!,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Actions menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: isDark ? Colors.white54 : Colors.black38),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  itemBuilder: (_) => [
                    _menuItem('edit', Icons.edit_rounded, 'Edit', Colors.blueAccent),
                    if (!profile.isDefault)
                      _menuItem('default', Icons.star_rounded, 'Set as Default',
                          Colors.amberAccent),
                    _menuItem('delete', Icons.delete_outline_rounded, 'Delete',
                        Colors.redAccent),
                  ],
                  onSelected: (action) async {
                    if (action == 'edit') {
                      ProfilesScreen._showProfileForm(context, profile);
                    } else if (action == 'default') {
                      await provider.setDefault(profile.id!);
                    } else if (action == 'delete') {
                      _confirmDelete(context, provider, profile);
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 12),

            // ── Details row ──────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (dobFormatted != null)
                  _infoChip(
                    icon: Icons.cake_rounded,
                    label: dobFormatted,
                    color: Colors.pinkAccent,
                  ),
                if (passwordPreview != null)
                  _infoChip(
                    icon: Icons.lock_outline_rounded,
                    label: 'PDF key: $passwordPreview',
                    color: Colors.greenAccent,
                  ),
                if (profile.dob == null)
                  _infoChip(
                    icon: Icons.warning_amber_rounded,
                    label: 'Add DOB for PDF unlock',
                    color: Colors.orangeAccent,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ProfileProvider provider, ProfileModel profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Profile?',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will delete "${profile.name}". Associated cards will not be affected.',
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.deleteProfile(profile.id!);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Form Sheet ───────────────────────────────────────────────────────

class _ProfileFormSheet extends StatefulWidget {
  final ProfileModel? existing;
  const _ProfileFormSheet({this.existing});

  @override
  State<_ProfileFormSheet> createState() => _ProfileFormSheetState();
}

class _ProfileFormSheetState extends State<_ProfileFormSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _selectedDob;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final p = widget.existing!;
      _nameCtrl.text = p.name;
      _emailCtrl.text = p.email ?? '';
      _isDefault = p.isDefault;
      if (p.dob != null) {
        try { _selectedDob = DateTime.parse(p.dob!); } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String get _passwordPreview {
    final name = _nameCtrl.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final prefix = name.length >= 4 ? name.substring(0, 4) : name;
    if (_selectedDob == null) return prefix.isEmpty ? '—' : '$prefix + DDMM';
    final dd = _selectedDob!.day.toString().padLeft(2, '0');
    final mm = _selectedDob!.month.toString().padLeft(2, '0');
    return '$prefix$dd$mm';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final isEdit = widget.existing != null;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              isEdit ? 'Edit Profile' : 'New Profile',
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black),
            ),
            Text(
              'Used to auto-unlock PDF bank statements',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45),
            ),
            const SizedBox(height: 24),

            // Name field
            _label('Full Name *', isDark),
            const SizedBox(height: 6),
            _field(
              controller: _nameCtrl,
              hint: 'e.g. Sujit Gupta',
              icon: Icons.person_outline_rounded,
              isDark: isDark,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // DOB field
            _label('Date of Birth', isDark),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cake_outlined,
                        size: 20,
                        color: _selectedDob != null
                            ? Colors.deepPurpleAccent
                            : Colors.grey),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDob != null
                          ? DateFormat('dd MMMM yyyy').format(_selectedDob!)
                          : 'Select Date of Birth',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _selectedDob != null
                            ? (isDark ? Colors.white : Colors.black)
                            : Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedDob != null)
                      GestureDetector(
                        onTap: () => setState(() => _selectedDob = null),
                        child: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Email field
            _label('Email ID (optional)', isDark),
            const SizedBox(height: 6),
            _field(
              controller: _emailCtrl,
              hint: 'e.g. user@gmail.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // PDF password preview
            if (_nameCtrl.text.trim().isNotEmpty || _selectedDob != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PDF unlock password preview',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.greenAccent.withValues(alpha: 0.8)),
                          ),
                          Text(
                            _passwordPreview,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          color: Colors.greenAccent, size: 16),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _passwordPreview));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Default switch
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set as Default',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black)),
                      Text('Used as primary profile for bill matching',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white54 : Colors.black45)),
                    ],
                  ),
                ),
                Switch(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  activeColor: Colors.deepPurpleAccent,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        isEdit ? 'Save Changes' : 'Create Profile',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, bool isDark) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(
          color: isDark ? Colors.white : Colors.black, fontSize: 14),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.grey, fontSize: 14),
        prefixIcon: Icon(icon, size: 20, color: Colors.deepPurpleAccent),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.deepPurpleAccent),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(1990),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.deepPurpleAccent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name')),
      );
      return;
    }

    setState(() => _saving = true);

    final profile = ProfileModel(
      id: widget.existing?.id,
      name: name,
      dob: _selectedDob?.toIso8601String(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      isDefault: _isDefault,
    );

    final provider = context.read<ProfileProvider>();
    if (widget.existing != null) {
      await provider.updateProfile(profile);
    } else {
      await provider.addProfile(profile);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.existing != null
              ? '${profile.name} updated successfully'
              : '${profile.name} profile created'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
