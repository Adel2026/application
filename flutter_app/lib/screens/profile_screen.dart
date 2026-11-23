import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/app_icon_service.dart';
import '../core/contact_picker_service.dart';
import '../core/database/database_service.dart';
import '../widgets/section_top_bar.dart';
import '../widgets/circular_image_cropper_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.database, this.onBack});

  final DatabaseService database;
  final VoidCallback? onBack;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _centerNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();
  final _facebookController = TextEditingController();
  final _youtubeController = TextEditingController();

  String? _photoPath;
  String _avatarEmoji = '👨‍🏫';
  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _emojiOptions = [
    '👨‍🏫', '👩‍🏫', '🧑‍🏫', '🎓', '📚', '⭐', '💡', '🔬', '📐', '🎯', '✨', '🏆'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _centerNameController.dispose();
    _nameController.dispose();
    _titleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.database.getSetting('teacher_name', defaultValue: 'أ. أحمد السيد'),
      widget.database.getSetting('teacher_title', defaultValue: 'خبير ومحاضر أول'),
      widget.database.getSetting('teacher_phone', defaultValue: '01012345678'),
      widget.database.getSetting('teacher_email', defaultValue: 'teacher@edu-academy.com'),
      widget.database.getSetting('teacher_bio', defaultValue: 'خبرة تدريسية لأكثر من 15 عاماً في تبسيط المناهج.'),
      widget.database.getSetting('teacher_facebook', defaultValue: ''),
      widget.database.getSetting('teacher_youtube', defaultValue: ''),
      widget.database.getSetting('teacher_photo_path', defaultValue: ''),
      widget.database.getSetting('teacher_avatar', defaultValue: '👨‍🏫'),
      widget.database.getSetting('center_name', defaultValue: 'أكاديمية المستقبل'),
    ]);

    if (mounted) {
      setState(() {
        _centerNameController.text = results[9];
        _nameController.text = results[0];
        _titleController.text = results[1];
        _phoneController.text = results[2];
        _emailController.text = results[3];
        _bioController.text = results[4];
        _facebookController.text = results[5];
        _youtubeController.text = results[6];
        final photo = results[7];
        _photoPath = (photo.isNotEmpty && File(photo).existsSync()) ? photo : null;
        _avatarEmoji = results[8].isNotEmpty ? results[8] : '👨‍🏫';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isNotEmpty && result.first.path != null) {
        final pickedPath = result.first.path!;

        if (!mounted) return;
        final croppedFile = await CircularImageCropper.cropImage(
          context,
          imagePath: pickedPath,
          title: 'صورة البروفايل الشخصي',
        );
        if (croppedFile == null) return;

        final appDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(croppedFile.path).isEmpty ? '.png' : p.extension(croppedFile.path);
        final targetFileName = 'teacher_avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
        final savedFile = await croppedFile.copy(p.join(appDir.path, targetFileName));

        setState(() {
          _photoPath = savedFile.path;
        });

        await widget.database.setSetting('teacher_photo_path', savedFile.path);
        await widget.database.setSetting('custom_logo_path', savedFile.path);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('تم قص وضبط وحفظ صورة البروفايل بنجاح 🌟', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('تعذر اختيار الصورة: $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    setState(() {
      _photoPath = null;
    });
    await widget.database.setSetting('teacher_photo_path', '');
    await widget.database.setSetting('custom_logo_path', '');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF334155),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('تم إزالة الصورة واستعادة الرمز الافتراضي', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_centerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم السنتر أو الأكاديمية أولاً')),
      );
      return;
    }

    setState(() => _isSaving = true);
    await widget.database.setSetting(
      'center_name',
      _centerNameController.text.trim(),
    );
    await widget.database.setSetting('teacher_name', _nameController.text.trim());
    await widget.database.setSetting('teacher_title', _titleController.text.trim());
    await widget.database.setSetting('teacher_phone', _phoneController.text.trim());
    await widget.database.setSetting('teacher_email', _emailController.text.trim());
    await widget.database.setSetting('teacher_bio', _bioController.text.trim());
    await widget.database.setSetting('teacher_facebook', _facebookController.text.trim());
    await widget.database.setSetting('teacher_youtube', _youtubeController.text.trim());
    await widget.database.setSetting('teacher_avatar', _avatarEmoji);
    if (_photoPath != null) {
      await widget.database.setSetting('teacher_photo_path', _photoPath!);
      await widget.database.setSetting('custom_logo_path', _photoPath!);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('تم حفظ بيانات البروفايل وتحديث المنصة فوراً ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: SectionTopBar(
          title: 'الملف الشخصي',
          icon: Icons.person_rounded,
          onBack: widget.onBack,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                child: Column(
                  children: [
                    // --- 1. Photo & Avatar Hero Card ---
                    _buildPhotoHeroCard(isDark),
                    const SizedBox(height: 16),

                    // --- 2. Emoji Avatar Selection Strip ---
                    _buildEmojiPickerStrip(isDark),
                    const SizedBox(height: 16),

                    _buildSectionCard(
                      isDark: isDark,
                      title: 'بيانات السنتر / الأكاديمية',
                      icon: Icons.apartment_rounded,
                      iconColor: const Color(0xFF10B981),
                      children: [
                        _buildInputField(
                          controller: _centerNameController,
                          label: 'اسم السنتر أو الأكاديمية',
                          hint: 'مثال: أكاديمية المستقبل',
                          icon: Icons.apartment_rounded,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- 3. Personal & Professional Details ---
                    _buildSectionCard(
                      isDark: isDark,
                      title: 'البيانات الأساسية والمهنية',
                      icon: Icons.badge_rounded,
                      iconColor: const Color(0xFF38BDF8),
                      children: [
                        _buildInputField(
                          controller: _nameController,
                          label: 'اسم المعلم / المحاضر',
                          hint: 'مثال: أ. أحمد السيد',
                          icon: Icons.person_outline_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _titleController,
                          label: 'المسمى الوظيفي / التخصص',
                          hint: 'مثال: خبير أول رياضيات وفيزياء',
                          icon: Icons.school_outlined,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _bioController,
                          label: 'النبذة التعريفية والخبرات',
                          hint: 'اكتب نبذة مختصرة عن مسيرتك وخبراتك...',
                          icon: Icons.notes_rounded,
                          isDark: isDark,
                          maxLines: 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- 4. Contact & Channels Details ---
                    _buildSectionCard(
                      isDark: isDark,
                      title: 'قنوات التواصل والتفاعل',
                      icon: Icons.contact_phone_rounded,
                      iconColor: const Color(0xFF10B981),
                      children: [
                        _buildInputField(
                          controller: _phoneController,
                          label: 'رقم هاتف العمل / واتساب',
                          hint: '010XXXXXXXX',
                          icon: Icons.phone_outlined,
                          isDark: isDark,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _emailController,
                          label: 'البريد الإلكتروني الرسمي',
                          hint: 'teacher@edu-academy.com',
                          icon: Icons.alternate_email_rounded,
                          isDark: isDark,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _facebookController,
                          label: 'رابط صفحة فيسبوك أو المجموعة',
                          hint: 'https://facebook.com/...',
                          icon: Icons.public_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _youtubeController,
                          label: 'رابط قناة يوتيوب التعليمية',
                          hint: 'https://youtube.com/@...',
                          icon: Icons.play_circle_outline_rounded,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // --- Save Button ---
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F2FE),
                          foregroundColor: const Color(0xFF021024),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          shadowColor: const Color(0x6600F2FE),
                        ),
                        onPressed: _isSaving ? null : _saveProfile,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF021024)),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 22),
                        label: Text(
                          _isSaving ? 'جاري الحفظ...' : 'حفظ تعديلات الملف الشخصي',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPhotoHeroCard(bool isDark) {
    final bool hasPhoto = _photoPath != null && _photoPath!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F2FE), Color(0xFF0284C7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F2FE).withValues(alpha: isDark ? 0.4 : 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF080E1C) : Colors.white,
                    ),
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.file(
                              File(_photoPath!),
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Text(
                                _avatarEmoji,
                                style: const TextStyle(fontSize: 44),
                              ),
                            ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: _pickPhoto,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F2FE),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF080E1C) : Colors.white,
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, size: 16, color: Color(0xFF021024)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _nameController.text.isNotEmpty ? _nameController.text : 'أ. أحمد السيد',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 3),
          Text(
            _titleController.text.isNotEmpty ? _titleController.text : 'خبير ومحاضر أول',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00F2FE),
                  side: const BorderSide(color: Color(0xFF00F2FE)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('تغيير الصورة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _pickPhoto,
              ),
              if (hasPhoto) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('حذف الصورة', style: TextStyle(fontSize: 12)),
                  onPressed: _removePhoto,
                ),
              ],
            ],
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                foregroundColor: const Color(0xFF00F2FE),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.app_shortcut_rounded, size: 16),
              label: const Text(
                'تثبيت كأيقونة للتطبيق على الشاشة الرئيسية 📱',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                try {
                  final name = _nameController.text.trim().isNotEmpty
                      ? _nameController.text.trim()
                      : 'سنتر أستاذي';
                  await AppIconService.setCustomAppIconAndPin(
                    database: widget.database,
                    sourceImagePath: _photoPath!,
                    customAppName: name,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: const Color(0xFF059669),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text('تم إرسال طلب تثبيت الأيقونة للشاشة الرئيسية بنجاح 📱',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.red.shade700,
                        content: Text('حدث خطأ: $e', style: const TextStyle(color: Colors.white)),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmojiPickerStrip(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_emotions_outlined, color: Colors.amber, size: 18),
              SizedBox(width: 6),
              Text('أو اختر رمزا تعبيرياً للبروفايل:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _emojiOptions.map((emoji) {
                final isSelected = _avatarEmoji == emoji && (_photoPath == null || _photoPath!.isEmpty);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _avatarEmoji = emoji;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00F2FE).withValues(alpha: 0.25)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00F2FE) : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0x3338BDF8) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 11.5, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF00F2FE)),
            suffixIcon: keyboardType == TextInputType.phone
                ? IconButton(
                    icon: const Icon(Icons.contacts_rounded, color: Color(0xFF10B981), size: 18),
                    tooltip: 'اختيار من دليل الهاتف',
                    onPressed: () async {
                      final contact = await ContactPickerService.pickContact();
                      if (contact != null && contact.phone.isNotEmpty) {
                        controller.text = contact.phone;
                      }
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: isDark ? const Color(0xFF080F1E) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00F2FE), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          ),
        ),
      ],
    );
  }
}
