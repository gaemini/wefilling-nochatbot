// lib/screens/privacy_policy_screen.dart
// 개인정보 처리방침 페이지

import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('개인정보 처리방침'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        '개인정보 처리방침 안내',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '위플링은 개인정보보호법에 따라 이용자의 개인정보 보호 및 권익을 보호하고 개인정보와 관련한 이용자의 고충을 원활하게 처리할 수 있도록 다음과 같은 처리방침을 두고 있습니다.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            _buildSection(
              '제1조 개인정보의 처리목적',
              '''위플링은 다음의 목적을 위하여 개인정보를 처리합니다. 처리하고 있는 개인정보는 다음의 목적 이외의 용도로는 이용되지 않으며, 이용 목적이 변경되는 경우에는 개인정보보호법 제18조에 따라 별도의 동의를 받는 등 필요한 조치를 이행할 예정입니다.

1. 회원가입 및 관리
   - 회원 가입의사 확인, 회원제 서비스 제공에 따른 본인 식별·인증, 회원자격 유지·관리, 서비스 부정이용 방지 목적으로 개인정보를 처리합니다.

2. 서비스 제공
   - 모임 생성 및 참여, 게시물 작성, 댓글 작성, 사용자 간 소통 서비스 제공을 목적으로 개인정보를 처리합니다.

3. 고충처리
   - 민원인의 신원 확인, 민원사항 확인, 사실조사를 위한 연락·통지, 처리결과 통보의 목적으로 개인정보를 처리합니다.''',
            ),

            _buildSection(
              '제2조 개인정보의 처리 및 보유기간',
              '''1. 위플링은 법령에 따른 개인정보 보유·이용기간 또는 정보주체로부터 개인정보를 수집 시에 동의받은 개인정보 보유·이용기간 내에서 개인정보를 처리·보유합니다.

2. 각각의 개인정보 처리 및 보유 기간은 다음과 같습니다.
   - 회원가입 및 관리 : 회원탈퇴 시까지
   - 서비스 제공 : 서비스 이용계약 종료 시까지
   - 고충처리 : 고충 처리 완료 후 3년''',
            ),

            _buildSection(
              '제3조 개인정보의 제3자 제공',
              '''위플링은 정보주체의 개인정보를 제1조(개인정보의 처리목적)에서 명시한 범위 내에서만 처리하며, 정보주체의 동의, 법률의 특별한 규정 등 개인정보보호법 제17조에 해당하는 경우에만 개인정보를 제3자에게 제공합니다.

현재 위플링은 개인정보를 제3자에게 제공하지 않습니다.''',
            ),

            _buildSection(
              '제4조 개인정보처리의 위탁',
              '''1. 위플링은 원활한 개인정보 업무처리를 위하여 다음과 같이 개인정보 처리업무를 위탁하고 있습니다.

- 위탁받는 자: Firebase (Google LLC)
- 위탁하는 업무의 내용: 회원관리, 서비스 제공을 위한 시스템 운영
- 위탁기간: 서비스 제공기간

2. 위플링은 위탁계약 체결시 개인정보보호법 제26조에 따라 위탁업무 수행목적 외 개인정보 처리금지, 기술적·관리적 보호조치, 재위탁 제한, 수탁자에 대한 관리·감독, 손해배상 등 책임에 관한 사항을 계약서 등 문서에 명시하고, 수탁자가 개인정보를 안전하게 처리하는지를 감독하고 있습니다.''',
            ),

            _buildSection(
              '제5조 정보주체의 권리·의무 및 행사방법',
              '''1. 정보주체는 위플링에 대해 언제든지 다음 각 호의 개인정보 보호 관련 권리를 행사할 수 있습니다.
   - 개인정보 처리정지 요구
   - 개인정보 열람요구
   - 개인정보 정정·삭제요구
   - 개인정보 처리정지 요구

2. 제1항에 따른 권리 행사는 위플링에 대해 개인정보보호법 시행규칙 별지 제8호 서식에 따라 서면, 전자우편, 모사전송(FAX) 등을 통하여 하실 수 있으며 위플링은 이에 대해 지체없이 조치하겠습니다.

3. 정보주체가 개인정보의 오류 등에 대한 정정 또는 삭제를 요구한 경우에는 위플링은 정정 또는 삭제를 완료할 때까지 당해 개인정보를 이용하거나 제공하지 않습니다.''',
            ),

            _buildSection(
              '제6조 처리하는 개인정보 항목',
              '''위플링은 다음의 개인정보 항목을 처리하고 있습니다.

1. 필수항목
   - 이메일 주소, 닉네임, 프로필 사진(선택)

2. 자동 수집 항목
   - 서비스 이용 기록, 접속 로그, 쿠키, 접속 IP 정보, 기기정보''',
            ),

            _buildSection(
              '제7조 개인정보의 파기',
              '''1. 위플링은 개인정보 보유기간의 경과, 처리목적 달성 등 개인정보가 불필요하게 되었을 때에는 지체없이 해당 개인정보를 파기합니다.

2. 개인정보 파기의 절차 및 방법은 다음과 같습니다.
   - 파기절차: 불필요한 개인정보 및 개인정보파일은 개인정보보호책임자의 승인을 받아 파기합니다.
   - 파기방법: 전자적 파일 형태의 정보는 기록을 재생할 수 없는 기술적 방법을 사용합니다.''',
            ),

            _buildSection(
              '제8조 개인정보의 안전성 확보조치',
              '''위플링은 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.

1. 관리적 조치: 내부관리계획 수립·시행, 정기적 직원 교육 등
2. 기술적 조치: 개인정보처리시스템 등의 접근권한 관리, 접근통제시스템 설치, 고유식별정보 등의 암호화, 보안프로그램 설치
3. 물리적 조치: 전산실, 자료보관실 등의 접근통제''',
            ),

            _buildSection(
              '제9조 개인정보 보호책임자',
              '''위플링은 개인정보 처리에 관한 업무를 총괄해서 책임지고, 개인정보 처리와 관련한 정보주체의 불만처리 및 피해구제 등을 위하여 아래와 같이 개인정보 보호책임자를 지정하고 있습니다.

▶ 개인정보 보호책임자
- 성명: 위플링 개발팀
- 연락처: support@wefilling.com

※ 개인정보 보호 담당부서로 연결됩니다.

▶ 개인정보 보호 담당부서
- 부서명: 개발팀
- 담당자: 위플링 개발팀
- 연락처: support@wefilling.com''',
            ),

            _buildSection(
              '제10조 권익침해 구제방법',
              '''정보주체는 아래의 기관에 대해 개인정보 침해신고, 상담등을 문의하실 수 있습니다.

▶ 개인정보 침해신고센터 (privacy.go.kr)
- 신고전화: 국번없이 182
- 주소: (01300) 서울특별시 중구 세종대로 209 정부서울청사 4층

▶ 개인정보 분쟁조정위원회 (www.kopico.go.kr)
- 신고전화: 국번없이 1833-6972
- 주소: (03171) 서울특별시 종로구 세종대로 209 정부서울청사 4층

▶ 대검찰청 사이버범죄수사단 (www.spo.go.kr)
- 신고전화: 국번없이 1301

▶ 경찰청 사이버테러대응센터 (cyberbureau.police.go.kr)
- 신고전화: 국번없이 182''',
            ),

            const SizedBox(height: 32),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_outlined, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      const Text(
                        '중요 안내',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '본 개인정보 처리방침은 일반적인 템플릿을 기반으로 작성되었습니다.\n'
                    '실제 서비스 운영 시에는 반드시 개인정보보호 전문가나 법무법인의 검토를 받아 '
                    '해당 서비스의 개인정보 처리 현황과 관련 법령에 맞게 수정해야 합니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange[800],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '부칙',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '이 개인정보 처리방침은 2025년 9월 25일부터 적용됩니다.\n'
                    '이전의 개인정보 처리방침은 아래에서 확인하실 수 있습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
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

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}
