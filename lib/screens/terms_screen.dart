// lib/screens/terms_screen.dart
// 서비스 이용약관 페이지

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.termsOfService ?? ""),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: isKo ? _buildKoreanTerms() : _buildEnglishTerms(),
        ),
      ),
    );
  }

  List<Widget> _buildKoreanTerms() {
    return [
      _buildSection(
        '제1조 (목적)',
        '이 약관은 위플링(이하 "회사")이 제공하는 모임 및 커뮤니티 서비스(이하 "서비스")의 이용과 관련하여 회사와 이용자 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.',
      ),
      
      _buildSection(
        '제2조 (정의)',
        '''1. "서비스"라 함은 회사가 제공하는 모임 생성, 참여, 게시물 작성 등의 커뮤니티 서비스를 의미합니다.
2. "이용자"라 함은 이 약관에 따라 회사가 제공하는 서비스를 받는 회원을 말합니다.
3. "회원"이라 함은 회사에 개인정보를 제공하여 회원등록을 한 자로서, 회사의 정보를 지속적으로 제공받으며 회사가 제공하는 서비스를 계속적으로 이용할 수 있는 자를 말합니다.''',
      ),

      _buildSection(
        '제3조 (약관의 공시 및 효력과 변경)',
        '''1. 이 약관은 서비스 화면에 게시하거나 기타의 방법으로 이용자에게 공시함으로써 효력이 발생합니다.
2. 회사는 필요하다고 인정되는 경우 이 약관을 변경할 수 있으며, 변경된 약관은 제1항과 같은 방법으로 공시함으로써 효력이 발생합니다.
3. 이용자는 변경된 약관에 동의하지 않을 경우 회원탈퇴를 요청할 수 있으며, 변경된 약관의 효력 발생일로부터 7일 후에도 거부의사를 표시하지 아니하고 서비스를 계속 이용할 경우 약관의 변경에 동의한 것으로 간주됩니다.''',
      ),

      _buildSection(
        '제4조 (서비스의 제공)',
        '''회사는 다음과 같은 서비스를 제공합니다:
1. 모임 생성 및 참여 서비스
2. 게시물 작성 및 댓글 서비스
3. 사용자 간 소통 서비스
4. 기타 회사가 정하는 서비스''',
      ),

      _buildSection(
        '제5조 (서비스의 중단)',
        '''1. 회사는 컴퓨터 등 정보통신설비의 보수점검, 교체 및 고장, 통신의 두절 등의 사유가 발생한 경우에는 서비스의 제공을 일시적으로 중단할 수 있습니다.
2. 회사는 제1항의 사유로 서비스의 제공이 일시적으로 중단됨으로 인하여 이용자 또는 제3자가 입은 손해에 대하여는 배상하지 아니합니다.''',
      ),

      _buildSection(
        '제6조 (회원가입)',
        '''1. 이용자는 회사가 정한 가입 양식에 따라 회원정보를 기입한 후 이 약관에 동의한다는 의사표시를 함으로서 회원가입을 신청합니다.
2. 회사는 제1항과 같이 회원으로 가입할 것을 신청한 이용자 중 다음 각호에 해당하지 않는 한 회원으로 등록합니다.
   - 가입신청자가 이 약관에 의하여 이전에 회원자격을 상실한 적이 있는 경우
   - 등록 내용에 허위, 기재누락, 오기가 있는 경우
   - 기타 회원으로 등록하는 것이 회사의 기술상 현저히 지장이 있다고 판단되는 경우''',
      ),

      _buildSection(
        '제7조 (회원탈퇴 및 자격상실)',
        '''1. 회원은 언제든지 탈퇴를 요청할 수 있으며 회사는 즉시 회원탈퇴를 처리합니다.
2. 회원이 다음 각호의 사유에 해당하는 경우, 회사는 회원자격을 제한 및 정지시킬 수 있습니다.
   - 가입 신청 시에 허위 내용을 등록한 경우
   - 다른 사람의 서비스 이용을 방해하거나 그 정보를 도용하는 등 전자상거래 질서를 위협하는 경우
   - 서비스를 이용하여 법령 또는 이 약관이 금지하거나 공서양속에 반하는 행위를 하는 경우''',
      ),

      _buildSection(
        '제8조 (개인정보보호)',
        '''1. 회사는 이용자의 개인정보 수집시 서비스제공을 위하여 필요한 범위에서 최소한의 개인정보를 수집합니다.
2. 회사는 회원가입시 구매계약이행에 필요한 정보를 미리 수집하지 않습니다.
3. 회사는 이용자의 개인정보를 수집·이용하는 때에는 당해 이용자에게 그 목적을 고지하고 동의를 받습니다.
4. 회사는 수집된 개인정보를 목적외의 용도로 이용할 수 없으며, 새로운 이용목적이 발생한 경우 또는 제3자에게 제공하는 경우에는 이용·제공단계에서 당해 이용자에게 그 목적을 고지하고 동의를 받습니다.''',
      ),

      _buildSection(
        '제9조 (회사의 의무)',
        '''1. 회사는 법령과 이 약관이 금지하거나 공서양속에 반하는 행위를 하지 않으며 이 약관이 정하는 바에 따라 지속적이고, 안정적으로 서비스를 제공하는데 최선을 다하여야 합니다.
2. 회사는 이용자가 안전하게 인터넷 서비스를 이용할 수 있도록 이용자의 개인정보보호를 위한 보안 시스템을 구축하여야 합니다.
3. 회사는 이용자로부터 제기되는 의견이나 불만이 정당하다고 객관적으로 인정될 경우에는 적절한 절차를 거쳐 즉시 처리하여야 합니다.''',
      ),

      _buildSection(
        '제10조 (이용자의 의무)',
        '''1. 이용자는 다음 행위를 하여서는 안 됩니다.
   - 신청 또는 변경시 허위 내용의 등록
   - 타인의 정보 도용
   - 회사가 게시한 정보의 변경
   - 회사가 정한 정보 이외의 정보(컴퓨터 프로그램 등) 등의 송신 또는 게시
   - 회사 기타 제3자의 저작권 등 지적재산권에 대한 침해
   - 회사 기타 제3자의 명예를 손상시키거나 업무를 방해하는 행위
   - 외설 또는 폭력적인 메시지, 화상, 음성, 기타 공서양속에 반하는 정보를 서비스에 공개 또는 게시하는 행위''',
      ),

      _buildSection(
        '제11조 (면책조항)',
        '''1. 회사는 천재지변 또는 이에 준하는 불가항력으로 인하여 서비스를 제공할 수 없는 경우에는 서비스 제공에 관한 책임이 면제됩니다.
2. 회사는 이용자의 귀책사유로 인한 서비스 이용의 장애에 대하여는 책임을 지지 않습니다.
3. 회사는 이용자가 서비스를 이용하여 기대하는 수익을 상실한 것에 대하여 책임을 지지 않으며 그 밖의 서비스를 통하여 얻은 자료로 인한 손해에 관하여 책임을 지지 않습니다.''',
      ),

      _buildSection(
        '제12조 (재판권 및 준거법)',
        '''이 약관으로 인하여 발생한 분쟁에 대해 소송이 제기되는 경우 민사소송법상의 관할법원에 제기합니다. 본 약관은 대한민국 법을 준거법으로 합니다.''',
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
              '이 약관은 2025년 9월 25일부터 적용됩니다.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildEnglishTerms() {
    return [
      _buildSection(
        'Article 1 (Purpose)',
        'These Terms of Service govern the use of the meetup and community services (the "Service") provided by Wefilling (the "Company"), and define the rights, obligations, and responsibilities between the Company and users.',
      ),
      
      _buildSection(
        'Article 2 (Definitions)',
        '''1. "Service" refers to the community services provided by the Company, including meetup creation, participation, and posting.
2. "User" refers to members who receive the Service in accordance with these Terms.
3. "Member" refers to individuals who have registered by providing personal information to the Company and can continuously use the Service.''',
      ),

      _buildSection(
        'Article 3 (Publication and Amendment of Terms)',
        '''1. These Terms become effective upon publication on the Service screen or notification to users.
2. The Company may amend these Terms when necessary, and amended Terms become effective upon publication in the same manner as paragraph 1.
3. Users who do not agree to amended Terms may request account withdrawal. If users continue to use the Service 7 days after the effective date without expressing disagreement, they are deemed to have agreed to the amended Terms.''',
      ),

      _buildSection(
        'Article 4 (Provision of Services)',
        '''The Company provides the following services:
1. Meetup creation and participation services
2. Post writing and commenting services
3. User communication services
4. Other services determined by the Company''',
      ),

      _buildSection(
        'Article 5 (Service Interruption)',
        '''1. The Company may temporarily suspend the Service due to maintenance, replacement, failure of information and communication facilities, or communication disruptions.
2. The Company shall not be liable for damages incurred by users or third parties due to temporary service suspension as described in paragraph 1.''',
      ),

      _buildSection(
        'Article 6 (Membership Registration)',
        '''1. Users apply for membership by filling out the registration form designated by the Company and expressing their agreement to these Terms.
2. The Company shall register applicants as members unless they fall under any of the following:
   - The applicant has previously lost membership status under these Terms
   - Registration contains false information, omissions, or errors
   - Registration would significantly impair the Company's technical operations''',
      ),

      _buildSection(
        'Article 7 (Withdrawal and Loss of Membership)',
        '''1. Members may request withdrawal at any time, and the Company shall process it immediately.
2. The Company may restrict or suspend membership if members fall under any of the following:
   - Registered false information during sign-up
   - Interfered with others' use of the Service or stolen their information
   - Used the Service for prohibited acts or acts contrary to public order and morals''',
      ),

      _buildSection(
        'Article 8 (Privacy Protection)',
        '''1. The Company collects minimum personal information necessary to provide the Service.
2. The Company does not collect information required for contract fulfillment in advance during registration.
3. The Company notifies users of the purpose and obtains consent when collecting and using personal information.
4. The Company cannot use collected personal information for purposes other than intended, and must notify users and obtain consent when new purposes arise or when providing to third parties.''',
      ),

      _buildSection(
        'Article 9 (Company\'s Obligations)',
        '''1. The Company shall not engage in acts prohibited by law or these Terms or contrary to public order and morals, and shall do its best to provide continuous and stable services.
2. The Company shall establish a security system to protect users' personal information.
3. The Company shall promptly handle opinions or complaints raised by users through appropriate procedures when objectively deemed legitimate.''',
      ),

      _buildSection(
        'Article 10 (User\'s Obligations)',
        '''1. Users shall not engage in the following acts:
   - Registering false information
   - Stealing others' information
   - Altering information posted by the Company
   - Transmitting or posting information other than designated by the Company
   - Infringing on intellectual property rights of the Company or third parties
   - Damaging reputation or interfering with business of the Company or third parties
   - Publishing or posting obscene or violent messages, images, sounds, or information contrary to public order and morals''',
      ),

      _buildSection(
        'Article 11 (Disclaimer)',
        '''1. The Company is exempt from liability for service provision if unable to provide services due to natural disasters or equivalent force majeure.
2. The Company is not liable for service usage disruptions caused by users' fault.
3. The Company is not liable for loss of expected profits from service use or damages from materials obtained through the Service.''',
      ),

      _buildSection(
        'Article 12 (Jurisdiction and Governing Law)',
        '''Disputes arising from these Terms shall be filed with the competent court under the Civil Procedure Act. These Terms are governed by the laws of the Republic of Korea.''',
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
              'Supplementary Provisions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'These Terms become effective from September 25, 2025.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    ];
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
