import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/context_x.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/sheets.dart';
import '../../profile/providers.dart';
import '../data/auth_repository.dart';
import 'brand.dart';

/// Shown while the session and profile load.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Wordmark(size: 40),
            const SizedBox(height: 28),
            if (profile.hasError || (profile.hasValue && profile.value == null)) ...[
              Text('Couldn\'t load your profile.', style: context.text.bodyMedium),
              const SizedBox(height: 12),
              AppButton(
                label: 'Try again',
                size: ButtonSize.medium,
                onPressed: () => ref.invalidate(myProfileProvider),
              ),
              LinkButton(label: 'Sign out', onPressed: () => ref.read(authRepositoryProvider).signOut()),
            ] else
              const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
          ],
        ),
      ),
    );
  }
}

/// Shared layout for the auth forms: back button, big title, content.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(AppIcons.back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: context.text.displaySmall),
              const SizedBox(height: Space.sm),
              Text(subtitle, style: context.text.bodyLarge!.copyWith(color: context.colors.inkMuted)),
              const SizedBox(height: Space.xxl + 4),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up where you left off.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                AppTextField(
                  label: 'College or personal email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Password',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: LinkButton(label: 'Forgot password?', onPressed: () => context.push('/forgot-password')),
        ),
        if (_error != null) _ErrorNote(_error!),
        const SizedBox(height: Space.lg),
        AppButton(label: 'Sign in', expand: true, loading: _busy, onPressed: _submit),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('New to Quad?', style: context.text.bodyMedium!.copyWith(color: context.colors.inkMuted)),
            LinkButton(label: 'Create an account', onPressed: () => context.pushReplacement('/sign-up')),
          ],
        ),
      ],
    );
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _confirmEmailFor;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ready = await ref
          .read(authRepositoryProvider)
          .signUp(name: _name.text, email: _email.text, password: _password.text);
      if (!ready && mounted) setState(() => _confirmEmailFor = _email.text.trim());
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmEmailFor != null) return _CheckInbox(email: _confirmEmailFor!);
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'It takes a minute. You\'ll set up your profile next.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.name,
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: Validators.email,
                ),
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Password',
                  controller: _password,
                  obscure: true,
                  helper: 'At least 8 characters',
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.password,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: Space.md), _ErrorNote(_error!)],
        const SizedBox(height: Space.xxl),
        AppButton(label: 'Create account', expand: true, loading: _busy, onPressed: _submit),
        const SizedBox(height: Space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already on Quad?', style: context.text.bodyMedium!.copyWith(color: context.colors.inkMuted)),
            LinkButton(label: 'Sign in', onPressed: () => context.pushReplacement('/sign-in')),
          ],
        ),
      ],
    );
  }
}

class _CheckInbox extends ConsumerWidget {
  const _CheckInbox({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(20)),
                child: Icon(AppIcons.checkCircle, color: c.accent, size: 30),
              ),
              const SizedBox(height: Space.xl),
              Text('Check your inbox', style: context.text.displaySmall),
              const SizedBox(height: Space.sm),
              Text.rich(
                TextSpan(
                  text: 'We sent a confirmation link to ',
                  children: [
                    TextSpan(text: email, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                    const TextSpan(text: '. Open it, then come back and sign in.'),
                  ],
                ),
                style: context.text.bodyLarge!.copyWith(color: c.inkMuted),
              ),
              const Spacer(flex: 2),
              AppButton(label: 'Go to sign in', expand: true, onPressed: () => context.go('/sign-in')),
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'Resend email',
                variant: ButtonVariant.ghost,
                expand: true,
                onPressed: () async {
                  try {
                    await ref.read(authRepositoryProvider).resendConfirmation(email);
                    if (context.mounted) showToast(context, 'Sent again. It can take a minute.');
                  } catch (error) {
                    if (context.mounted) showToast(context, friendlyError(error), error: true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) showToast(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Reset password',
      subtitle: _sent
          ? 'If an account exists for that email, a reset link is on its way.'
          : 'Enter your email and we\'ll send you a link to set a new password.',
      children: [
        if (!_sent) ...[
          Form(
            key: _form,
            child: AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: Space.xxl),
          AppButton(label: 'Send reset link', expand: true, loading: _busy, onPressed: _submit),
        ] else
          AppButton(label: 'Back to sign in', expand: true, onPressed: () => context.go('/sign-in')),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.warning, color: c.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: context.text.bodyMedium!.copyWith(color: c.danger))),
        ],
      ),
    );
  }
}
