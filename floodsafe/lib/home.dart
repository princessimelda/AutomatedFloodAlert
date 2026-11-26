import 'dart:async';

import 'package:flutter/material.dart';

import 'assistant_screen.dart';
import 'dashboard/dashboard_controller.dart';
import 'dashboard/dashboard_data.dart';
import 'maps/map_screen.dart';
import 'location/location_service.dart';
import 'account/account_repository.dart';
import 'account/account_screen.dart';
import 'ui.dart';
import 'data/content_repository.dart';
import 'assistant/assistant_repository.dart';
import 'alerts/alert_repository.dart';
import 'alerts/alert_inbox.dart';
import 'site_widgets.dart';
import 'emergency_help.dart';
import 'seasonal_advisory.dart';
import 'maps/route_repository.dart';
import 'data/local_information_repository.dart';
import 'place_search.dart';
import 'rainfall_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.repository,
    this.locationService,
    this.contentRepository,
    this.assistantRepository,
    this.accountRepository,
    this.connectedToApi = false,
  });
  final DashboardRepository? repository;
  final LocationService? locationService;
  final ContentRepository? contentRepository;
  final AssistantRepository? assistantRepository;
  final AccountRepository? accountRepository;
  final bool connectedToApi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DashboardController _dashboard;
  late final LocationService _locationService;
  late final ContentRepository _content;
  StreamSubscription<void>? _accountChanges;
  String? _owner;
  int _defaultRequest = 0;
  int _tab = 0;
  int _locationRequest = 0;
  bool _locating = false;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _dashboard = DashboardController(
      repository: widget.repository ?? FixtureDashboardRepository(),
    )..addListener(_onDashboardChanged);
    _locationService = widget.locationService ?? ForegroundLocationService();
    _content = widget.contentRepository ?? const FixtureContentRepository();
    _owner = widget.accountRepository?.userId;
    _accountChanges = widget.accountRepository?.changes.listen((_) {
      final owner = widget.accountRepository?.userId;
      if (_owner != owner) {
        _owner = owner;
        _defaultRequest++;
        _locationRequest++;
        _locating = false;
        _locationError = null;
        _dashboard.clear();
        scheduleMicrotask(_restoreDefault);
      }
    });
    _restoreDefault();
  }

  Future<void> _restoreDefault() async {
    final request = ++_defaultRequest;
    final owner = widget.accountRepository?.userId;
    if (owner == null) return;
    try {
      final places = await widget.accountRepository!.savedPlaces();
      if (!mounted ||
          request != _defaultRequest ||
          owner != widget.accountRepository?.userId ||
          _dashboard.place != null) {
        return;
      }
      for (final saved in places) {
        if (saved.isDefault) {
          await _dashboard.selectPlace(saved.place);
          break;
        }
      }
    } catch (_) {
      /* Manual place selection remains available. */
    }
  }

  void _onDashboardChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _locationRequest++;
    _defaultRequest++;
    _accountChanges?.cancel();
    _dashboard.removeListener(_onDashboardChanged);
    _dashboard.dispose();
    super.dispose();
  }

  Future<void> _choosePlace() async {
    _defaultRequest++;
    // A manual choice supersedes a pending GPS result.
    _locationRequest++;
    setState(() {
      _locating = false;
      _locationError = null;
    });
    final place = await showDialog<Place>(
      context: context,
      builder: (_) => LocationPicker(
        current: _dashboard.place?.id,
        repository: _content,
        connectedToApi: widget.connectedToApi,
      ),
    );
    if (place != null && mounted) await _dashboard.selectPlace(place);
  }

  Future<void> _useLocation() async {
    _defaultRequest++;
    final request = ++_locationRequest;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final place = await _locationService.currentPlace().timeout(
        const Duration(seconds: 30),
      );
      if (!mounted || request != _locationRequest) return;
      setState(() => _locating = false);
      await _dashboard.selectPlace(place);
    } on LocationFailure catch (failure) {
      if (!mounted || request != _locationRequest) return;
      setState(() {
        _locating = false;
        _locationError = failure.message;
      });
    } catch (_) {
      if (!mounted || request != _locationRequest) return;
      setState(() {
        _locating = false;
        _locationError =
            'Could not get your location. Try again or choose a place.';
      });
    }
  }

  void _openGuidance() => setState(() => _tab = 3);

  Future<void> _profile() async {
    _defaultRequest++;
    final place = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountScreen(
          repository: widget.accountRepository,
          selected: _dashboard.place,
        ),
      ),
    );
    if (!mounted) return;
    if (place != null) {
      _locationRequest++;
      await _dashboard.selectPlace(place);
    } else {
      await _restoreDefault();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(80),
      child: SiteNavigation(
        selected: _tab,
        onSelect: (tab) => setState(() => _tab = tab),
        onAccount: _profile,
      ),
    ),
    body: SafeArea(
      child: switch (_tab) {
        0 => _home(),
        1 => AlertInbox(
          repository: widget.repository is AlertRepository
              ? widget.repository as AlertRepository
              : const EmptyAlertRepository(),
          onSignIn: _profile,
          accountId: widget.accountRepository?.userId,
          placeId: _dashboard.place?.id.startsWith('gps:') == false
              ? _dashboard.place?.id
              : null,
        ),
        2 => MapScreen(
          routes: widget.repository is RouteRepository
              ? widget.repository as RouteRepository
              : null,
          selected: _dashboard.place,
          content: _content,
          locationService: _locationService,
          account: widget.accountRepository,
          embedded: true,
          onPlaceSelected: (place) async {
            setState(() => _tab = 0);
            await _dashboard.selectPlace(place);
          },
        ),
        3 => PreparednessScreen(
          repository: widget.connectedToApi ? _content : null,
          place: _dashboard.place,
          embedded: true,
        ),
        4 => AssistantScreen(
          repository:
              widget.assistantRepository ?? const EmptyAssistantRepository(),
        ),
        _ => const EmergencyHelp(),
      },
    ),
  );

  Widget _home() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1240),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntroSection(onMap: _openMap, onPrepare: _openGuidance),
            const SizedBox(height: 32),
            Text('Your area at a glance', style: titleStyle(30)),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _placeCard()),
                        const SizedBox(width: 20),
                        Expanded(child: _situationCard()),
                      ],
                    )
                  : Column(
                      children: [
                        _placeCard(),
                        const SizedBox(height: 16),
                        _situationCard(),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            if (_dashboard.place != null &&
                widget.repository is WeatherRepository) ...[
              Surface(
                child: RainfallPanel(
                  place: _dashboard.place!,
                  repository: widget.repository as WeatherRepository,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('What to do next', style: titleStyle(24)),
                  ),
                  const SizedBox(height: 12),
                  Text(_nextStep, style: const TextStyle(height: 1.5)),
                  const SizedBox(height: 10),
                  const Text(
                    'For your household preparedness. Follow local instructions during an emergency.',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('read-guidance'),
              onPressed: _openGuidance,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Read preparedness steps'),
            ),
            const SizedBox(height: 20),
            _mapPreview(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );

  Widget _placeCard() {
    final place = _dashboard.place;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Your location', style: titleStyle(20)),
          ),
          const SizedBox(height: 12),
          Text(
            place?.name ?? 'No place selected',
            key: const Key('selected-place'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            place?.accuracyMeters != null
                ? 'Location found, accurate to about ${place!.accuracyMeters!.round()} m. Used for this check only; not saved or tracked.'
                : place?.latitude != null
                ? 'Approximate place location. Used for this check only; not saved or tracked.'
                : 'Location is optional. Used once; not saved or tracked.',
            style: const TextStyle(color: muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('location-search'),
                  onPressed: _choosePlace,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.all(10),
                  ),
                  child: Text(
                    place == null ? 'Choose a place' : 'Change place',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const Key('use-location'),
                  onPressed: _locating ? null : _useLocation,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.all(10),
                  ),
                  child: Text(
                    _locating ? 'Finding location…' : 'Use my location',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          if (_locating) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: const Text(
                'Waiting for location permission or a location fix. You can choose a place instead.',
              ),
            ),
          ],
          if (_locationError != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _locationError!,
                style: const TextStyle(color: red, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _situationCard() {
    final status = _dashboard.status;
    final data = _dashboard.data;
    final assessment = data?.assessment;
    final ready = status == DashboardStatus.ready;
    final label = switch (status) {
      DashboardStatus.choosePlace => 'Choose a place to begin',
      DashboardStatus.loading => 'Checking selected place…',
      DashboardStatus.error => 'Could not load this place',
      DashboardStatus.unavailable => 'Risk information unavailable',
      DashboardStatus.stale => 'Information out of date',
      DashboardStatus.ready =>
        '${data!.isDemo ? 'Sample ' : ''}${assessment!.level.name} risk',
    };
    final colour = ready && assessment!.level == RiskLevel.high ? red : navy;
    final icon = ready
        ? switch (assessment!.level) {
            RiskLevel.high => Icons.warning_amber_rounded,
            RiskLevel.moderate => Icons.info_outline,
            RiskLevel.low => Icons.fact_check_outlined,
          }
        : switch (status) {
            DashboardStatus.loading => Icons.hourglass_top,
            DashboardStatus.stale => Icons.history,
            DashboardStatus.error => Icons.cloud_off_outlined,
            _ => Icons.help_outline,
          };
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Current situation', style: titleStyle(24)),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(icon, color: colour, size: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    key: const Key('risk-status'),
                    style: TextStyle(
                      color: colour,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(switch (status) {
            DashboardStatus.choosePlace => 'Choose your area to check available updates. You can read preparedness steps without sharing your location or signing in.',
            DashboardStatus.loading =>
              'Looking for the latest update for your area.',
            DashboardStatus.error => 'We could not retrieve an assessment. This does not mean the area is at low risk.',
            DashboardStatus.unavailable => 'No current assessment is available for this place. Missing information does not mean low risk.',
            DashboardStatus.stale => 'The previous update has expired. A new update is needed to describe current conditions.',
            DashboardStatus.ready =>
              data!.isDemo
                  ? 'This example shows how an update would look. It does not describe current conditions in ${_dashboard.place!.name}.'
                  : 'This update covers ${_dashboard.place!.name}. Check when it was updated below.',
          }, style: const TextStyle(height: 1.5)),
          if (data != null && assessment != null) ...[
            const SizedBox(height: 14),
            Text(
              'Source: ${data.source}',
              style: const TextStyle(color: muted, height: 1.5),
            ),
            Text(
              'Updated: ${_time(assessment.issuedAt)}',
              style: const TextStyle(color: muted, height: 1.5),
            ),
            Text(
              'Valid until: ${_time(assessment.validUntil)}',
              style: const TextStyle(color: muted, height: 1.5),
            ),
            if (data.isDemo)
              const Text(
                'Example only · Not current conditions',
                style: TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w700,
                  height: 1.8,
                ),
              ),
          ],
          if (_dashboard.place != null && !_dashboard.loading) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              key: const Key('refresh-dashboard'),
              onPressed: _dashboard.refresh,
              icon: const Icon(Icons.refresh),
              label: Text(
                status == DashboardStatus.error
                    ? 'Try again'
                    : 'Refresh information',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _nextStep => switch (_dashboard.status) {
    DashboardStatus.choosePlace => 'Choose a place to explore its information. You can read general preparedness steps now.',
    DashboardStatus.loading =>
      'While information loads, you can read general preparedness steps.',
    DashboardStatus.ready =>
      _dashboard.data!.isDemo
          ? 'Practise finding preparedness guidance. This sample assessment does not tell you to evacuate or identify a safe route.'
          : 'Read preparedness guidance and follow instructions from local authorities.',
    _ => 'Current local risk cannot be confirmed here. Check official local updates and read general preparedness guidance.',
  };

  Future<void> _openMap() async {
    _defaultRequest++;
    _locationRequest++;
    setState(() {
      _locating = false;
      _locationError = null;
      _tab = 2;
    });
  }

  Widget _mapPreview() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Explore your area', style: titleStyle(23)),
        const SizedBox(height: 8),
        const Text(
          'View roads, rivers, your location and saved neighbourhoods on an interactive map.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openMap,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Open map'),
        ),
      ],
    ),
  );
}

String _time(DateTime value) =>
    '${value.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC';

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    this.current,
    this.repository = const FixtureContentRepository(),
    this.connectedToApi = false,
  });
  final String? current;
  final ContentRepository repository;
  final bool connectedToApi;
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  String _query = '';
  late Future<List<Place>> _places;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _places = widget.repository.listPlaces().timeout(
      const Duration(seconds: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Choose a place'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose the area you want to check.'),
            const SizedBox(height: 16),
            NairobiPlaceSearch(
              label: 'Search locations',
              repository: widget.repository is PlaceSearchRepository
                  ? widget.repository as PlaceSearchRepository
                  : null,
              onQueryChanged: (query) => setState(() => _query = query),
              onSelected: (place) => Navigator.pop(context, place),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Place>>(
              future: _places,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading places',
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Text(
                        'Could not load places. You can cancel and still read preparedness steps.',
                      ),
                      TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Retry places'),
                      ),
                    ],
                  );
                }
                final places = (snapshot.data ?? []).where(
                  (place) => place.name.toLowerCase().contains(
                    _query.trim().toLowerCase(),
                  ),
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (places.isEmpty &&
                        widget.repository is! PlaceSearchRepository)
                      Semantics(
                        liveRegion: true,
                        child: const Text('No matching places are available.'),
                      ),
                    ...places.map(
                      (place) => ListTile(
                        minVerticalPadding: 14,
                        contentPadding: EdgeInsets.zero,
                        title: Text(place.name),
                        subtitle: const Text('Nairobi'),
                        selected: place.id == widget.current,
                        trailing: Icon(
                          place.id == widget.current
                              ? Icons.check_circle_outline
                              : Icons.chevron_right,
                        ),
                        onTap: () => Navigator.pop(context, place),
                      ),
                    ),
                  ],
                );
              },
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

