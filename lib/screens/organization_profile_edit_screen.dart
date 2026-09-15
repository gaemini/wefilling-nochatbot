import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/organization_profile.dart';
import '../services/organization_account_service.dart';
import '../l10n/ui_locale.dart';

class OrganizationProfileEditScreen extends StatefulWidget {
  const OrganizationProfileEditScreen({
    super.key,
    required this.access,
  });

  final OrganizationAccess access;

  @override
  State<OrganizationProfileEditScreen> createState() =>
      _OrganizationProfileEditScreenState();
}

class _OrganizationProfileEditScreenState
    extends State<OrganizationProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _shortDescription;
  late final TextEditingController _description;
  late final TextEditingController _affiliation;
  late final TextEditingController _activityArea;
  late final TextEditingController _website;
  late final TextEditingController _contact;
  String _logoUrl = '';
  String _coverImageUrl = '';
  bool _saving = false;
  bool _uploading = false;

  OrganizationProfile get _organization => widget.access.organization!;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _organization.name);
    _shortDescription =
        TextEditingController(text: _organization.shortDescription);
    _description = TextEditingController(text: _organization.description);
    _affiliation = TextEditingController(text: _organization.affiliation);
    _activityArea = TextEditingController(text: _organization.activityArea);
    _website = TextEditingController(text: _organization.websiteUrl);
    _contact = TextEditingController(text: _organization.publicContact);
    _logoUrl = _organization.logoUrl;
    _coverImageUrl = _organization.coverImageUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _shortDescription.dispose();
    _description.dispose();
    _affiliation.dispose();
    _activityArea.dispose();
    _website.dispose();
    _contact.dispose();
    super.dispose();
  }

  String _copy(String ko, String en, String zh) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'zh'
        ? zh
        : code == 'ko'
            ? ko
            : en;
  }

  Future<void> _pickImage({required bool cover}) async {
    if (_uploading || _saving) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: cover ? 1800 : 900,
    );
    if (image == null || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _uploading = true);
    try {
      final kind = cover ? 'cover' : 'logo';
      final object = FirebaseStorage.instance.ref(
        'organization_profile_images/${widget.access.organizationId}/'
        '${kind}_${const Uuid().v4()}.jpg',
      );
      await object.putFile(
        File(image.path),
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: <String, String>{
            'organizationId': widget.access.organizationId,
            'uploaderUid': uid,
            'kind': kind,
          },
        ),
      );
      final url = await object.getDownloadURL();
      if (!mounted) return;
      setState(() {
        if (cover) {
          _coverImageUrl = url;
        } else {
          _logoUrl = url;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_copy(
          '이미지를 업로드하지 못했습니다.',
          'Could not upload the image.',
          '图片上传失败。',
        )),
      ));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _uploading || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await OrganizationAccountService.instance.updateProfile(
        widget.access.organizationId,
        <String, dynamic>{
          'name': _name.text.trim(),
          'shortDescription': _shortDescription.text.trim(),
          'description': _description.text.trim(),
          'affiliation': _affiliation.text.trim(),
          'activityArea': _activityArea.text.trim(),
          'websiteUrl': _website.text.trim(),
          'publicContact': _contact.text.trim(),
          'logoUrl': _logoUrl,
          'coverImageUrl': _coverImageUrl,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_copy(
          '단체 프로필을 저장하지 못했습니다.',
          'Could not save the organization profile.',
          '机构资料保存失败。',
        )),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: const UnderlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _copy('단체 프로필 수정', 'Edit organization', '编辑机构资料'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_copy('저장', 'Save', '保存')),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            MediaQuery.viewPaddingOf(context).bottom + 32,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _uploading ? null : () => _pickImage(cover: false),
                    icon: const Icon(Icons.account_circle_outlined, size: 20),
                    label: Text(_copy('로고', 'Logo', '标志')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _uploading ? null : () => _pickImage(cover: true),
                    icon: const Icon(Icons.image_outlined, size: 20),
                    label: Text(_copy('커버', 'Cover', '封面')),
                  ),
                ),
              ],
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              maxLength: 100,
              decoration: _decoration(_copy('단체명', 'Name', '机构名称')),
            ),
            TextField(
              controller: _shortDescription,
              maxLength: 300,
              maxLines: 2,
              decoration: _decoration(
                _copy('한 줄 소개', 'Short description', '简短介绍'),
              ),
            ),
            TextField(
              controller: _description,
              maxLength: 2000,
              minLines: 4,
              maxLines: 8,
              decoration: _decoration(_copy('소개', 'About', '介绍')),
            ),
            TextField(
              controller: _affiliation,
              maxLength: 160,
              decoration: _decoration(_copy('소속', 'Affiliation', '所属单位')),
            ),
            TextField(
              controller: _activityArea,
              maxLength: 160,
              decoration: _decoration(_copy('활동 지역', 'Activity area', '活动地区')),
            ),
            TextField(
              controller: _website,
              maxLength: 2000,
              keyboardType: TextInputType.url,
              decoration: _decoration(_copy('웹사이트', 'Website', '网站')),
            ),
            TextField(
              controller: _contact,
              maxLength: 320,
              decoration:
                  _decoration(_copy('공개 연락처', 'Public contact', '公开联系方式')),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving || _uploading ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.pointColor,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.2,
                      ),
                    )
                  : Text(_copy('저장', 'Save', '保存')),
            ),
          ],
        ),
      ),
    );
  }
}
