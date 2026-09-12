// lib/screens/privacy_policy_screen.dart
// 개인정보 처리방침 페이지

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../l10n/ui_locale.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

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
          AppLocalizations.of(context)!.privacyPolicy ?? "",
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
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
          children: [
            const SizedBox(height: 0),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第1条 处理目的'
                  : isKo
                      ? '제1조 개인정보의 처리목적'
                      : 'Article 1 Purpose of Processing'),
              (isChineseUi(context)
                  ? 'Wefilling出于以下目的处理个人信息。所处理的个人信息不会用于下述目的以外的用途。如使用目的发生变化，将依据《个人信息保护法》第18条采取另行征得同意等必要措施。\n\n1. 会员注册与管理\n   - 确认注册意愿、识别和认证会员身份、维护和管理会员资格，以及防止违规使用服务。\n\n2. 提供服务\n   - 提供创建和参加聚会、发布动态、发表评论及用户交流等服务。\n\n3. 投诉处理\n   - 核实投诉人身份、确认投诉内容、为查明事实进行联系和通知，以及告知处理结果。'
                  : isKo
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
   - Personal data is processed to verify complainant identity, confirm complaint details, contact and notify for fact-finding, and report processing results.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第2条 保存期限'
                  : isKo
                      ? '제2조 개인정보의 처리 및 보유기간'
                      : 'Article 2 Retention Period'),
              (isChineseUi(context)
                  ? '1. Wefilling在法律规定的期限内，或收集个人信息时与个人信息主体约定的保存及使用期限内处理和保存个人信息。\n\n2. 各类个人信息的处理和保存期限如下：\n   - 会员注册与管理：至会员注销时\n   - 提供服务：至服务使用合同终止时\n   - 投诉处理：投诉解决后3年'
                  : isKo
                      ? '''1. Wefilling은 법령에 따른 개인정보 보유·이용기간 또는 정보주체로부터 개인정보를 수집 시에 동의받은 개인정보 보유·이용기간 내에서 개인정보를 처리·보유합니다.

2. 각각의 개인정보 처리 및 보유 기간은 다음과 같습니다.
   - 회원가입 및 관리 : 회원탈퇴 시까지
   - 서비스 제공 : 서비스 이용계약 종료 시까지
   - 고충처리 : 고충 처리 완료 후 3년'''
                      : '''1. Wefilling processes and retains personal data within the retention and use period prescribed by law or the retention and use period agreed upon when collecting personal data from data subjects.

2. The processing and retention period for each type of personal data is as follows:
   - Membership registration and management: Until membership withdrawal
   - Service provision: Until termination of service use contract
   - Complaint handling: 3 years after complaint resolution'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第3条 向第三方提供'
                  : isKo
                      ? '제3조 개인정보의 제3자 제공'
                      : 'Article 3 Third-Party Provision'),
              (isChineseUi(context)
                  ? 'Wefilling仅在第1条（个人信息处理目的）规定的范围内处理个人信息，并仅在取得本人同意、法律有特别规定等符合《个人信息保护法》第17条的情况下向第三方提供个人信息。\n\n目前，Wefilling不向第三方提供个人信息。'
                  : isKo
                      ? '''Wefilling은 정보주체의 개인정보를 제1조(개인정보의 처리목적)에서 명시한 범위 내에서만 처리하며, 정보주체의 동의, 법률의 특별한 규정 등 개인정보보호법 제17조에 해당하는 경우에만 개인정보를 제3자에게 제공합니다.

현재 Wefilling은 개인정보를 제3자에게 제공하지 않습니다.'''
                      : '''Wefilling processes personal data of data subjects only within the scope specified in Article 1 (Purpose of Processing Personal Data) and provides personal data to third parties only in cases corresponding to Article 17 of the Personal Information Protection Act, such as with data subject consent or special legal provisions.

Currently, Wefilling does not provide personal data to third parties.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第4条 委托处理'
                  : isKo
                      ? '제4조 개인정보처리의 위탁'
                      : 'Article 4 Outsourcing'),
              (isChineseUi(context)
                  ? '1. 为顺利处理个人信息，Wefilling委托以下服务商处理相关事务。\n\n▶ 受托方\n   - 公司：Firebase（Google LLC）\n   - 委托事务：会员管理、提供服务所需的系统运行\n   - 委托期限：服务提供期间\n\n2. 签订委托合同时，Wefilling依据《个人信息保护法》第26条，在合同等文件中明确禁止超出委托目的处理个人信息、技术和管理保护措施、再委托限制、受托方管理监督及损害赔偿责任等事项，并监督受托方是否安全处理个人信息。'
                  : isKo
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

2. When concluding outsourcing contracts, Wefilling specifies in contracts and other documents matters concerning prohibition of personal data processing beyond outsourced task performance purposes, technical and administrative protection measures, restrictions on re-outsourcing, management and supervision of contractors, and liability for damages in accordance with Article 26 of the Personal Information Protection Act, and supervises whether contractors safely process personal data.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第5条 个人信息主体的权利及行使方式'
                  : isKo
                      ? '제5조 정보주체의 권리·의무 및 행사방법'
                      : 'Article 5 Data Subject Rights and Exercise Methods'),
              (isChineseUi(context)
                  ? '1. 个人信息主体可随时向Wefilling行使以下权利：\n   - 请求查阅个人信息\n   - 请求更正或删除个人信息\n   - 请求停止处理个人信息\n\n2. 可依据《个人信息保护法》实施细则附表第8号，通过书面、电子邮件、传真等方式行使第1款的权利，Wefilling将及时采取措施。\n\n3. 如请求更正或删除个人信息中的错误，在更正或删除完成前，Wefilling不会使用或提供该个人信息。\n\n4. 可通过法定代理人或受托人行使第1款的权利。此时，须提交《个人信息保护法》实施细则附表第11号规定的授权委托书。'
                  : isKo
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

4. Rights under paragraph 1 may be exercised through agents such as legal representatives or authorized persons of data subjects. In this case, a power of attorney according to Form No. 11 attached to the Enforcement Rules of the Personal Information Protection Act must be submitted.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第6条 处理的个人信息项目'
                  : isKo
                      ? '제6조 처리하는 개인정보 항목'
                      : 'Article 6 Personal Data Items Processed'),
              (isChineseUi(context)
                  ? 'Wefilling处理以下个人信息：\n\n1. 注册信息\n   - 电子邮箱、昵称、头像（选填）\n\n2. 自动收集的信息\n   - 服务使用记录、访问日志、Cookie、访问IP信息、设备信息'
                  : isKo
                      ? '''Wefilling은 다음의 개인정보 항목을 처리하고 있습니다.

1. 필수항목
   - 이메일 주소, 닉네임, 프로필 사진(선택)

2. 자동 수집 항목
   - 서비스 이용 기록, 접속 로그, 쿠키, 접속 IP 정보, 기기정보'''
                      : '''Wefilling processes the following personal data items:

1. Required Items
   - Email address, nickname, profile photo (optional)

2. Automatically Collected Items
   - Service usage records, access logs, cookies, access IP information, device information'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第7条 个人信息销毁'
                  : isKo
                      ? '제7조 개인정보의 파기'
                      : 'Article 7 Destruction of Personal Data'),
              (isChineseUi(context)
                  ? '1. 保存期限届满、处理目的达成等导致个人信息不再需要时，Wefilling将及时销毁。\n\n2. 销毁程序和方法如下：\n\n▶ 销毁程序\n   - 不再需要的个人信息及个人信息文件，经个人信息保护负责人批准后销毁。\n\n▶ 销毁方法\n   - 电子文件：使用无法恢复记录的技术方法删除\n   - 纸质文件：通过粉碎或焚烧销毁'
                  : isKo
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
   - Paper documents: Destroyed by shredding or incineration'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第8条 安全保障措施'
                  : isKo
                      ? '제8조 개인정보의 안전성 확보조치'
                      : 'Article 8 Security Measures'),
              (isChineseUi(context)
                  ? 'Wefilling采取以下措施保障个人信息安全：\n\n1. 管理措施：制定并实施内部管理计划、定期开展员工培训等。\n2. 技术措施：管理个人信息处理系统的访问权限、安装访问控制系统、加密唯一身份识别信息、安装安全程序。\n3. 物理措施：限制机房、资料保管室等场所的访问。'
                  : isKo
                      ? '''Wefilling은 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.

1. 관리적 조치: 내부관리계획 수립·시행, 정기적 직원 교육 등
2. 기술적 조치: 개인정보처리시스템 등의 접근권한 관리, 접근통제시스템 설치, 고유식별정보 등의 암호화, 보안프로그램 설치
3. 물리적 조치: 전산실, 자료보관실 등의 접근통제'''
                      : '''Wefilling takes the following measures to ensure the security of personal data:

1. Administrative Measures: Establishment and implementation of internal management plans, regular employee training, etc.
2. Technical Measures: Access authority management for personal data processing systems, installation of access control systems, encryption of unique identification information, installation of security programs
3. Physical Measures: Access control for computer rooms, data storage rooms, etc.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第9条 个人信息保护负责人'
                  : isKo
                      ? '제9조 개인정보 보호책임자'
                      : 'Article 9 Privacy Officer'),
              (isChineseUi(context)
                  ? 'Wefilling指定以下个人信息保护负责人，统筹个人信息处理事务，并处理相关投诉和损害救济。\n\n▶ 个人信息保护负责人\n   - 姓名：Christopher Watson\n   - 联系方式：wefilling@gmail.com\n\n▶ 个人信息保护部门\n   - 联系人：Christopher Watson\n   - 联系方式：wefilling@gmail.com\n\n使用Wefilling服务时，如有与个人信息保护相关的咨询、投诉或损害救济需求，可联系上述负责人和部门。Christopher Watson将及时答复并处理相关咨询。'
                  : isKo
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

Data subjects may contact the privacy officer and department regarding all personal information protection-related inquiries, complaint handling, damage relief, etc. that arise while using Wefilling services. Christopher Watson will respond to and process data subject inquiries without delay.'''),
            ),
            _buildSection(
              context,
              (isChineseUi(context)
                  ? '第10条 权利受侵害时的救济途径'
                  : isKo
                      ? '제10조 권익침해 구제방법'
                      : 'Article 10 Remedies for Rights Violations'),
              (isChineseUi(context)
                  ? '如需举报个人信息侵权或咨询，可联系以下机构：\n\n▶ 个人信息侵权举报中心（privacy.go.kr）\n   - 举报电话：118（免费）\n   - 地址：韩国首尔市中区世宗大路209号政府首尔办公大楼4层（01300）\n\n▶ 个人信息纠纷调解委员会（www.kopico.go.kr）\n   - 举报电话：1833-6972（免费）\n   - 地址：韩国首尔市钟路区世宗大路209号政府首尔办公大楼4层（03171）\n\n▶ 大检察厅网络犯罪部门（www.spo.go.kr）\n   - 举报电话：1301（免费）\n\n▶ 警察厅网络犯罪举报系统（police.go.kr）\n   - 举报电话：182（免费）\n\n▶ 中央行政审判委员会（www.simpan.go.kr）\n   - 电话：110'
                  : isKo
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
   - Phone: 110'''),
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
                  Text(
                    (isChineseUi(context)
                        ? '附则'
                        : isKo
                            ? '부칙'
                            : 'Addendum'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (isChineseUi(context)
                        ? '本隐私政策自2025年11月25日起生效。\n历史版本可在下方查看。'
                        : isKo
                            ? '이 개인정보 처리방침은 2025년 11월 25일부터 적용됩니다.\n이전의 개인정보 처리방침은 아래에서 확인하실 수 있습니다.'
                            : 'This Privacy Policy takes effect on November 25, 2025.\nPrevious versions can be found below.'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (isChineseUi(context)
                        ? '联系方式：wefilling@gmail.com'
                        : isKo
                            ? '문의: wefilling@gmail.com'
                            : 'Contact: wefilling@gmail.com'),
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 14,
                      color: Color(0xFF6B7280),
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

  Widget _buildSection(BuildContext context, String title, String content) {
    final localizedContent = isChineseUi(context)
        ? content.replaceAll(
            'Wefilling',
            AppLocalizations.of(context)!.appName,
          )
        : content;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            localizedContent,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
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
