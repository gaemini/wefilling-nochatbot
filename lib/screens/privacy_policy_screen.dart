// lib/screens/privacy_policy_screen.dart
// 개인정보 처리방침 페이지

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.privacyPolicy ?? ""),
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
                      Text(
                        isKo ? '개인정보 처리방침 안내' : 'Privacy Policy Guide',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isKo
                        ? 'Wefilling 서비스를 운영하는 Christopher Watson은 개인정보보호법에 따라 이용자의 개인정보 보호 및 권익을 보호하고 개인정보와 관련한 이용자의 고충을 원활하게 처리할 수 있도록 다음과 같은 처리방침을 두고 있습니다.'
                        : 'Christopher Watson, who operates the Wefilling service, processes personal information in accordance with the Personal Information Protection Act and takes necessary measures to protect users\' rights and handle related inquiries effectively.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            _buildSection(
              isKo ? '제1조 개인정보의 처리목적' : 'Article 1 Purpose of Processing',
              isKo
                  ? '''Wefilling은 다음의 목적을 위하여 개인정보를 처리합니다. 처리하고 있는 개인정보는 다음의 목적 이외의 용도로는 이용되지 않으며, 이용 목적이 변경되는 경우에는 개인정보보호법 제18조에 따라 별도의 동의를 받는 등 필요한 조치를 이행할 예정입니다.

1. 회원가입 및 관리
   - 회원 가입의사 확인, 회원제 서비스 제공에 따른 본인 식별·인증, 회원자격 유지·관리, 서비스 부정이용 방지 목적으로 개인정보를 처리합니다.

2. 서비스 제공
   - 모임 생성 및 참여, 게시물 작성, 댓글 작성, 사용자 간 소통 서비스 제공을 목적으로 개인정보를 처리합니다.

3. 고충처리
   - 민원인의 신원 확인, 민원사항 확인, 사실조사를 위한 연락·통지, 처리결과 통보의 목적으로 개인정보를 처리합니다.'''
                  : '''Wefilling processes personal data for the following purposes. Personal data being processed will not be used for purposes other than those listed below. If the purpose of use changes, necessary measures will be taken, such as obtaining separate consent in accordance with Article 18 of the Personal Information Protection Act.

1. Membership Registration and Management
   - Personal data is processed to confirm membership registration intent, identify and authenticate users for membership services, maintain and manage membership qualifications, and prevent unauthorized use of services.

2. Service Provision
   - Personal data is processed to provide services including meetup creation and participation, post writing, commenting, and user communication.

3. Complaint Handling
   - Personal data is processed to verify complainant identity, confirm complaint details, contact and notify for fact-finding, and report processing results.''',
            ),

            _buildSection(
              isKo ? '제2조 개인정보의 처리 및 보유기간' : 'Article 2 Retention Period',
              isKo
                  ? '''1. Wefilling은 법령에 따른 개인정보 보유·이용기간 또는 정보주체로부터 개인정보를 수집 시에 동의받은 개인정보 보유·이용기간 내에서 개인정보를 처리·보유합니다.

2. 각각의 개인정보 처리 및 보유 기간은 다음과 같습니다.
   - 회원가입 및 관리 : 회원탈퇴 시까지
   - 서비스 제공 : 서비스 이용계약 종료 시까지
   - 고충처리 : 고충 처리 완료 후 3년'''
                  : '''1. Wefilling processes and retains personal data within the retention and use period prescribed by law or the retention and use period agreed upon when collecting personal data from data subjects.

2. The processing and retention period for each type of personal data is as follows:
   - Membership registration and management: Until membership withdrawal
   - Service provision: Until termination of service use contract
   - Complaint handling: 3 years after complaint resolution''',
            ),

            _buildSection(
              isKo ? '제3조 개인정보의 제3자 제공' : 'Article 3 Third-Party Provision',
              isKo
                  ? '''Wefilling은 정보주체의 개인정보를 제1조(개인정보의 처리목적)에서 명시한 범위 내에서만 처리하며, 정보주체의 동의, 법률의 특별한 규정 등 개인정보보호법 제17조에 해당하는 경우에만 개인정보를 제3자에게 제공합니다.

현재 Wefilling은 개인정보를 제3자에게 제공하지 않습니다.'''
                  : '''Wefilling processes personal data of data subjects only within the scope specified in Article 1 (Purpose of Processing Personal Data) and provides personal data to third parties only in cases corresponding to Article 17 of the Personal Information Protection Act, such as with data subject consent or special legal provisions.

Currently, Wefilling does not provide personal data to third parties.''',
            ),

            _buildSection(
              isKo ? '제4조 개인정보처리의 위탁' : 'Article 4 Outsourcing',
              isKo
                  ? '''1. Wefilling은 원활한 개인정보 업무처리를 위하여 다음과 같이 개인정보 처리업무를 위탁하고 있습니다.

▶ 위탁받는 자
   - 업체명: Firebase (Google LLC)
   - 위탁업무 내용: 회원관리, 서비스 제공을 위한 시스템 운영
   - 위탁기간: 서비스 제공기간

2. Wefilling은 위탁계약 체결시 개인정보보호법 제26조에 따라 위탁업무 수행목적 외 개인정보 처리금지, 기술적·관리적 보호조치, 재위탁 제한, 수탁자에 대한 관리·감독, 손해배상 등 책임에 관한 사항을 계약서 등 문서에 명시하고, 수탁자가 개인정보를 안전하게 처리하는지를 감독하고 있습니다.'''
                  : '''1. Wefilling outsources personal data processing tasks as follows for smooth personal data processing.

▶ Outsourcing Partner
   - Company: Firebase (Google LLC)
   - Outsourced tasks: Member management, system operation for service provision
   - Outsourcing period: Service provision period

2. When concluding outsourcing contracts, Wefilling specifies in contracts and other documents matters concerning prohibition of personal data processing beyond outsourced task performance purposes, technical and administrative protection measures, restrictions on re-outsourcing, management and supervision of contractors, and liability for damages in accordance with Article 26 of the Personal Information Protection Act, and supervises whether contractors safely process personal data.''',
            ),

            _buildSection(
              isKo ? '제5조 정보주체의 권리·의무 및 행사방법' : 'Article 5 Data Subject Rights and Exercise Methods',
              isKo
                  ? '''1. 정보주체는 Wefilling에 대해 언제든지 다음 각 호의 개인정보 보호 관련 권리를 행사할 수 있습니다.
   - 개인정보 열람요구
   - 개인정보 정정·삭제요구
   - 개인정보 처리정지 요구

2. 제1항에 따른 권리 행사는 Wefilling에 대해 개인정보보호법 시행규칙 별지 제8호 서식에 따라 서면, 전자우편, 모사전송(FAX) 등을 통하여 하실 수 있으며 Wefilling은 이에 대해 지체없이 조치하겠습니다.

3. 정보주체가 개인정보의 오류 등에 대한 정정 또는 삭제를 요구한 경우에는 Wefilling은 정정 또는 삭제를 완료할 때까지 당해 개인정보를 이용하거나 제공하지 않습니다.

4. 제1항에 따른 권리 행사는 정보주체의 법정대리인이나 위임을 받은 자 등 대리인을 통하여 하실 수 있습니다. 이 경우 개인정보보호법 시행규칙 별지 제11호 서식에 따른 위임장을 제출하셔야 합니다.'''
                  : '''1. Data subjects may exercise the following personal information protection-related rights against Wefilling at any time:
   - Request for access to personal data
   - Request for correction or deletion of personal data
   - Request for suspension of personal data processing

2. Rights under paragraph 1 may be exercised against Wefilling in writing, by email, facsimile (FAX), etc. according to Form No. 8 attached to the Enforcement Rules of the Personal Information Protection Act, and Wefilling will take action without delay.

3. If a data subject requests correction or deletion of errors in personal data, Wefilling will not use or provide the personal data until the correction or deletion is completed.

4. Rights under paragraph 1 may be exercised through agents such as legal representatives or authorized persons of data subjects. In this case, a power of attorney according to Form No. 11 attached to the Enforcement Rules of the Personal Information Protection Act must be submitted.''',
            ),

            _buildSection(
              isKo ? '제6조 처리하는 개인정보 항목' : 'Article 6 Personal Data Items Processed',
              isKo
                  ? '''Wefilling은 다음의 개인정보 항목을 처리하고 있습니다.

1. 필수항목
   - 이메일 주소, 닉네임, 프로필 사진(선택)

2. 자동 수집 항목
   - 서비스 이용 기록, 접속 로그, 쿠키, 접속 IP 정보, 기기정보'''
                  : '''Wefilling processes the following personal data items:

1. Required Items
   - Email address, nickname, profile photo (optional)

2. Automatically Collected Items
   - Service usage records, access logs, cookies, access IP information, device information''',
            ),

            _buildSection(
              isKo ? '제7조 개인정보의 파기' : 'Article 7 Destruction of Personal Data',
              isKo
                  ? '''1. Wefilling은 개인정보 보유기간의 경과, 처리목적 달성 등 개인정보가 불필요하게 되었을 때에는 지체없이 해당 개인정보를 파기합니다.

2. 개인정보 파기의 절차 및 방법은 다음과 같습니다.

▶ 파기절차
   - 불필요한 개인정보 및 개인정보파일은 개인정보보호책임자의 승인을 받아 파기합니다.

▶ 파기방법
   - 전자적 파일: 기록을 재생할 수 없는 기술적 방법을 사용하여 삭제
   - 종이 문서: 분쇄기로 분쇄하거나 소각하여 파기'''
                  : '''1. Wefilling destroys personal data without delay when it becomes unnecessary, such as when the retention period expires or the processing purpose is achieved.

2. The procedure and method for destroying personal data are as follows:

▶ Destruction Procedure
   - Unnecessary personal data and personal data files are destroyed with approval from the privacy officer.

▶ Destruction Method
   - Electronic files: Deleted using technical methods that make records irreproducible
   - Paper documents: Destroyed by shredding or incineration''',
            ),

            _buildSection(
              isKo ? '제8조 개인정보의 안전성 확보조치' : 'Article 8 Security Measures',
              isKo
                  ? '''Wefilling은 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.

1. 관리적 조치: 내부관리계획 수립·시행, 정기적 직원 교육 등
2. 기술적 조치: 개인정보처리시스템 등의 접근권한 관리, 접근통제시스템 설치, 고유식별정보 등의 암호화, 보안프로그램 설치
3. 물리적 조치: 전산실, 자료보관실 등의 접근통제'''
                  : '''Wefilling takes the following measures to ensure the security of personal data:

1. Administrative Measures: Establishment and implementation of internal management plans, regular employee training, etc.
2. Technical Measures: Access authority management for personal data processing systems, installation of access control systems, encryption of unique identification information, installation of security programs
3. Physical Measures: Access control for computer rooms, data storage rooms, etc.''',
            ),

            _buildSection(
              isKo ? '제9조 개인정보 보호책임자' : 'Article 9 Privacy Officer',
              isKo
                  ? '''Wefilling은 개인정보 처리에 관한 업무를 총괄해서 책임지고, 개인정보 처리와 관련한 정보주체의 불만처리 및 피해구제 등을 위하여 아래와 같이 개인정보 보호책임자를 지정하고 있습니다.

▶ 개인정보 보호책임자
   - 성명: Christopher Watson
   - 연락처: wefilling@gmail.com

▶ 개인정보 보호 담당부서
   - 담당자: Christopher Watson
   - 연락처: wefilling@gmail.com

정보주체는 Wefilling 서비스를 이용하시면서 발생한 모든 개인정보 보호 관련 문의, 불만처리, 피해구제 등에 관한 사항을 개인정보 보호책임자 및 담당부서로 문의하실 수 있습니다. Christopher Watson은 정보주체의 문의에 대해 지체 없이 답변 및 처리해드릴 것입니다.'''
                  : '''Wefilling designates a privacy officer as follows to oversee personal data processing operations and handle complaints and damage relief related to personal data processing for data subjects.

▶ Privacy Officer
   - Name: Christopher Watson
   - Contact: wefilling@gmail.com

▶ Privacy Department
   - Contact Person: Christopher Watson
   - Contact: wefilling@gmail.com

Data subjects may contact the privacy officer and department regarding all personal information protection-related inquiries, complaint handling, damage relief, etc. that arise while using Wefilling services. Christopher Watson will respond to and process data subject inquiries without delay.''',
            ),

            _buildSection(
              isKo ? '제10조 권익침해 구제방법' : 'Article 10 Remedies for Rights Violations',
              isKo
                  ? '''정보주체는 아래의 기관에 대해 개인정보 침해신고, 상담등을 문의하실 수 있습니다.

▶ 개인정보 침해신고센터 (privacy.go.kr)
   - 신고전화: 국번없이 118
   - 주소: (01300) 서울특별시 중구 세종대로 209 정부서울청사 4층

▶ 개인정보 분쟁조정위원회 (www.kopico.go.kr)
   - 신고전화: 국번없이 1833-6972
   - 주소: (03171) 서울특별시 종로구 세종대로 209 정부서울청사 4층

▶ 대검찰청 사이버범죄수사단 (www.spo.go.kr)
   - 신고전화: 국번없이 1301

▶ 경찰청 사이버범죄 신고시스템 (police.go.kr)
   - 신고전화: 국번없이 182

▶ 중앙행정심판위원회 (www.simpan.go.kr)
   - 전화: 110'''
                  : '''Data subjects may contact the following organizations for personal information infringement reports and consultations:

▶ Privacy Reporting Center (privacy.go.kr)
   - Report Phone: 118 (toll-free)
   - Address: 4th Floor, Government Complex Seoul, 209 Sejong-daero, Jung-gu, Seoul (01300)

▶ Personal Information Dispute Mediation Committee (www.kopico.go.kr)
   - Report Phone: 1833-6972 (toll-free)
   - Address: 4th Floor, Government Complex Seoul, 209 Sejong-daero, Jongno-gu, Seoul (03171)

▶ Supreme Prosecutors' Office Cyber Crime Division (www.spo.go.kr)
   - Report Phone: 1301 (toll-free)

▶ National Police Agency Cyber Crime Reporting System (police.go.kr)
   - Report Phone: 182 (toll-free)

▶ Central Administrative Appeals Commission (www.simpan.go.kr)
   - Phone: 110''',
            ),

            const SizedBox(height: 32),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isKo ? '부칙' : 'Addendum',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isKo
                        ? '이 개인정보 처리방침은 2025년 11월 25일부터 적용됩니다.\n이전의 개인정보 처리방침은 아래에서 확인하실 수 있습니다.'
                        : 'This Privacy Policy takes effect on November 25, 2025.\nPrevious versions can be found below.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isKo ? '문의: wefilling@gmail.com' : 'Contact: wefilling@gmail.com',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
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
