import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'site_widgets.dart';
import 'ui.dart';

class EmergencyHelp extends StatelessWidget {
  const EmergencyHelp({super.key});

  Future<void> _call(BuildContext context, String number) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: number.replaceAll(' ', '')),
      );
      if (opened) return;
    } catch (_) {
      /* Show the number if no dialler is available. */
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Call $number using your phone.')),
    );
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const PageIntro(
            title: 'Emergency Help',
            description:
                'Quick access to emergency services and support in Nairobi.',
            icon: Icons.emergency_outlined,
          ),
          Surface(
            color: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need urgent help?', style: titleStyle(24)),
                const SizedBox(height: 8),
                const Text(
                  'Call the national emergency line. Tell the operator where you are and what has happened.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _call(context, '112'),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call 112'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _call(context, '999'),
                      icon: const Icon(Icons.call_outlined),
                      label: const Text('Call 999'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 850
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  _contact(
                    context,
                    width,
                    'Kenya Red Cross',
                    'Disaster response, rescue and relief.',
                    Icons.health_and_safety_outlined,
                    '1199',
                    const [],
                    'https://redcross.or.ke/ready-before-the-first-case/3/',
                  ),
                  _contact(
                    context,
                    width,
                    'St John Ambulance',
                    'Emergency medical and ambulance support.',
                    Icons.local_hospital_outlined,
                    '0721 225 285',
                    const [],
                    'https://www.stjohnkenya.org/contact',
                  ),
                  _contact(
                    context,
                    width,
                    'National Disaster Operations Centre',
                    'Disaster coordination and flood reporting.',
                    Icons.support_agent,
                    '0800 721 571',
                    const ['020 221 2386', '0758 547 049', '0776 390 897'],
                    'https://www.ndoc.go.ke/taxonomy/term/12',
                  ),
                  _contact(
                    context,
                    width,
                    'Nairobi County Fire & Rescue',
                    'County emergency and fire assistance.',
                    Icons.local_fire_department_outlined,
                    '1508',
                    const ['020 222 2181', '020 234 4599'],
                    'https://nairobi.go.ke',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Surface(
            color: accent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: blue),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Help responders find you', style: titleStyle(23)),
                      const SizedBox(height: 8),
                      const Text(
                        'Give your location or nearest landmark, describe the emergency and say how many people need help. FloodSafe cannot dispatch responders.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _contact(
    BuildContext context,
    double width,
    String title,
    String description,
    IconData icon,
    String number,
    List<String> alternatives,
    String source,
  ) => SizedBox(
    width: width,
    child: Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Icon(icon, color: blue, size: 30),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle(23)),
                    const SizedBox(height: 8),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SelectableText(number, style: titleStyle(28)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _call(context, number),
            icon: const Icon(Icons.call_outlined),
            label: Text('Call $number'),
          ),
          if (alternatives.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More contact numbers'),
              children: [
                for (final alternative in alternatives)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _call(context, alternative),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(alternative),
                    ),
                  ),
              ],
            ),
          TextButton(
            onPressed: () async {
              await launchUrl(Uri.parse(source));
            },
            child: const Text('Organisation website'),
          ),
        ],
      ),
    ),
  );
}
