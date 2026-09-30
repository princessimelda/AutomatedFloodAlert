import 'package:flutter/material.dart';

import 'ui.dart';
import 'demo_map.dart';
import 'news.dart';
import 'assistant_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _located = false, _route = false;
  String _location = 'Kibera';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _locationPrompt();
      }
    });
  }

  void _locationPrompt() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        contentPadding: const EdgeInsets.fromLTRB(26, 24, 26, 26),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(19),
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF2FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: blue,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Start with your\nneighbourhood',
                style: titleStyle(29),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              const Text(
                'See how local risk information and nearby updates will look in FloodSafe.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 16),
              const DemoBadge(label: 'DEMO LOCATION · NO GPS ACCESS'),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('use-demo-location'),
                  onPressed: () {
                    setState(() => _located = true);
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Use demo location'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Choose a location myself'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => LocationPicker(current: _location),
    );
    if (selected != null && mounted) {
      setState(() {
        _location = selected;
        _located = true;
        _route = false;
      });
    }
  }

  void _profile() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 10, 26, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFFEAF2FF),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: blue,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Your FloodSafe', style: titleStyle(29)),
                const SizedBox(height: 6),
                const Text(
                  'Demo profile · Nairobi, Kenya',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_outline, color: blue),
                  title: const Text('Saved places'),
                  subtitle: const Text('Preview home and work locations'),
                  trailing: const DemoBadge(label: 'COMING LATER'),
                  onTap: () => showInfo(
                    sheetContext,
                    'Saved places',
                    'In a later version, you’ll be able to save home, work, and other places in Nairobi to follow updates for each location.',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_none, color: blue),
                  title: const Text('Notification preferences'),
                  subtitle: const Text('Alerts will be connected later'),
                  onTap: () => showInfo(
                    sheetContext,
                    'Notification preferences',
                    'Weather, river-level, and location-based notification settings will appear here. This prototype does not send background notifications.',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.language, color: blue),
                  title: Text('Language'),
                  trailing: Text('English', style: TextStyle(color: muted)),
                ),
                const Divider(color: line),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/',
                        (_) => false,
                      );
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Restart demo'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _riskDetails() => showInfo(
    context,
    'Understanding this risk preview',
    'The coloured regions demonstrate how high, moderate, and low risk could be displayed. They are illustrative shapes, not measured flood boundaries.\n\nSelected area: $_location, Nairobi.\n\nThe prediction model and live data connections will be integrated in a later phase.',
    icon: Icons.layers_outlined,
  );
  void _routeDetails() {
    setState(() => _route = !_route);
    if (_route) {
      showInfo(
        context,
        'Your route preview is ready',
        'A dashed green route and example assembly point now appear on the map. They demonstrate the planned interface and are not suitable for navigation.\n\nVerified destinations and routing logic will be connected later.',
        icon: Icons.alt_route_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final content = switch (_tab) {
        0 => _dashboard(wide),
        1 => const NewsScreen(),
        _ => const AssistantScreen(),
      };
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 235,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 32, 18, 32),
                        child: Brand(),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(26, 15, 0, 14),
                        child: Text(
                          'YOUR FLOODSAFE',
                          style: TextStyle(
                            fontSize: 9,
                            color: muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      _navItem(0, Icons.grid_view_rounded, 'Overview'),
                      _navItem(1, Icons.article_outlined, 'Flood News'),
                      _navItem(2, Icons.auto_awesome_outlined, 'AI Assistant'),
                      const Spacer(),
                      if (constraints.maxHeight >= 800)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Surface(
                            color: paper,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.favorite_border_rounded,
                                  color: blue,
                                  size: 22,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Made for our city.',
                                  style: titleStyle(19),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'A little awareness goes a long way.',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const DemoBadge(label: 'NAIROBI · ENGLISH'),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: TextButton.icon(
                          onPressed: _profile,
                          icon: const Icon(Icons.person_outline),
                          label: const Text('Your profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 30 : 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        children: [
                          if (!wide)
                            const Brand(tagline: false)
                          else ...[
                            const Icon(
                              Icons.location_on_outlined,
                              color: blue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Nairobi County, Kenya',
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ],
                          const Spacer(),
                          if (wide)
                            const DemoBadge(label: 'INTERACTIVE UI PROTOTYPE'),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: _profile,
                            tooltip: 'Your profile',
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFECF3FF),
                            ),
                            icon: const Icon(
                              Icons.person_outline_rounded,
                              color: navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                height: 73,
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xFFE4EEFF),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded, color: blue),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.article_outlined),
                    selectedIcon: Icon(Icons.article, color: blue),
                    label: 'Flood News',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon: Icon(Icons.auto_awesome, color: blue),
                    label: 'AI Assistant',
                  ),
                ],
              ),
      );
    },
  );
  Widget _navItem(int i, IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
    child: Material(
      color: _tab == i ? const Color(0xFFEAF2FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: _tab == i ? blue : muted, size: 21),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w500,
            color: _tab == i ? blue : muted,
          ),
        ),
        onTap: () => setState(() => _tab = i),
      ),
    ),
  );
  Widget _dashboard(bool wide) => SingleChildScrollView(
    padding: EdgeInsets.all(wide ? 30 : 20),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1250),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR NEIGHBOURHOOD, AT A GLANCE',
                        style: TextStyle(
                          color: muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Stay one step ahead.',
                        style: titleStyle(wide ? 36 : 29),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'A little local knowledge. A lot more peace of mind.',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (wide)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: DemoBadge(label: 'SAMPLE DATA'),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.science_outlined, size: 18, color: blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Demo mode · Risk areas, routes, and updates are illustrative, not live alerts.',
                      style: TextStyle(color: navy, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: _mapPanel(wide)),
                  const SizedBox(width: 22),
                  Expanded(flex: 4, child: _updates()),
                ],
              )
            else ...[
              _mapPanel(wide),
              const SizedBox(height: 24),
              _updates(),
            ],
            const SizedBox(height: 26),
            Surface(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_awesome_outlined, color: blue),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Questions? Start here.', style: titleStyle(20)),
                        const SizedBox(height: 5),
                        const Text(
                          'Explore your FloodSafe assistant.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _tab = 2),
                    tooltip: 'Open AI Assistant',
                    icon: const Icon(Icons.arrow_forward_rounded, color: blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'FloodSafe · Designed for a more informed Nairobi',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _mapPanel(bool wide) => Surface(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: paper,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              key: const Key('location-search'),
              onTap: _search,
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: navy, size: 23),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _located
                            ? '$_location, Nairobi'
                            : 'Search a Nairobi neighbourhood',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.tune_rounded, color: muted, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
        DemoMap(
          location: _location,
          showLocation: _located,
          route: _route,
          height: wide ? 425 : 365,
        ),
        const SizedBox(height: 12),
        if (!_located)
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: blue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Choose a demo location to explore local risk.',
                    style: TextStyle(fontSize: 12, color: navy),
                  ),
                ),
                IconButton(
                  onPressed: _search,
                  tooltip: 'Choose location',
                  icon: const Icon(Icons.arrow_forward, color: blue),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF7DCDD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFCE0E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        color: red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'High flood risk',
                            style: titleStyle(23).copyWith(color: red),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Sample scenario for $_location',
                            style: const TextStyle(
                              color: red,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'See how an area advisory and route option could appear here.',
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _riskDetails,
                      tooltip: 'Risk details',
                      icon: const Icon(Icons.chevron_right, color: red),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _routeDetails,
                    icon: Icon(
                      _route
                          ? Icons.visibility_off_outlined
                          : Icons.near_me_outlined,
                      size: 19,
                    ),
                    label: Text(
                      _route ? 'Hide demo route' : 'Preview safe-route feature',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _updates() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeading('Local outlook', trailing: const DemoBadge(label: 'DEMO')),
      const SizedBox(height: 15),
      Surface(
        color: const Color(0xFFEDF4FF),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'NAIROBI',
                    style: TextStyle(
                      color: navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.cloud_outlined,
                  color: blue.withValues(alpha: .75),
                  size: 35,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('19°', style: titleStyle(48).copyWith(color: navy)),
                const SizedBox(width: 16),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 9),
                    child: Text(
                      'Cloudy skies\nSample weather',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.water_drop_outlined, color: blue, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Rain 80%',
                      style: TextStyle(color: navy, fontSize: 11),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.air_rounded, color: blue, size: 17),
                    SizedBox(width: 6),
                    Text(
                      '12 km/h',
                      style: TextStyle(color: navy, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SectionHeading(
        'Latest updates',
        trailing: TextButton(
          onPressed: () => setState(() => _tab = 1),
          child: const Text('View all', style: TextStyle(fontSize: 12)),
        ),
      ),
      const SizedBox(height: 12),
      ...demoNews
          .take(3)
          .map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: NewsCard(item: n, compact: true),
            ),
          ),
    ],
  );
}

class LocationPicker extends StatefulWidget {
  const LocationPicker({super.key, required this.current});
  final String current;
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final locations = [
      'Kibera',
      'Westlands',
      'Embakasi',
      'Kasarani',
    ].where((l) => l.toLowerCase().contains(_query.toLowerCase())).toList();
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Explore Nairobi', style: titleStyle(27)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a sample neighbourhood.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search locations',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 14),
            if (locations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No demo locations found. Try Kibera or Westlands.',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
            ...locations.map(
              (l) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined, color: blue),
                title: Text(l),
                subtitle: const Text(
                  'Nairobi County',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: l == widget.current
                    ? const Icon(Icons.check_circle, color: blue, size: 18)
                    : const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.pop(context, l),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
