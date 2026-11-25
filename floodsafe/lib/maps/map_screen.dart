import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';

import '../account/account_repository.dart';
import '../dashboard/dashboard_data.dart';
import '../data/content_repository.dart';
import '../location/location_service.dart';
import '../ui.dart';
import '../site_widgets.dart';
import 'map_locations.dart';
import 'route_repository.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selected,
    required this.content,
    required this.locationService,
    this.account,
    this.tileProvider,
    this.embedded = false,
    this.onPlaceSelected,
    this.routes,
  });
  final Place? selected;
  final ContentRepository content;
  final LocationService locationService;
  final AccountRepository? account;
  final TileProvider? tileProvider;
  final bool embedded;
  final ValueChanged<Place>? onPlaceSelected;
  final RouteRepository? routes;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = MapController();
  StreamSubscription<void>? _authChanges;
  List<Place> _places = [];
  List<SavedPlace> _saved = [];
  Place? _selected;
  String? _owner, _error, _locationError;
  bool _loading = true, _locating = false, _tilesFailed = false, _ready = false;
  String _query = '';
  int _loadRequest = 0, _locationRequest = 0, _tilesVersion = 0;
  WalkingRoute? _route;
  LatLng? _destination;
  final List<LatLng> _blocked = [];
  bool _routing = false, _avoidSteps = true;
  String? _routeError, _tapMode;
  int _routeRequest = 0;
  Timer? _routeExpiry;

  void _clearRoute() {
    _routeRequest++;
    _routeExpiry?.cancel();
    _route = null;
    _routing = false;
    _routeError = null;
  }

  Future<void> _findRoute() async {
    final origin = mapPosition(_selected);
    final repository = widget.routes;
    if (origin == null || repository == null) return;
    _clearRoute();
    final request = _routeRequest;
    setState(() {
      _routing = true;
      _tapMode = null;
    });
    try {
      final route = await repository
          .findRoute(
            origin: origin,
            destination: _destination,
            avoidSteps: _avoidSteps,
            blocked: List.of(_blocked),
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted || request != _routeRequest) return;
      if (!route.validUntil.isAfter(DateTime.now().toUtc())) {
        throw StateError('Expired route');
      }
      setState(() {
        _route = route;
        _routing = false;
      });
      if (_ready && route.points.length > 1) {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(route.points),
            padding: const EdgeInsets.all(40),
          ),
        );
      }
      _routeExpiry = Timer(route.validUntil.difference(DateTime.now().toUtc()), () {
        if (mounted) {
          setState(() {
            _clearRoute();
            _routeError =
                'This route has expired. Search again for updated information.';
          });
        }
      });
    } catch (_) {
      if (!mounted || request != _routeRequest) return;
      setState(() {
        _routing = false;
        _routeError = 'We could not find a route right now. Try again shortly or contact Emergency Help.';
      });
    }
  }

  void _mapTap(LatLng point) {
    final mode = _tapMode;
    if (mode == null) return;
    if (mode == 'start') {
      _select(
        Place(
          id: 'gps:map',
          name: 'Chosen starting point',
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      );
    }
    setState(() {
      _clearRoute();
      if (mode == 'destination') _destination = point;
      if (mode == 'blocked' && _blocked.length < 12) _blocked.add(point);
      _tapMode = null;
    });
  }

  Widget _routePanel() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Find a walking route', style: titleStyle(25)),
        const SizedBox(height: 10),
        Text(
          _selected == null
              ? 'Choose a starting place or use your location.'
              : 'Starting near ${_selected!.name}.',
        ),
        const Text(
          'Find a mapped assembly point or choose your destination. Flood safety and destination availability cannot be confirmed.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _clearRoute();
                _tapMode = 'start';
              }),
              icon: const Icon(Icons.trip_origin),
              label: const Text('Choose start on map'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _clearRoute();
                _tapMode = 'destination';
              }),
              icon: const Icon(Icons.place_outlined),
              label: Text(
                _destination == null
                    ? 'Choose destination on map'
                    : 'Change destination',
              ),
            ),
            if (_destination != null)
              TextButton(
                onPressed: () => setState(() {
                  _clearRoute();
                  _destination = null;
                }),
                child: const Text('Use nearest assembly point'),
              ),
            OutlinedButton.icon(
              onPressed: _blocked.length >= 12
                  ? null
                  : () => setState(() {
                      _clearRoute();
                      _tapMode = 'blocked';
                    }),
              icon: const Icon(Icons.block),
              label: const Text('Mark blocked road'),
            ),
            if (_blocked.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _clearRoute();
                  _blocked.clear();
                }),
                child: Text('Clear ${_blocked.length} blocked points'),
              ),
          ],
        ),
        if (_tapMode != null)
          Semantics(
            liveRegion: true,
            child: Text(
              'Tap the map to mark ${_tapMode == 'start'
                  ? 'your starting point'
                  : _tapMode == 'blocked'
                  ? 'a blocked road'
                  : 'your destination'}.',
            ),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Avoid mapped stairs'),
          subtitle: const Text(
            'Other accessibility conditions are not verified.',
          ),
          value: _avoidSteps,
          onChanged: (value) => setState(() {
            _clearRoute();
            _avoidSteps = value ?? true;
          }),
        ),
        FilledButton.icon(
          onPressed:
              _routing ||
                  mapPosition(_selected) == null ||
                  widget.routes == null
              ? null
              : _findRoute,
          icon: const Icon(Icons.directions_walk),
          label: Text(
            _routing
                ? 'Finding route…'
                : _destination == null
                ? 'Find nearest mapped assembly point'
                : 'Find walking route',
          ),
        ),
        if (widget.routes == null)
          const Text('Route search needs a connection to FloodSafe.'),
        if (_routing)
          const LinearProgressIndicator(
            semanticsLabel: 'Finding walking route',
          ),
        if (_routeError != null)
          Semantics(liveRegion: true, child: Text(_routeError!)),
        if (_route != null) ...[
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: Text(_route!.message)),
          if (_route!.status == 'found') ...[
            const SizedBox(height: 10),
            Text(
              _route!.destinationName ?? 'Chosen destination',
              style: titleStyle(21),
            ),
            Text(
              '${_route!.distanceM} m · about ${_route!.minutes} minutes on mapped roads',
            ),
            Text(
              'Route starts ${_route!.startGap} m from your pin and ends ${_route!.endGap} m from the destination. These connections are not verified.',
            ),
            ExpansionTile(
              title: const Text('Route details'),
              children: [
                for (final road in _route!.roads) ListTile(title: Text(road)),
                const Text(
                  'OpenStreetMap contributors · walking-time estimate excludes delays. Blocked points are used only for this search.',
                ),
              ],
            ),
          ],
        ],
      ],
    ),
  );
  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
    _owner = widget.account?.userId;
    _authChanges = widget.account?.changes.listen((_) {
      final owner = widget.account?.userId;
      if (owner != _owner) {
        _owner = owner;
        _locationRequest++;
        setState(() {
          _clearRoute();
          _destination = null;
          _blocked.clear();
          _saved = [];
          _selected = null;
          _locating = false;
        });
        scheduleMicrotask(_load);
      }
    });
    _load();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final places = await widget.content.listPlaces().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted || request != _loadRequest) return;
      setState(() => _places = places);
      final saved =
          await widget.account?.savedPlaces().timeout(
            const Duration(seconds: 12),
          ) ??
          <SavedPlace>[];
      if (!mounted || request != _loadRequest) return;
      setState(() => _saved = saved);
    } catch (_) {
      if (mounted && request == _loadRequest) {
        setState(
          () => _error = 'Some places could not be loaded. Retry, or return to Home to choose a place.',
        );
      }
    } finally {
      if (mounted && request == _loadRequest) setState(() => _loading = false);
    }
  }

  void _select(Place place) {
    _locationRequest++;
    setState(() {
      _clearRoute();
      _selected = place;
      _locating = false;
      _locationError = null;
    });
    final position = mapPosition(place);
    if (_ready && position != null) {
      _controller.move(position, place.id.startsWith('gps:') ? 16 : 14);
    }
  }

  Future<void> _locate() async {
    final request = ++_locationRequest;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final place = await widget.locationService.currentPlace().timeout(
        const Duration(seconds: 30),
      );
      if (!mounted || request != _locationRequest) return;
      _select(place);
    } catch (error) {
      if (!mounted || request != _locationRequest) return;
      setState(() {
        _locating = false;
        _locationError = error is LocationFailure
            ? error.message
            : 'Could not locate you. Choose a place below or use Home.';
      });
    }
  }

  void _tileError() {
    if (_tilesFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tilesFailed) setState(() => _tilesFailed = true);
    });
  }

  @override
  void dispose() {
    _clearRoute();
    _loadRequest++;
    _locationRequest++;
    _authChanges?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double change) {
    if (_ready) {
      _controller.move(
        _controller.camera.center,
        (_controller.camera.zoom + change).clamp(3, 19).toDouble(),
      );
    }
  }

  Widget _search() => TextField(
    key: const Key('map-search'),
    decoration: const InputDecoration(
      labelText: 'Search places',
      hintText: 'For example, Westlands or Embakasi',
      prefixIcon: Icon(Icons.search),
    ),
    onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
  );

  @override
  Widget build(BuildContext context) {
    final position = mapPosition(_selected);
    final gps = _selected?.id.startsWith('gps:') == true;
    final savedIds = _saved.map((s) => s.place.id).toSet();
    final markers = <String, Place>{
      for (final place in _places) place.id: place,
      for (final saved in _saved) saved.place.id: saved.place,
    };
    final selected = _selected;
    if (selected != null) markers[selected.id] = selected;
    final places = _places.where((p) => p.name.toLowerCase().contains(_query));
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Flood map')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const PageIntro(
                  title: 'Flood risk map',
                  description:
                      'Explore your area and find available flood information.',
                  icon: Icons.map_outlined,
                ),
                Surface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final location = FilledButton.icon(
                            onPressed: _locating ? null : _locate,
                            icon: const Icon(Icons.my_location),
                            label: Text(
                              _locating
                                  ? 'Finding location…'
                                  : 'Use my location',
                            ),
                          );
                          final zoom = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _zoom(1),
                                tooltip: 'Zoom in',
                                icon: const Icon(Icons.add),
                              ),
                              IconButton(
                                onPressed: () => _zoom(-1),
                                tooltip: 'Zoom out',
                                icon: const Icon(Icons.remove),
                              ),
                            ],
                          );
                          return constraints.maxWidth >= 760
                              ? Row(
                                  children: [
                                    location,
                                    const SizedBox(width: 16),
                                    Expanded(child: _search()),
                                    const SizedBox(width: 12),
                                    zoom,
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _search(),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [location, zoom],
                                    ),
                                  ],
                                );
                        },
                      ),
                      if (_locationError != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_locationError!),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: MediaQuery.sizeOf(context).width >= 900
                            ? 420
                            : 340,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: FlutterMap(
                            mapController: _controller,
                            options: MapOptions(
                              keepAlive: true,
                              initialCenter: position ?? nairobiCentre,
                              initialZoom: position == null ? 11 : 14,
                              minZoom: 3,
                              maxZoom: 19,
                              onMapReady: () => _ready = true,
                              onTap: (_, point) => _mapTap(point),
                            ),
                            children: [
                              TileLayer(
                                key: ValueKey(_tilesVersion),
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.floodsafe',
                                maxNativeZoom: 19,
                                panBuffer: 0,
                                tileProvider: widget.tileProvider,
                                errorTileCallback: (_, _, _) => _tileError(),
                              ),
                              if (_route?.status == 'found')
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: _route!.points,
                                      strokeWidth: 5,
                                      color: blue,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  if (_destination != null)
                                    Marker(
                                      point: _destination!,
                                      width: 48,
                                      height: 48,
                                      child: const Tooltip(
                                        message: 'Chosen destination, flood safety unverified',
                                        child: Icon(
                                          Icons.flag,
                                          color: navy,
                                          size: 36,
                                        ),
                                      ),
                                    ),
                                  if (_route?.status == 'found' &&
                                      _destination == null)
                                    Marker(
                                      point: _route!.points.last,
                                      width: 48,
                                      height: 48,
                                      child: const Tooltip(
                                        message: 'Mapped assembly point, flood safety unverified',
                                        child: Icon(
                                          Icons.flag,
                                          color: navy,
                                          size: 36,
                                        ),
                                      ),
                                    ),
                                  for (final point in _blocked)
                                    Marker(
                                      point: point,
                                      width: 40,
                                      height: 40,
                                      child: const Tooltip(
                                        message: 'Blocked road to avoid',
                                        child: Icon(
                                          Icons.block,
                                          color: Colors.red,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (gps &&
                                  position != null &&
                                  _selected!.accuracyMeters != null)
                                CircleLayer(
                                  circles: [
                                    CircleMarker(
                                      point: position,
                                      radius: _selected!.accuracyMeters!,
                                      useRadiusInMeter: true,
                                      color: blue.withValues(alpha: .16),
                                      borderColor: blue,
                                      borderStrokeWidth: 2,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: [
                                  for (final place in markers.values)
                                    if (mapPosition(place) != null)
                                      Marker(
                                        point: mapPosition(place)!,
                                        width: 48,
                                        height: 48,
                                        child: IconButton(
                                          tooltip: place.id.startsWith('gps:')
                                              ? 'Your device position'
                                              : '${place.name}${savedIds.contains(place.id) ? ', saved place' : ', neighbourhood centre'}',
                                          onPressed: () => _select(place),
                                          icon: Icon(
                                            place.id.startsWith('gps:')
                                                ? Icons.my_location
                                                : savedIds.contains(place.id)
                                                ? Icons.bookmark
                                                : Icons.location_on,
                                            size: 32,
                                            color: place.id == _selected?.id
                                                ? navy
                                                : blue,
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                              const Align(
                                alignment: Alignment.bottomRight,
                                child: ColoredBox(
                                  color: Colors.white,
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Text(
                                      '© OpenStreetMap contributors',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final opened = await launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                          );
                          if (!opened && mounted) {
                            setState(
                              () => _error = 'Attribution: https://www.openstreetmap.org/copyright',
                            );
                          }
                        },
                        child: const Text('© OpenStreetMap contributors'),
                      ),
                      if (_tilesFailed) ...[
                        const Text(
                          'The map could not fully load. You can still choose a place below.',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _tilesFailed = false;
                            _tilesVersion++;
                          }),
                          child: const Text('Retry map tiles'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _routePanel(),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final list = Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Choose a place without using the map',
                            style: titleStyle(23),
                          ),
                          const SizedBox(height: 8),
                          const Text('Supported neighbourhoods'),
                          if (_loading) const Text('Loading places…'),
                          if (_error != null) ...[
                            Semantics(liveRegion: true, child: Text(_error!)),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry places'),
                            ),
                          ],
                          if (_saved.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('Saved places'),
                            for (final saved in _saved)
                              ListTile(
                                title: Text(saved.place.name),
                                subtitle: Text(
                                  saved.isDefault
                                      ? 'Saved · default place'
                                      : 'Saved place',
                                ),
                                trailing: const Icon(Icons.bookmark_outline),
                                onTap: () => _select(saved.place),
                              ),
                          ],
                          if (!_loading && places.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No matching places found.'),
                            ),
                          for (final place in places)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.location_on_outlined,
                                color: blue,
                              ),
                              title: Text(place.name, style: titleStyle(18)),
                              subtitle: const Text('Neighbourhood centre'),
                              selected: place.id == _selected?.id,
                              selectedTileColor: accent,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _select(place),
                            ),
                        ],
                      ),
                    );
                    final conditions = Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Current conditions', style: titleStyle(25)),
                          const SizedBox(height: 20),
                          if (_selected != null) ...[
                            Text(_selected!.name, style: titleStyle(23)),
                            const SizedBox(height: 8),
                            Text(
                              gps
                                  ? 'Device location${_selected!.accuracyMeters == null ? '' : ' · accuracy ±${_selected!.accuracyMeters!.round()} m'}'
                                  : 'Approximate neighbourhood centre',
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'No current flood update for this area.',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'An update is needed before current flood conditions can be confirmed.',
                            ),
                            if (position == null)
                              const Text(
                                'No map position is available for this place.',
                              ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: () {
                                if (widget.onPlaceSelected != null) {
                                  widget.onPlaceSelected!(_selected!);
                                } else {
                                  Navigator.pop(context, _selected);
                                }
                              },
                              child: const Text('View information on Home'),
                            ),
                            OutlinedButton(
                              onPressed: position == null
                                  ? null
                                  : () => _select(_selected!),
                              child: const Text('Centre on selection'),
                            ),
                          ] else
                            const Text(
                              'Choose a place on the map or from the list to view its information.',
                            ),
                        ],
                      ),
                    );
                    return constraints.maxWidth >= 950
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: list),
                              const SizedBox(width: 20),
                              Expanded(flex: 3, child: conditions),
                            ],
                          )
                        : Column(
                            children: [
                              conditions,
                              const SizedBox(height: 20),
                              list,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                Surface(
                  color: accent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: blue),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pins mark places, not flood-risk levels. Suggested routes cannot confirm that a road or destination is safe from flooding.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
