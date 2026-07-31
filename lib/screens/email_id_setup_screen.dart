import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/signup_flow_widgets.dart';
import 'password_setup_screen.dart';

/// Legacy two-step email sign-up entry kept visually aligned with the active
/// sign-up flow for callers that still navigate here.
class EmailIdSetupScreen extends StatefulWidget {
  const EmailIdSetupScreen({
    super.key,
    required this.verifiedHanyangEmail,
  });

  final String verifiedHanyangEmail;

  @override
  State<EmailIdSetupScreen> createState() => _EmailIdSetupScreenState();
}

class _EmailIdSetupScreenState extends State<EmailIdSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasswordSetupScreen(
          verifiedHanyangEmail: widget.verifiedHanyangEmail,
          loginEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: Color(0xFF0F172A),
          ),
        ),
        title: Text(
          l10n.emailIdSetupTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth < 360 ? 18.0 : 24.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                28 + bottomInset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SignupPageIntro(
                          icon: Icons.alternate_email_rounded,
                          title: l10n.emailIdSetupTitle,
                          description: l10n.emailIdSetupDescription,
                        ),
                        const SizedBox(height: 32),
                        SignupVerifiedEmail(
                          label: l10n.verifiedHanyangEmailLabel,
                          email: widget.verifiedHanyangEmail,
                        ),
                        const SizedBox(height: 34),
                        SignupSectionLabel(text: l10n.loginEmailLabel),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.newUsername],
                          onFieldSubmitted: (_) => _goToNextStep(),
                          decoration: signupInputDecoration(
                            hintText: 'example@gmail.com',
                            icon: Icons.mail_outline_rounded,
                            helperText: l10n.loginEmailHelper,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F172A),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return l10n.pleaseEnterEmail;
                            if (!email.contains('@') ||
                                !email.split('@').last.contains('.')) {
                              return l10n.validEmailFormat;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              _emailController.text =
                                  widget.verifiedHanyangEmail;
                            },
                            icon: const Icon(Icons.school_outlined, size: 18),
                            label: Text(l10n.useVerifiedHanyangEmail),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SignupPrimaryButton(
                          label: l10n.next,
                          onPressed: _goToNextStep,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 18),
                          SignupInlineError(message: _errorMessage!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
