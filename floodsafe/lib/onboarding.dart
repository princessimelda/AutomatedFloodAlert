import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_form.currentState!.validate()) return;
    var phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('0')) phone = phone.substring(1);
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => VerifyScreen(phone: '+254 $phone'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DemoBadge(label: 'NAIROBI · DEMO EXPERIENCE'),
          const SizedBox(height: 24),
          Text('Welcome', style: titleStyle(38)),
          const SizedBox(height: 16),
          const Text(
            'Enter your phone number to create an account or log in to FloodSafe.',
            style: TextStyle(color: muted, fontSize: 16, height: 1.65),
          ),
          const SizedBox(height: 32),
          const Text(
            'Phone number',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('phone-input'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              hintText: '712 345 678',
              prefixIcon: Padding(
                padding: EdgeInsets.fromLTRB(16, 15, 12, 15),
                child: Text(
                  '🇰🇪  +254',
                  style: TextStyle(
                    fontSize: 16,
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            validator: (value) => RegExp(r'^0?[17]\d{8}$').hasMatch(value ?? '')
                ? null
                : 'Enter a Kenyan number, e.g. 712345678.',
            onFieldSubmitted: (_) => _continue(),
          ),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: muted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Use a sample number. No SMS will be sent.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _continue,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue'),
                  SizedBox(width: 14),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
              child: const Text('Explore the demo first'),
            ),
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Expanded(child: Divider(color: line)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  'HERE TO HELP YOU',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.6,
                    color: muted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: line)),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _benefit(Icons.layers_outlined, 'Understand risk'),
              _benefit(Icons.notifications_none_rounded, 'Stay informed'),
              _benefit(Icons.near_me_outlined, 'Plan ahead'),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              onPressed: () => showInfo(
                context,
                'About FloodSafe',
                'FloodSafe is a Nairobi-focused flood-awareness project. This prototype previews location-based risk information, updates, and assistance. All risk areas, routes, and updates in this demo are illustrative.',
              ),
              child: const Text(
                'Learn more about FloodSafe',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Preview our ',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              TextButton(
                onPressed: () => showInfo(
                  context,
                  'Terms of service',
                  'This is a demonstration interface. Final terms of service will be added before public release. The demo does not provide live flood warnings or verified evacuation routes.',
                ),
                child: const Text('Terms', style: TextStyle(fontSize: 11)),
              ),
              const Text(' and ', style: TextStyle(color: muted, fontSize: 11)),
              TextButton(
                onPressed: () => showInfo(
                  context,
                  'Privacy',
                  'This prototype does not send SMS, request your actual location, or save your phone number to a server. Demo selections last only for the current session.',
                ),
                child: const Text('Privacy', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _benefit(IconData icon, String text) => Expanded(
    child: Column(
      children: [
        Icon(icon, color: blue, size: 23),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: muted),
        ),
      ],
    ),
  );
}

class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.child, this.back = false});
  final Widget child;
  final bool back;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          final form = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 32 : 26,
                  vertical: 26,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (back)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Go back',
                        ),
                      ),
                    if (!wide) ...[
                      const Brand(large: true),
                      const SizedBox(height: 38),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          );
          if (!wide) {
            return SingleChildScrollView(
              child: Column(children: [form, const Landscape(height: 120)]),
            );
          }
          return Row(
            children: [
              Expanded(
                child: Container(
                  color: const Color(0xFFEAF3FF),
                  child: LayoutBuilder(
                    builder: (context, panel) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: panel.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(44),
                                child: Brand(large: true),
                              ),
                              Expanded(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 50,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const DemoBadge(
                                          label: 'BUILT FOR NAIROBI',
                                        ),
                                        const SizedBox(height: 28),
                                        Text(
                                          'Your city.\nYour community.\nYour peace of mind.',
                                          style: titleStyle(
                                            48,
                                          ).copyWith(color: navy, height: 1.2),
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'A clearer picture of flood risk,\nright where you are.',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: muted,
                                            height: 1.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Landscape(height: 230),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: SingleChildScrollView(child: form)),
            ],
          );
        },
      ),
    ),
  );
}

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.phone});
  final String phone;
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());
  Timer? _timer;
  int _remaining = 30;
  String? _error;
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _verify() {
    if (_controllers.map((c) => c.text).join() != '123456') {
      setState(() => _error = 'For this demo, enter the code 123456.');
      return;
    }
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    back: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DemoBadge(label: 'STEP 02 · VERIFICATION'),
        const SizedBox(height: 24),
        Text('Verify your number', style: titleStyle(36)),
        const SizedBox(height: 16),
        const Text(
          'Your updates, one step closer.',
          style: TextStyle(color: muted, fontSize: 16),
        ),
        const SizedBox(height: 14),
        Text(
          widget.phone,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: navy,
          ),
        ),
        const SizedBox(height: 24),
        const Surface(
          color: Color(0xFFEDF4FF),
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.science_outlined, color: blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Demo code: 123456\nNo message has been sent.',
                  style: TextStyle(color: navy, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Row(
          children: List.generate(
            6,
            (i) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 5 ? 0 : 8),
                child: TextField(
                  key: Key('otp-$i'),
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(1),
                  ],
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 17),
                    semanticCounterText: 'Digit ${i + 1} of 6',
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty && i < 5) {
                      _nodes[i + 1].requestFocus();
                    } else if (v.isEmpty && i > 0) {
                      _nodes[i - 1].requestFocus();
                    }
                    setState(() => _error = null);
                  },
                  onSubmitted: (_) => _verify(),
                ),
              ),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: red, fontSize: 13),
            ),
          ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _remaining == 0
              ? () {
                  setState(() => _remaining = 30);
                  _startTimer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Demo code is still 123456. No SMS was sent.',
                      ),
                    ),
                  );
                }
              : null,
          child: Text(
            _remaining > 0
                ? 'Resend available in 00:${_remaining.toString().padLeft(2, '0')}'
                : 'Resend demo code',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _verify,
            child: const Text('Verify & continue'),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Change phone number'),
          ),
        ),
      ],
    ),
  );
}
