import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui.dart';

const seasonalSource =
    'https://meteo.go.ke/our-products/seasonal-forecast/october-november-decemberond-national-climate-outlook-forum-ncof13/';

class SeasonalAdvisory extends StatelessWidget {
  const SeasonalAdvisory({super.key, this.now});
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final time = (now ?? DateTime.now()).toUtc();
    final current =
        !time.isBefore(DateTime.utc(2026, 10)) &&
        time.isBefore(DateTime.utc(2027));
    return Surface(
      color: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            current
                ? 'Seasonal outlook · October–December 2026'
                : 'Past seasonal outlook · October–December 2026',
            style: titleStyle(21),
          ),
          const SizedBox(height: 12),
          Text(
            current
                ? 'The national seasonal outlook expects above-average rainfall in Nairobi, with wet spells and occasional storms.'
                : 'This seasonal outlook has ended. Check the latest forecasts before making decisions.',
          ),
          if (current) ...[
            const SizedBox(height: 10),
            const Text(
              'Prepare your household and check daily and weekly forecasts. This seasonal outlook does not confirm flooding at your location.',
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Issued 26 August 2026 · Kenya Meteorological Service Authority (KMSA)\nNCOF13 technical statement, pages 1–4.',
            style: TextStyle(color: muted, height: 1.5),
          ),
          TextButton.icon(
            onPressed: () async {
              final opened = await launchUrl(Uri.parse(seasonalSource));
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Visit meteo.go.ke for the seasonal statement.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Read the official seasonal outlook'),
          ),
        ],
      ),
    );
  }
}
