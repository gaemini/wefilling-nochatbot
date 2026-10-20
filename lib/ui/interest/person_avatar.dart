import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/cache/app_image_cache_manager.dart';
import '../../utils/country_flag_helper.dart';

/// 사람 아바타(카드 48 / 목록 52). 사진이 없으면 uid로 고른 색의 이니셜 원.
/// [nationality]가 있으면 오른쪽 아래에 국기 배지(20, 흰 2px 테두리, -3 밖으로 걸침).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.uid,
    required this.name,
    this.photoUrl,
    this.nationality,
    this.size = 48,
  });

  final String uid;
  final String name;
  final String? photoUrl;

  /// 한글 국가명(CountryFlagHelper 입력값).
  final String? nationality;
  final double size;

  static const _backgrounds = [
    Color(0xFFDBE4F0),
    Color(0xFFE8E0F2),
    Color(0xFFDDEFE6),
    Color(0xFFF5E6D8),
    Color(0xFFF1E3E3),
    Color(0xFFE2E8EE),
  ];

  /// uid 해시로 고른 바탕색(같은 사람은 늘 같은 색).
  static Color backgroundFor(String uid) {
    var hash = 0;
    for (final unit in uid.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _backgrounds[hash % _backgrounds.length];
  }

  @override
  Widget build(BuildContext context) {
    final background = backgroundFor(uid);
    final initial = name.trim().characters.isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final fallback = ColoredBox(
      color: background,
      child: Center(
        child: Text(
          initial,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size * .4,
            fontWeight: FontWeight.w800,
            color: Color.lerp(background, Colors.black, .55),
            height: 1,
          ),
        ),
      ),
    );
    final photo = (photoUrl ?? '').trim();
    final flag = (nationality ?? '').trim().isEmpty
        ? null
        : CountryFlagHelper.getCountryInfo(nationality!.trim())?.emoji;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: size,
              child: photo.startsWith('https://')
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      cacheManager: AppImageCacheManager.instance,
                      fit: BoxFit.cover,
                      memCacheWidth: (size * 3).round(),
                      fadeInDuration: Duration.zero,
                      placeholder: (_, __) => fallback,
                      errorWidget: (_, __, ___) => fallback,
                    )
                  : fallback,
            ),
          ),
          if (flag != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                key: const ValueKey('person-avatar-flag'),
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(flag,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 12, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 나라 이름(화면 언어). 모르면 ''.
String countryNameOf(String? nationality, String languageCode) {
  final raw = (nationality ?? '').trim();
  if (raw.isEmpty) return '';
  return CountryFlagHelper.getCountryInfo(raw)?.getLocalizedName(languageCode) ??
      raw;
}
