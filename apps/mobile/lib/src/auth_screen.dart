import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/l10n/localized_error.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen(
      {required this.api, required this.onAuthenticated, super.key});

  final ApiClient api;
  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _storage = FlutterSecureStorage();
  static const _lastEmailKey = 'last_login_email';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _salary = TextEditingController();
  var _registering = false;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
  }

  Future<void> _loadLastEmail() async {
    final email = await _storage.read(key: _lastEmailKey);
    if (mounted && email != null) _email.text = email;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _salary.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_registering) {
        final salary =
            double.tryParse(_salary.text.replaceAll(',', '').trim()) ?? -1;
        await widget.api.register(
            name: _name.text,
            email: _email.text,
            phone: _phone.text,
            password: _password.text,
            salaryCents: (salary * 100).round());
      } else {
        await widget.api.login(email: _email.text, password: _password.text);
      }
      await widget.api.persistSession();
      await _storage.write(key: _lastEmailKey, value: _email.text.trim());
      if (mounted) widget.onAuthenticated();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error =
            localizedError(AppLocalizations.of(context)!, error.message));
      }
    } catch (_) {
      if (mounted)
        setState(
            () => _error = AppLocalizations.of(context)!.cannotReachServer);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(l10n.appTitle.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                          letterSpacing: 2,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(_registering ? l10n.createYourAccount : l10n.welcomeBack,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  if (_registering) ...[
                    TextField(
                        key: const Key('auth-name-field'),
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration:
                            InputDecoration(labelText: l10n.accountName)),
                    const SizedBox(height: 12),
                    TextField(
                        key: const Key('auth-salary-field'),
                        controller: _salary,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                            labelText: l10n.monthlySalary,
                            prefixText: r'$ ',
                            suffixText: 'MXN')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                      key: const Key('auth-email-field'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: l10n.email)),
                  const SizedBox(height: 12),
                  if (_registering) ...[
                    TextField(
                        key: const Key('auth-phone-field'),
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                            labelText: l10n.mexicanMobileNumber,
                            hintText: '55 1234 5678')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                      key: const Key('auth-password-field'),
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _submitting ? null : _submit(),
                      decoration: InputDecoration(labelText: l10n.password)),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error))),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('auth-submit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_registering ? l10n.createAccount : l10n.signIn),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _registering = !_registering;
                              _error = null;
                            }),
                    child: Text(
                        _registering ? l10n.alreadyHaveAccount : l10n.newHere),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
