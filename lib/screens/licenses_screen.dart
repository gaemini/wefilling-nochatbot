// lib/screens/licenses_screen.dart
// 오픈소스 라이선스 페이지

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.openSourceLicenses ?? "오픈소스 라이선스",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body: FutureBuilder<LicenseData>(
        future: _loadLicenses(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading licenses',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            );
          }

          final licenseData = snapshot.data!;

          return Column(
            children: [
              // 헤더 정보
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Wefilling',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Powered by Flutter',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '라이선스 ${licenseData.packages.length}개',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              // 라이선스 목록
              Expanded(
                child: ListView.separated(
                  itemCount: licenseData.packages.length,
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    color: Color(0xFFF3F4F6),
                  ),
                  itemBuilder: (context, index) {
                    final package = licenseData.packages[index];
                    return _buildLicenseItem(
                      context,
                      package,
                      licenseData.packageLicenseBindings[package]!,
                      licenseData.licenses,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLicenseItem(
    BuildContext context,
    String packageName,
    List<int> licenseIndices,
    List<LicenseEntry> licenses,
  ) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LicenseDetailScreen(
              packageName: packageName,
              licenseIndices: licenseIndices,
              licenses: licenses,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    packageName,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '라이선스 ${licenseIndices.length}개',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF9CA3AF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<LicenseData> _loadLicenses() async {
    final licenses = <LicenseEntry>[];
    final packageLicenseBindings = <String, List<int>>{};
    final packages = <String>[];

    await for (final license in LicenseRegistry.licenses) {
      licenses.add(license);
      for (final package in license.packages) {
        if (!packageLicenseBindings.containsKey(package)) {
          packageLicenseBindings[package] = [];
          packages.add(package);
        }
        packageLicenseBindings[package]!.add(licenses.length - 1);
      }
    }

    packages.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return LicenseData(
      packages: packages,
      packageLicenseBindings: packageLicenseBindings,
      licenses: licenses,
    );
  }
}

class LicenseData {
  final List<String> packages;
  final Map<String, List<int>> packageLicenseBindings;
  final List<LicenseEntry> licenses;

  LicenseData({
    required this.packages,
    required this.packageLicenseBindings,
    required this.licenses,
  });
}

class LicenseDetailScreen extends StatelessWidget {
  final String packageName;
  final List<int> licenseIndices;
  final List<LicenseEntry> licenses;

  const LicenseDetailScreen({
    Key? key,
    required this.packageName,
    required this.licenseIndices,
    required this.licenses,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          packageName,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              packageName,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 24),
            ...licenseIndices.map((index) {
              final license = licenses[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...license.paragraphs.map((paragraph) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          paragraph.text,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: paragraph.indent == 0 ? 15 : 14,
                            height: 1.7,
                            color: const Color(0xFF374151),
                            letterSpacing: -0.2,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
