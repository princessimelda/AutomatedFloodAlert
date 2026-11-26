import 'dart:async';

import 'package:flutter/material.dart';

import '../dashboard/dashboard_data.dart';
import '../ui.dart';
import 'account_repository.dart';
import 'account_errors.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    this.selected,
    this.resetPassword = false,
  });
  final AccountRepository? repository;
  final Place? selected;
  final bool resetPassword;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _emailField = GlobalKey<FormFieldState<String>>();
  final _form = GlobalKey<FormState>();
  StreamSubscription<void>? _subscription;
  List<SavedPlace> _places = [];
  bool _busy = false;
  bool _showPassword = false,
      _creatingAccount = false,
      _changingPassword = false;
  String? _message;
  int _request = 0;
  String? _owner;
  @override
  void initState() {
    super.initState();
    _owner = widget.repository?.userId;
    _subscription = widget.repository?.changes.listen((_) {
      if (_owner != widget.repository?.userId) {
        _owner = widget.repository?.userId;
        _places = [];
        _password.clear();
        _request++;
        if (mounted) setState(() {});
        scheduleMicrotask(_refresh);
      }
      if (mounted) setState(() {});
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final places = await widget.repository?.savedPlaces() ?? <SavedPlace>[];
      if (mounted && request == _request) setState(() => _places = places);
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _message = 'Could not load saved places. Try refreshing.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _message = accountErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final signedIn = repository?.userId != null;
    final recovery = repository is AccountRecoveryRepository
        ? repository as AccountRecoveryRepository
        : null;
    final resetting =
        signedIn &&
        (widget.resetPassword ||
            _changingPassword ||
            recovery?.passwordRecoveryRequired == true);
    return Scaffold(
      appBar: AppBar(title: const Text('Your FloodSafe')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  resetting
                      ? 'Set a new password'
                      : signedIn
                      ? 'Your saved places'
                      : 'Sign in to save places',
                  style: titleStyle(28),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sign-in is optional. You can check places and read preparedness steps as a guest. Saving a place does not enable alerts.',
                ),
                const SizedBox(height: 20),
                if (repository == null)
                  const Text(
                    'Account services are not configured in this build. You can continue using Home as a guest.',
                  ),
                if (repository != null && !signedIn)
                  Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          TextFormField(
                            key: _emailField,
                            controller: _email,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            validator: (v) =>
                                v != null &&
                                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                        .hasMatch(v.trim())
                                ? null
                                : 'Enter a valid email address.',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            obscureText: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter your password.';
                              }
                              if (_creatingAccount && v.length < 8) {
                                return 'Use at least 8 characters.';
                              }
                              return null;
                            },
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              label: Text(
                                _showPassword
                                    ? 'Hide password'
                                    : 'Show password',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _creatingAccount = false;
                                    if (_form.currentState!.validate()) {
                                      _run(() async {
                                        await repository.signIn(
                                          _email.text.trim(),
                                          _password.text,
                                        );
                                        _password.clear();
                                        await _refresh();
                                      });
                                    }
                                  },
                            child: const Text('Sign in'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    _creatingAccount = true;
                                    if (_form.currentState!.validate()) {
                                      _run(() async {
                                        final active = await repository.signUp(
                                          _email.text.trim(),
                                          _password.text,
                                        );
                                        _password.clear();
                                        if (mounted) {
                                          setState(
                                            () => _message = active
                                                ? 'Account created.'
                                                : 'Check your email for confirmation. If you already have an account, sign in or choose Forgot password. Creating an account again does not reset your password.',
                                          );
                                        }
                                      });
                                    }
                                  },
                            child: const Text('Create an account'),
                          ),
                          if (recovery != null) ...[
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      if (_emailField.currentState!
                                          .validate()) {
                                        _run(() async {
                                          await recovery.requestPasswordReset(
                                            _email.text.trim(),
                                          );
                                          if (mounted) {
                                            setState(
                                              () => _message = 'If this email has an account, a password reset link has been sent. Check your inbox and spam folder. Open the latest link in this browser.',
                                            );
                                          }
                                        });
                                      }
                                    },
                              child: const Text('Forgot password'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      if (_emailField.currentState!
                                          .validate()) {
                                        _run(() async {
                                          await recovery.resendConfirmation(
                                            _email.text.trim(),
                                          );
                                          if (mounted) {
                                            setState(
                                              () => _message = 'If confirmation is needed, an email has been sent. Check your inbox and spam folder.',
                                            );
                                          }
                                        });
                                      }
                                    },
                              child: const Text('Resend confirmation email'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (resetting && recovery != null) ...[
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _password,
                          decoration: const InputDecoration(
                            labelText: 'New password',
                          ),
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (value) =>
                              value != null && value.length >= 8
                              ? null
                              : 'Use at least 8 characters.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmation,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                          ),
                          obscureText: true,
                          validator: (value) => value == _password.text
                              ? null
                              : 'The passwords do not match.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  if (_form.currentState!.validate()) {
                                    _run(() async {
                                      await recovery.updatePassword(
                                        _password.text,
                                      );
                                      _password.clear();
                                      _confirmation.clear();
                                      if (mounted) {
                                        setState(() {
                                          _changingPassword = false;
                                          _message = 'Password updated. Use your new password next time you sign in.';
                                        });
                                      }
                                    });
                                  }
                                },
                          child: const Text('Save new password'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (signedIn && !resetting) ...[
                  if (recovery != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _changingPassword = true),
                      child: const Text('Change password'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _run(_refresh),
                    child: const Text('Refresh saved places'),
                  ),
                  if (widget.selected != null &&
                      !widget.selected!.id.startsWith('gps:'))
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              await repository!.save(widget.selected!);
                              await _refresh();
                            }),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text('Save ${widget.selected!.name}'),
                    ),
                  if (_places.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No saved places yet. Choose a place on Home, then save it here.',
                      ),
                    ),
                  ..._places.map(
                    (saved) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(saved.place.name, style: titleStyle(21)),
                            if (saved.isDefault) const Text('Default place'),
                            if (saved.place.isDemo)
                              const Text(
                                'Sample scenario · not a current flood report',
                              ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context, saved.place),
                              child: Text('View ${saved.place.name}'),
                            ),
                            if (!saved.isDefault)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        await repository!.makeDefault(saved.id);
                                        await _refresh();
                                      }),
                                child: Text('Make ${saved.place.name} default'),
                              ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await repository!.remove(saved.id);
                                      await _refresh();
                                    }),
                              child: Text('Remove ${saved.place.name}'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repository!.signOut();
                            if (mounted) setState(() => _places = []);
                          }),
                    child: const Text('Sign out'),
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Updating your account',
                    ),
                  ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Home'),
                ),
                if (!signedIn) ...[
                  const SizedBox(height: 24),
                  const Landscape(height: 140),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