class PreparednessScreen extends StatelessWidget {
  const PreparednessScreen({
    super.key,
    this.repository,
    this.place,
    this.embedded = false,
  });
  final ContentRepository? repository;
  final Place? place;
  final bool embedded;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: embedded ? null : AppBar(title: const Text('Preparedness steps')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Semantics(
                header: true,
                child: Text('Preparedness steps', style: titleStyle(28)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Plan before you need to act. These steps help you prepare; follow local instructions during an emergency.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 20),
              if (repository == null) const SeasonalAdvisory(),
              if (repository != null)
                PublishedAdvisories(repository: repository!, place: place),
              ...const [
                (
                  '1. Avoid floodwater',
                  'Do not cross flooded roads on foot or in a vehicle.',
                ),
                (
                  '2. Make a plan',
                  'Discuss how your household will communicate and what you will do if flooding affects your area.',
                ),
                (
                  '3. Follow official instructions',
                  'Check current information from local authorities. Follow evacuation instructions when issued.',
                ),
              ].map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(step.$1, style: titleStyle(21)),
                        ),
                        const SizedBox(height: 10),
                        Text(step.$2, style: const TextStyle(height: 1.6)),
                      ],
                    ),
                  ),
                ),
              ),
              const SelectableText(
                'Sources\nKMSA — NCOF13 technical statement, issued 26 August 2026 (pages 1–4). Seasonal outlook for October–December 2026.\nhttps://meteo.go.ke/our-products/seasonal-forecast/october-november-decemberond-national-climate-outlook-forum-ncof13/\n\nCDC — Preparing for Floods\nhttps://www.cdc.gov/floods/safety/',
                style: TextStyle(color: muted, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PublishedAdvisories extends StatefulWidget {
  const PublishedAdvisories({super.key, required this.repository, this.place});
  final ContentRepository repository;
  final Place? place;
  @override
  State<PublishedAdvisories> createState() => _PublishedAdvisoriesState();
}

class _PublishedAdvisoriesState extends State<PublishedAdvisories> {
  late Future<List<Advisory>> _advisories;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _expiry?.cancel();
    _advisories = widget.repository
        .loadAdvisories(place: widget.place)
        .timeout(const Duration(seconds: 12))
        .then((items) {
          final now = DateTime.now().toUtc();
          final current = items.where((item) => item.current(now)).toList();
          if (mounted) _scheduleExpiry(current);
          return current;
        });
  }

  void _scheduleExpiry(List<Advisory> items) {
    _expiry?.cancel();
    final now = DateTime.now().toUtc();
    final current = items.where((item) => item.current(now)).toList();
    if (current.isEmpty || !mounted) return;
    final earliest = current
        .map((item) => item.validUntil)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _expiry = Timer(earliest.difference(now), () {
      if (mounted) {
        setState(() {});
        _scheduleExpiry(items);
      }
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text('Published advisories', style: titleStyle(23)),
      ),
      const SizedBox(height: 12),
      const SeasonalAdvisory(),
      const SizedBox(height: 16),
      FutureBuilder<List<Advisory>>(
        future: _advisories,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text(
              'Loading advisories… General preparedness steps remain below.',
            );
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Local advisories could not be loaded. Try again.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Retry advisories'),
                ),
              ],
            );
          }
          final current = (snapshot.data ?? []).where(
            (item) => !item.isDemo && item.current(DateTime.now().toUtc()),
          );
          if (current.isEmpty) {
            return const Text(
              'No additional local advisories are available right now.',
            );
          }
          return Column(
            children: current
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.isDemo)
                            const Text(
                              'TEST ADVISORY · Not an evacuation instruction',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: navy,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Semantics(
                            header: true,
                            child: Text(item.title, style: titleStyle(21)),
                          ),
                          const SizedBox(height: 12),
                          Text(item.body, style: const TextStyle(height: 1.6)),
                          const SizedBox(height: 12),
                          Text(
                            'Published: ${_time(item.publishedAt)}\nValid until: ${_time(item.validUntil)}',
                            style: const TextStyle(color: muted, height: 1.5),
                          ),
                          SelectableText(
                            'Source: ${item.source}\n${item.sourceUrl}',
                            style: const TextStyle(color: muted, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 20),
    ],
  );
}
