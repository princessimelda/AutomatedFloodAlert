import 'package:flutter/material.dart';

import 'ui.dart';

const siteSections = [
  'Home',
  'Alerts',
  'Map',
  'Prepare',
  'Help',
  'Emergency Help',
];

class SiteNavigation extends StatelessWidget {
  const SiteNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onAccount,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: navy,
    child: SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 1180 &&
              MediaQuery.textScalerOf(context).scale(16) <= 22;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 32 : 8,
              vertical: 12,
            ),
            child: Row(
              children: [
                Material(
                  color: paper,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelect(0),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Brand(tagline: false),
                    ),
                  ),
                ),
                const Spacer(),
                if (wide)
                  for (var i = 0; i < siteSections.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: TextButton(
                        key: Key('nav-$i'),
                        onPressed: () => onSelect(i),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: selected == i
                              ? blue
                              : Colors.transparent,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        child: Text(siteSections[i]),
                      ),
                    )
                else
                  PopupMenuButton<int>(
                    tooltip: 'Open navigation menu',
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onSelected: onSelect,
                    itemBuilder: (_) => [
                      for (var i = 0; i < siteSections.length; i++)
                        PopupMenuItem(value: i, child: Text(siteSections[i])),
                    ],
                  ),
                IconButton(
                  onPressed: onAccount,
                  tooltip: 'Your profile and sign-in options',
                  icon: const Icon(Icons.person_outline, color: Colors.white),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class IntroSection extends StatelessWidget {
  const IntroSection({super.key, required this.onMap, required this.onPrepare});
  final VoidCallback onMap, onPrepare;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      return Container(
        key: const Key('home-intro'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: compact ? 1 : .60,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/images/flood-damage.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: compact
                        ? [
                            paper.withValues(alpha: .97),
                            paper.withValues(alpha: .90),
                          ]
                        : [
                            paper,
                            paper.withValues(alpha: .98),
                            paper.withValues(alpha: .05),
                          ],
                    stops: compact ? null : const [0, .47, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 24 : 48),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FLOODSAFE · NAIROBI',
                      style: TextStyle(
                        color: navy,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        'Stay ahead of the flood.',
                        style: titleStyle(compact ? 36 : 56),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Know your area. Find available flood updates, prepare your household and reach emergency support.',
                      style: TextStyle(fontSize: 19, height: 1.5),
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: onMap,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('View flood map'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onPrepare,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('Learn more'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });
  final String title, description;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(16),
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
              Semantics(
                header: true,
                child: Text(title, style: titleStyle(34)),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(color: muted, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
