import 'package:flutter/material.dart';

import 'ui.dart';

class NewsItem {
  const NewsItem(
    this.title,
    this.summary,
    this.category,
    this.time,
    this.icon,
    this.color,
    this.body,
  );
  final String title, summary, category, time, body;
  final IconData icon;
  final Color color;
}

const demoNews = [
  NewsItem(
    'Heavy rainfall across Nairobi',
    'A preview of how weather advisories will appear in your feed.',
    'Weather Alerts',
    '2 hours ago',
    Icons.thunderstorm_outlined,
    blue,
    'This sample advisory demonstrates the weather update screen. In the connected application, an update will include the issuing organisation, affected areas, issue time, and a link to the original advisory.\n\nNo current weather event is being reported by this prototype.',
  ),
  NewsItem(
    'A closer look at Nairobi River',
    'Understand how river-level updates could help you plan ahead.',
    'River Levels',
    '5 hours ago',
    Icons.waves_rounded,
    Color(0xFF218EAA),
    'This is an example river-level update. Future observations will show their source, measurement time, and location.\n\nThe research model is still in development. This example does not report a measured river level or a verified flood prediction.',
  ),
  NewsItem(
    'Know your neighbourhood',
    'A little preparation can make a difference when conditions change.',
    'Safety Tips',
    '8 hours ago',
    Icons.explore_outlined,
    green,
    'This page previews a neighbourhood preparedness article. The final application will link to reviewed information and relevant local authorities.\n\nSaved locations, assembly points, and route details are planned features. The places and routes shown in this demo are illustrative.',
  ),
  NewsItem(
    'Your rainy-season checklist',
    'A place for practical guidance and trusted information.',
    'Safety Tips',
    '1 day ago',
    Icons.checklist_rounded,
    Color(0xFFB68128),
    'This sample article shows the space for a rainy-season checklist, supporting illustrations, and links to official guidance.\n\nThe production content will be reviewed and attributed before release. You can explore the interface without relying on this prototype for emergency decisions.',
  ),
];

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  String _filter = 'All Updates';
  @override
  Widget build(BuildContext context) {
    final items = demoNews
        .where((n) => _filter == 'All Updates' || n.category == _filter)
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1060),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DemoBadge(label: 'THE COMMUNITY BRIEF'),
              const SizedBox(height: 14),
              Text('Flood news & updates', style: titleStyle(34)),
              const SizedBox(height: 10),
              const Text(
                'A clearer view of what’s happening around you.',
                style: TextStyle(color: muted, fontSize: 16),
              ),
              const SizedBox(height: 22),
              const Surface(
                color: Color(0xFFEDF4FF),
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: blue, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sample stories for this demo. These are not current news or official alerts.',
                        style: TextStyle(fontSize: 12, color: navy),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children:
                      [
                            'All Updates',
                            'Weather Alerts',
                            'River Levels',
                            'Safety Tips',
                          ]
                          .map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f),
                                selected: _filter == f,
                                onSelected: (_) => setState(() => _filter = f),
                                showCheckmark: false,
                                selectedColor: blue,
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _filter == f ? Colors.white : muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                side: BorderSide(
                                  color: _filter == f ? blue : line,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth < 680) {
                    return Column(
                      children: items
                          .map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: NewsCard(item: n),
                            ),
                          )
                          .toList(),
                    );
                  }
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: items
                        .map(
                          (n) => SizedBox(
                            width: (c.maxWidth - 20) / 2,
                            child: NewsCard(item: n),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'You’re all caught up with the demo feed.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item, this.compact = false});
  final NewsItem item;
  final bool compact;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => openNews(context, item),
      child: Surface(
        padding: EdgeInsets.all(compact ? 15 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: StoryPainter(
                            color: item.color,
                            weather: item.category == 'Weather Alerts',
                          ),
                        ),
                      ),
                      Positioned(
                        right: 22,
                        bottom: 20,
                        child: Icon(
                          item.icon,
                          size: 65,
                          color: Colors.white.withValues(alpha: .9),
                        ),
                      ),
                      const Positioned(
                        top: 12,
                        left: 12,
                        child: DemoBadge(label: 'DEMO STORY'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.category.toUpperCase(),
                    style: TextStyle(
                      color: item.color,
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  item.time,
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(item.title, style: titleStyle(compact ? 19 : 23)),
            const SizedBox(height: 8),
            Text(
              item.summary,
              style: const TextStyle(fontSize: 13, color: muted, height: 1.5),
            ),
            if (!compact) ...[
              const SizedBox(height: 16),
              const Row(
                children: [
                  Text(
                    'Read story',
                    style: TextStyle(
                      color: blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 7),
                  Icon(Icons.arrow_forward, size: 15, color: blue),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void openNews(BuildContext context, NewsItem item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          26,
          10,
          26,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DemoBadge(label: 'SAMPLE CONTENT'),
              const SizedBox(height: 18),
              Text(item.title, style: titleStyle(30)),
              const SizedBox(height: 12),
              Text(
                '${item.category} · Demo editorial',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Text(
                item.body,
                style: const TextStyle(height: 1.8, fontSize: 15),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to updates'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StoryPainter extends CustomPainter {
  StoryPainter({required this.color, required this.weather});
  final Color color;
  final bool weather;
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .5)!, color],
        ).createShader(Offset.zero & s),
    );
    for (int i = 0; i < 14; i++) {
      final height = 22.0 + (i * 19 % 55);
      c.drawRect(
        Rect.fromLTWH(
          i * s.width / 14,
          s.height - height,
          s.width / 18,
          height,
        ),
        Paint()..color = Colors.white.withValues(alpha: .13),
      );
    }
    final p = Path()
      ..moveTo(0, s.height * .8)
      ..cubicTo(
        s.width * .3,
        s.height * .35,
        s.width * .6,
        s.height * 1.3,
        s.width,
        s.height * .7,
      )
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(p, Paint()..color = Colors.white.withValues(alpha: .2));
    c.drawCircle(
      Offset(s.width * .18, s.height * .3),
      24,
      Paint()..color = Colors.white.withValues(alpha: .15),
    );
    if (weather) {
      for (int i = 0; i < 8; i++) {
        c.drawLine(
          Offset(35 + i * 24, 20),
          Offset(25 + i * 24, 42),
          Paint()
            ..color = Colors.white.withValues(alpha: .25)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant StoryPainter old) =>
      old.color != color || old.weather != weather;
}
