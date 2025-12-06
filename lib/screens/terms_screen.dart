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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.termsOfService ?? "",
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
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
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
        '이 약관은 Christopher Watson(이하 "회사")이 제공하는 Wefilling 모임 및 커뮤니티 서비스(이하 "서비스")의 이용과 관련하여 회사와 이용자 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.',
      ),
      
      _buildSection(
        '제2조 (정의)',
        '''1. "서비스"라 함은 회사가 제공하는 모임 생성, 참여, 게시물 작성 등의 커뮤니티 서비스를 의미합니다.
2. "이용자"라 함은 이 약관에 따라 회사가 제공하는 서비스를 받는 회원을 말합니다.
3. "회원"이라 함은 회사에 개인정보를 제공하여 회원등록을 한 자로서, 회사의 정보를 지속적으로 제공받으며 회사가 제공하는 서비스를 계속적으로 이용할 수 있는 자를 말합니다.
4. "비회원"이라 함은 회원에 가입하지 않고 회사가 제공하는 서비스를 이용하는 자를 말합니다.''',
      ),

      _buildSection(
        '제3조 (약관의 공시 및 효력과 변경)',
        '''1. 이 약관은 서비스 화면에 게시하거나 기타의 방법으로 이용자에게 공시함으로써 효력이 발생합니다.
2. 회사는 필요하다고 인정되는 경우 이 약관을 변경할 수 있으며, 변경된 약관은 제1항과 같은 방법으로 공시하고 공시 후 7일이 경과한 시점부터 효력이 발생합니다. 다만, 이용자에게 불리한 약관의 변경인 경우에는 공시 외에 일정기간 서비스 내 전자우편, 로그인 시 동의창 등의 전자적 수단을 통해 따로 명확히 통지하도록 합니다.
3. 이용자는 변경된 약관에 동의하지 않을 경우 회원탈퇴를 요청할 수 있으며, 변경된 약관의 효력 발생일로부터 7일 후에도 거부의사를 표시하지 아니하고 서비스를 계속 이용할 경우 약관의 변경에 동의한 것으로 간주됩니다.''',
      ),

      _buildSection(
        '제4조 (약관 외 준칙)',
        '이 약관에서 정하지 아니한 사항과 이 약관의 해석에 관하여는 전자상거래 등에서의 소비자보호에 관한 법률, 약관의 규제 등에 관한 법률, 정보통신망 이용촉진 및 정보보호 등에 관한 법률 등 관련 법령 또는 상관례에 따릅니다.',
      ),

      _buildSection(
        '제5조 (서비스의 제공)',
        '''회사는 다음과 같은 서비스를 제공합니다:
1. 모임 생성 및 참여 서비스
2. 게시물 작성 및 댓글 서비스
3. 사용자 간 소통 서비스
4. 기타 회사가 정하는 서비스''',
      ),

      _buildSection(
        '제6조 (서비스의 중단)',
        '''1. 회사는 컴퓨터 등 정보통신설비의 보수점검, 교체 및 고장, 통신의 두절 등의 사유가 발생한 경우에는 서비스의 제공을 일시적으로 중단할 수 있습니다.
2. 회사는 제1항의 사유로 서비스의 제공이 일시적으로 중단됨으로 인하여 이용자 또는 제3자가 입은 손해에 대하여 배상하지 아니합니다. 단, 회사의 고의 또는 중과실에 의한 경우에는 그러하지 아니합니다.
3. 사업종목의 전환, 사업의 포기, 업체 간의 통합 등의 이유로 서비스를 제공할 수 없게 되는 경우에는 회사는 제9조에 정한 방법으로 이용자에게 통지하고 당초 회사에서 제시한 조건에 따라 소비자에게 보상합니다.''',
      ),

      _buildSection(
        '제7조 (회원가입)',
        '''1. 이용자는 회사가 정한 가입 양식에 따라 회원정보를 기입한 후 이 약관에 동의한다는 의사표시를 함으로서 회원가입을 신청합니다.
2. 회사는 제1항과 같이 회원으로 가입할 것을 신청한 이용자 중 다음 각호에 해당하지 않는 한 회원으로 등록합니다.
   - 가입신청자가 이 약관에 의하여 이전에 회원자격을 상실한 적이 있는 경우. 다만, 회원자격 상실 후 3년이 경과한 자로서 회사의 회원재가입 승낙을 얻은 경우에는 예외로 합니다.
   - 등록 내용에 허위, 기재누락, 오기가 있는 경우
   - 기타 회원으로 등록하는 것이 회사의 기술상 현저히 지장이 있다고 판단되는 경우
3. 회원가입계약의 성립 시기는 회사의 승낙이 회원에게 도달한 시점으로 합니다.
4. 회원은 제1항의 회원정보 기재 내용에 변경이 발생한 경우, 즉시 변경사항을 정정하여 기재하여야 합니다.''',
      ),

      _buildSection(
        '제8조 (회원탈퇴 및 자격상실)',
        '''1. 회원은 언제든지 탈퇴를 요청할 수 있으며 회사는 즉시 회원탈퇴를 처리합니다.
2. 회원이 다음 각호의 사유에 해당하는 경우, 회사는 회원자격을 제한 및 정지시킬 수 있습니다.
   - 가입 신청 시에 허위 내용을 등록한 경우
   - 다른 사람의 서비스 이용을 방해하거나 그 정보를 도용하는 등 전자상거래 질서를 위협하는 경우
   - 서비스를 이용하여 법령 또는 이 약관이 금지하거나 공서양속에 반하는 행위를 하는 경우
3. 회사가 회원자격을 제한·정지시킨 후, 동일한 행위가 2회 이상 반복되거나 30일 이내에 그 사유가 시정되지 아니하는 경우 회사는 회원자격을 상실시킬 수 있습니다.
4. 회사가 회원자격을 상실시키는 경우에는 회원등록을 말소합니다. 이 경우 회원에게 이를 통지하고, 회원등록 말소 전에 최소한 30일 이상의 기간을 정하여 소명할 기회를 부여합니다.''',
      ),

      _buildSection(
        '제9조 (회원에 대한 통지)',
        '''1. 회사가 회원에 대한 통지를 하는 경우, 회원이 회사와 미리 약정하여 지정한 전자우편 주소로 할 수 있습니다.
2. 회사는 불특정다수 회원에 대한 통지의 경우 1주일 이상 서비스 게시판에 게시함으로서 개별 통지에 갈음할 수 있습니다. 다만, 회원 본인의 거래와 관련하여 중대한 영향을 미치는 사항에 대하여는 개별통지를 합니다.''',
      ),

      _buildSection(
        '제10조 (개인정보보호)',
        '''1. 회사는 이용자의 개인정보 수집시 서비스제공을 위하여 필요한 범위에서 최소한의 개인정보를 수집합니다.
2. 회사는 회원가입시 구매계약이행에 필요한 정보를 미리 수집하지 않습니다.
3. 회사는 이용자의 개인정보를 수집·이용하는 때에는 당해 이용자에게 그 목적을 고지하고 동의를 받습니다.
4. 회사는 수집된 개인정보를 목적외의 용도로 이용할 수 없으며, 새로운 이용목적이 발생한 경우 또는 제3자에게 제공하는 경우에는 이용·제공단계에서 당해 이용자에게 그 목적을 고지하고 동의를 받습니다.
5. 회사가 제2항과 제3항에 의해 이용자의 동의를 받아야 하는 경우에는 개인정보보호 책임자의 신원(소속, 성명 및 전화번호, 기타 연락처), 정보의 수집목적 및 이용목적, 제3자에 대한 정보제공 관련사항(제공받은자, 제공목적 및 제공할 정보의 내용) 등 정보통신망 이용촉진 및 정보보호 등에 관한 법률 제22조 제2항이 규정한 사항을 미리 명시하거나 고지해야 하며 이용자는 언제든지 이 동의를 철회할 수 있습니다.
6. 이용자는 언제든지 회사가 가지고 있는 자신의 개인정보에 대해 열람 및 오류정정을 요구할 수 있으며 회사는 이에 대해 지체 없이 필요한 조치를 취할 의무를 집니다.
7. 회사는 개인정보 보호를 위하여 이용자의 개인정보를 취급하는 자를 최소한으로 제한하여야 하며 신용카드, 은행계좌 등을 포함한 이용자의 개인정보의 분실, 도난, 유출, 동의 없는 제3자 제공, 변조 등으로 인한 이용자의 손해에 대하여 모든 책임을 집니다.
8. 회사 또는 그로부터 개인정보를 제공받은 제3자는 개인정보의 수집목적 또는 제공받은 목적을 달성한 때에는 당해 개인정보를 지체 없이 파기합니다.
9. 회사는 개인정보의 수집·이용·제공에 관한 동의란을 미리 선택한 것으로 설정해두지 않습니다. 또한 개인정보의 수집·이용·제공에 관한 이용자의 동의거절시 제한되는 서비스를 구체적으로 명시하고, 필수수집항목이 아닌 개인정보의 수집·이용·제공에 관한 이용자의 동의 거절을 이유로 회원가입 등 서비스 제공을 제한하거나 거절하지 않습니다.''',
      ),

      _buildSection(
        '제11조 (회사의 의무)',
        '''1. 회사는 법령과 이 약관이 금지하거나 공서양속에 반하는 행위를 하지 않으며 이 약관이 정하는 바에 따라 지속적이고, 안정적으로 서비스를 제공하는데 최선을 다하여야 합니다.
2. 회사는 이용자가 안전하게 인터넷 서비스를 이용할 수 있도록 이용자의 개인정보보호를 위한 보안 시스템을 구축하여야 합니다.
3. 회사가 상품이나 용역에 대하여 「표시·광고의 공정화에 관한 법률」 제3조 소정의 부당한 표시·광고행위를 함으로써 이용자가 손해를 입은 때에는 이를 배상할 책임을 집니다.
4. 회사는 이용자가 원하지 않는 영리목적의 광고성 전자우편을 발송하지 않습니다.
5. 회사는 이용자로부터 제기되는 의견이나 불만이 정당하다고 객관적으로 인정될 경우에는 적절한 절차를 거쳐 즉시 처리하여야 합니다.''',
      ),

      _buildSection(
        '제12조 (이용자의 의무)',
        '''1. 이용자는 다음 행위를 하여서는 안 됩니다.
   - 신청 또는 변경시 허위 내용의 등록
   - 타인의 정보 도용
   - 회사가 게시한 정보의 변경
   - 회사가 정한 정보 이외의 정보(컴퓨터 프로그램 등) 등의 송신 또는 게시
   - 회사 기타 제3자의 저작권 등 지적재산권에 대한 침해
   - 회사 기타 제3자의 명예를 손상시키거나 업무를 방해하는 행위
   - 외설 또는 폭력적인 메시지, 화상, 음성, 기타 공서양속에 반하는 정보를 서비스에 공개 또는 게시하는 행위
   - 회사의 동의 없이 영리를 목적으로 서비스를 사용하는 행위
   - 기타 불법적이거나 부당한 행위
2. 이용자는 관계법령, 이 약관의 규정, 이용안내 및 서비스와 관련하여 공지한 주의사항, 회사가 통지하는 사항 등을 준수하여야 하며, 기타 회사의 업무에 방해되는 행위를 하여서는 안 됩니다.''',
      ),

      _buildSection(
        '제13조 (저작권의 귀속 및 이용제한)',
        '''1. 회사가 작성한 저작물에 대한 저작권 기타 지적재산권은 회사에 귀속합니다.
2. 이용자는 서비스를 이용함으로써 얻은 정보 중 회사에게 지적재산권이 귀속된 정보를 회사의 사전 승낙 없이 복제, 송신, 출판, 배포, 방송 기타 방법에 의하여 영리목적으로 이용하거나 제3자에게 이용하게 하여서는 안 됩니다.
3. 회사는 약정에 따라 이용자에게 귀속된 저작권을 사용하는 경우 당해 이용자에게 통보하여야 합니다.''',
      ),

      _buildSection(
        '제14조 (분쟁해결)',
        '''1. 회사는 이용자가 제기하는 정당한 의견이나 불만을 반영하고 그 피해를 보상처리하기 위하여 피해보상처리기구를 설치·운영합니다.
2. 회사는 이용자로부터 제출되는 불만사항 및 의견은 우선적으로 그 사항을 처리합니다. 다만, 신속한 처리가 곤란한 경우에는 이용자에게 그 사유와 처리일정을 즉시 통보해 드립니다.
3. 회사와 이용자 간에 발생한 전자상거래 분쟁과 관련하여 이용자의 피해구제신청이 있는 경우에는 공정거래위원회 또는 시·도지사가 의뢰하는 분쟁조정기관의 조정에 따를 수 있습니다.''',
      ),

      _buildSection(
        '제15조 (면책조항)',
        '''1. 회사는 천재지변 또는 이에 준하는 불가항력으로 인하여 서비스를 제공할 수 없는 경우에는 서비스 제공에 관한 책임이 면제됩니다.
2. 회사는 이용자의 귀책사유로 인한 서비스 이용의 장애에 대하여는 책임을 지지 않습니다.
3. 회사는 이용자가 서비스를 이용하여 기대하는 수익을 상실한 것에 대하여 책임을 지지 않으며 그 밖의 서비스를 통하여 얻은 자료로 인한 손해에 관하여 책임을 지지 않습니다.
4. 회사는 이용자가 서비스에 게재한 정보, 자료, 사실의 신뢰도, 정확성 등의 내용에 관하여는 책임을 지지 않습니다.
5. 회사는 이용자 간 또는 이용자와 제3자 상호간에 서비스를 매개로 하여 거래 등을 한 경우에는 책임이 면제됩니다.''',
      ),

      _buildSection(
        '제16조 (재판권 및 준거법)',
        '''1. 회사와 이용자 간에 발생한 전자상거래 분쟁에 관한 소송은 제소 당시의 이용자의 주소에 의하고, 주소가 없는 경우에는 거소를 관할하는 지방법원의 전속관할로 합니다. 다만, 제소 당시 이용자의 주소 또는 거소가 분명하지 않거나 외국 거주자의 경우에는 민사소송법상의 관할법원에 제기합니다.
2. 회사와 이용자 간에 제기된 전자상거래 소송에는 대한민국 법을 적용합니다.''',
      ),

      const SizedBox(height: 16),
      
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '부칙',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '이 약관은 2025년 11월 25일부터 적용됩니다.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '문의: wefilling@gmail.com',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
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
        'These Terms of Service govern the use of the Wefilling meetup and community services (the "Service") provided by Christopher Watson (the "Company"), and define the rights, obligations, and responsibilities between the Company and users.',
      ),
      
      _buildSection(
        'Article 2 (Definitions)',
        '''1. "Service" refers to the community services provided by the Company, including meetup creation, participation, and posting.
2. "User" refers to members who receive the Service in accordance with these Terms.
3. "Member" refers to individuals who have registered by providing personal information to the Company and can continuously use the Service.
4. "Non-member" refers to individuals who use the Service without registering as members.''',
      ),

      _buildSection(
        'Article 3 (Publication and Amendment of Terms)',
        '''1. These Terms become effective upon publication on the Service screen or notification to users.
2. The Company may amend these Terms when necessary. Amended Terms shall be published in the same manner as paragraph 1 and become effective 7 days after publication. However, for amendments unfavorable to users, the Company shall provide separate clear notice through electronic means such as email or login consent windows for a certain period in addition to publication.
3. Users who do not agree to amended Terms may request account withdrawal. If users continue to use the Service 7 days after the effective date without expressing disagreement, they are deemed to have agreed to the amended Terms.''',
      ),

      _buildSection(
        'Article 4 (Supplementary Provisions)',
        'Matters not specified in these Terms and interpretation of these Terms shall be governed by the Act on Consumer Protection in Electronic Commerce, the Act on Regulation of Terms and Conditions, the Act on Promotion of Information and Communications Network Utilization and Information Protection, and other relevant laws and commercial practices.''',
      ),

      _buildSection(
        'Article 5 (Provision of Services)',
        '''The Company provides the following services:
1. Meetup creation and participation services
2. Post writing and commenting services
3. User communication services
4. Other services determined by the Company''',
      ),

      _buildSection(
        'Article 6 (Service Interruption)',
        '''1. The Company may temporarily suspend the Service due to maintenance, replacement, failure of information and communication facilities, or communication disruptions.
2. The Company shall not be liable for damages incurred by users or third parties due to temporary service suspension as described in paragraph 1, except in cases of willful misconduct or gross negligence by the Company.
3. If the Service cannot be provided due to business conversion, business abandonment, or corporate merger, the Company shall notify users in accordance with Article 9 and compensate consumers according to the conditions initially presented by the Company.''',
      ),

      _buildSection(
        'Article 7 (Membership Registration)',
        '''1. Users apply for membership by filling out the registration form designated by the Company and expressing their agreement to these Terms.
2. The Company shall register applicants as members unless they fall under any of the following:
   - The applicant has previously lost membership status under these Terms. However, exceptions may be made for those who have obtained the Company's consent for re-registration after 3 years have passed since membership loss.
   - Registration contains false information, omissions, or errors
   - Registration would significantly impair the Company's technical operations
3. The membership contract becomes effective when the Company's acceptance reaches the member.
4. Members must immediately update any changes to the member information provided in paragraph 1.''',
      ),

      _buildSection(
        'Article 8 (Withdrawal and Loss of Membership)',
        '''1. Members may request withdrawal at any time, and the Company shall process it immediately.
2. The Company may restrict or suspend membership if members fall under any of the following:
   - Registered false information during sign-up
   - Interfered with others' use of the Service or stolen their information, threatening electronic commerce order
   - Used the Service for acts prohibited by law or these Terms or acts contrary to public order and morals
3. If the same act is repeated twice or more after the Company restricts or suspends membership, or if the cause is not corrected within 30 days, the Company may terminate membership.
4. When the Company terminates membership, it shall delete the member registration. In this case, the Company shall notify the member and provide at least 30 days for explanation before deleting the member registration.''',
      ),

      _buildSection(
        'Article 9 (Notice to Members)',
        '''1. When the Company notifies members, it may use the email address pre-designated by the member in agreement with the Company.
2. For notices to an unspecified number of members, the Company may substitute individual notice by posting on the service bulletin board for at least one week. However, individual notice shall be provided for matters that significantly affect the member's own transactions.''',
      ),

      _buildSection(
        'Article 10 (Privacy Protection)',
        '''1. The Company collects minimum personal information necessary to provide the Service.
2. The Company does not collect information required for contract fulfillment in advance during registration.
3. The Company notifies users of the purpose and obtains consent when collecting and using personal information.
4. The Company cannot use collected personal information for purposes other than intended, and must notify users and obtain consent when new purposes arise or when providing to third parties.
5. When the Company must obtain user consent under paragraphs 2 and 3, it must specify or notify in advance the identity of the privacy officer (affiliation, name, phone number, and other contact information), purpose of information collection and use, matters related to providing information to third parties (recipient, purpose of provision, and content of information to be provided) as required by Article 22, Paragraph 2 of the Act on Promotion of Information and Communications Network Utilization and Information Protection. Users may withdraw this consent at any time.
6. Users may request access to and correction of errors in their personal information held by the Company at any time, and the Company shall take necessary measures without delay.
7. The Company shall minimize the number of persons handling users' personal information to protect privacy, and shall be fully liable for damages to users caused by loss, theft, leakage, unauthorized provision to third parties, or alteration of users' personal information, including credit cards and bank accounts.
8. The Company or third parties who receive personal information from the Company shall destroy the personal information without delay when the purpose of collection or provision is achieved.
9. The Company does not pre-select consent boxes for collection, use, and provision of personal information. Additionally, the Company specifies services that will be restricted if users refuse consent for collection, use, and provision of personal information, and does not restrict or refuse service provision such as membership registration based on users' refusal to consent to collection, use, and provision of non-essential personal information.''',
      ),

      _buildSection(
        'Article 11 (Company\'s Obligations)',
        '''1. The Company shall not engage in acts prohibited by law or these Terms or contrary to public order and morals, and shall do its best to provide continuous and stable services in accordance with these Terms.
2. The Company shall establish a security system to protect users' personal information so that users can safely use internet services.
3. The Company shall be liable for damages incurred by users due to unfair labeling or advertising acts as prescribed in Article 3 of the Act on Fair Labeling and Advertising regarding products or services.
4. The Company shall not send commercial advertising emails for profit purposes that users do not want.
5. The Company shall promptly handle opinions or complaints raised by users through appropriate procedures when objectively deemed legitimate.''',
      ),

      _buildSection(
        'Article 12 (User\'s Obligations)',
        '''1. Users shall not engage in the following acts:
   - Registering false information during application or modification
   - Stealing others' information
   - Altering information posted by the Company
   - Transmitting or posting information other than designated by the Company (such as computer programs)
   - Infringing on intellectual property rights such as copyrights of the Company or third parties
   - Damaging reputation or interfering with business of the Company or third parties
   - Publishing or posting obscene or violent messages, images, sounds, or other information contrary to public order and morals
   - Using the Service for commercial purposes without the Company's consent
   - Other illegal or improper acts
2. Users shall comply with relevant laws, provisions of these Terms, user guides and notices related to the Service, and matters notified by the Company, and shall not engage in acts that interfere with the Company's business.''',
      ),

      _buildSection(
        'Article 13 (Copyright Ownership and Usage Restrictions)',
        '''1. Copyrights and other intellectual property rights for works created by the Company belong to the Company.
2. Users shall not use information obtained through the Service for which intellectual property rights belong to the Company for commercial purposes by reproduction, transmission, publication, distribution, broadcasting, or other methods, or allow third parties to use it, without the Company's prior consent.
3. The Company shall notify the relevant user when using copyrights belonging to users according to agreements.''',
      ),

      _buildSection(
        'Article 14 (Dispute Resolution)',
        '''1. The Company establishes and operates a damage compensation processing organization to reflect legitimate opinions or complaints raised by users and compensate for damages.
2. The Company prioritizes processing complaints and opinions submitted by users. However, if prompt processing is difficult, the Company shall immediately notify users of the reason and processing schedule.
3. Regarding electronic commerce disputes between the Company and users, if users request damage relief, the Company may follow mediation by dispute resolution organizations commissioned by the Fair Trade Commission or city/provincial governors.''',
      ),

      _buildSection(
        'Article 15 (Disclaimer)',
        '''1. The Company is exempt from liability for service provision if unable to provide services due to natural disasters or equivalent force majeure.
2. The Company is not liable for service usage disruptions caused by users' fault.
3. The Company is not liable for loss of expected profits from service use or damages from materials obtained through the Service.
4. The Company is not liable for the reliability, accuracy, or other content of information, data, or facts posted by users on the Service.
5. The Company is exempt from liability for transactions between users or between users and third parties mediated through the Service.''',
      ),

      _buildSection(
        'Article 16 (Jurisdiction and Governing Law)',
        '''1. Lawsuits regarding electronic commerce disputes between the Company and users shall have exclusive jurisdiction of the district court having jurisdiction over the user's address at the time of filing, or residence if there is no address. However, if the user's address or residence is unclear at the time of filing, or if the user is a foreign resident, the lawsuit shall be filed with the competent court under the Civil Procedure Act.
2. Korean law shall apply to electronic commerce lawsuits filed between the Company and users.''',
      ),

      const SizedBox(height: 16),
      
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Supplementary Provisions',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'These Terms become effective from November 25, 2025.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Contact: wefilling@gmail.com',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              height: 1.7,
              color: Color(0xFF374151),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
