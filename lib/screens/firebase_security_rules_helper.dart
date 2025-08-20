import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class FirebaseSecurityRulesHelper extends StatelessWidget {
  final String projectId;

  const FirebaseSecurityRulesHelper({
    Key? key,
    required this.projectId,
  }) : super(key: key);

  final String securityRules = '''
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read: if true;  // 모든 사용자에게 읽기 권한 허용
      allow write: if request.auth != null;  // 인증된 사용자에게만 쓰기 권한 허용
    }
  }
}
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Storage 문제 해결'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 문제 설명
            const Text(
              '게시글 이미지가 표시되지 않는 문제',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '이미지가 표시되지 않는 주된 원인은 Firebase Storage 보안 규칙 설정 때문일 가능성이 높습니다. '
              '현재 규칙이 모든 사용자의 이미지 읽기를 허용하지 않기 때문입니다.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            
            // 해결 방법
            const Text(
              '해결 방법',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '1. Firebase 콘솔에서 Storage 규칙을 수정해야 합니다.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            
            // Firebase 콘솔 링크
            ElevatedButton.icon(
              onPressed: () {
                _launchFirebaseConsole();
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Firebase 콘솔 열기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 24),
            const Text(
              '2. 아래 보안 규칙을 복사하여 Firebase 콘솔의 규칙 편집기에 붙여넣기 하세요.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            
            // 보안 규칙 코드 블록
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    securityRules,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      _copyToClipboard(context);
                    },
                    icon: const Icon(Icons.content_copy),
                    label: const Text('규칙 복사'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            const Text(
              '3. "규칙 게시" 버튼을 클릭하여 변경사항을 저장하세요.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              '4. 앱을 다시 시작하면 이미지가 정상적으로 표시될 것입니다.',
              style: TextStyle(fontSize: 16),
            ),
            
            const SizedBox(height: 32),
            // 주의사항
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '참고: 위 보안 규칙은 모든 사용자가 이미지를 볼 수 있도록 허용하지만, '
                      '업로드는 로그인한 사용자만 가능하도록 설정합니다. 프로덕션 환경에서는 '
                      '더 세분화된 보안 규칙을 설정하는 것이 좋습니다.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _launchFirebaseConsole() async {
    final url = 'https://console.firebase.google.com/project/$projectId/storage/rules';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      print('Could not launch $url');
    }
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: securityRules));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('보안 규칙이 클립보드에 복사되었습니다.')),
    );
  }
}