import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/account_repository.dart';
import '../dashboard/dashboard_data.dart';
import '../data/content_repository.dart';
import '../location/location_service.dart';
import '../ui.dart';
import 'map_locations.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selected,
    required this.content,
    required this.locationService,
    this.account,
    this.tileProvider,
  });
  final Place? selected;
  final ContentRepository content;
  final LocationService locationService;
  final AccountRepository? account;
  final TileProvider? tileProvider;
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
  int _loadRequest = 0, _locationRequest = 0, _tilesVersion = 0;
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
    _loadRequest++;
    _locationRequest++;
    _authChanges?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPosition = mapPosition(_selected);
    final gps = _selected?.id.startsWith('gps:') == true;
    final savedIds = _saved.map((s) => s.place.id).toSet();
    final markers = <String, Place>{
      for (final place in _places) place.id: place,
      for (final saved in _saved) saved.place.id: saved.place,
    };
    final selected = _selected;
    if (selected != null) markers[selected.id] = selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Explore the map')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Explore roads, rivers and places. Markers show approximate neighbourhood centres or your device position. Flood boundaries and evacuation routes are not available.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    _locating ? 'Finding location…' : 'Use my location',
                  ),
                ),
                OutlinedButton(
                  onPressed: selectedPosition == null
                      ? null
                      : () => _select(_selected!),
                  child: const Text('Centre on selection'),
                ),
                IconButton(
                  onPressed: () {
                    if (_ready) {
                      _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom + 1).clamp(3, 19).toDouble(),
                      );
                    }
                  },
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  onPressed: () {
                    if (_ready) {
                      _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom - 1).clamp(3, 19).toDouble(),
                      );
                    }
                  },
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.remove),
                ),
              ],
            ),
            if (_locationError != null)
              Semantics(liveRegion: true, child: Text(_locationError!)),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    keepAlive: true,
                    initialCenter: selectedPosition ?? nairobiCentre,
                    initialZoom: selectedPosition == null ? 11 : 14,
                    minZoom: 3,
                    maxZoom: 19,
                    onMapReady: () {
                      _ready = true;
                    },
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_tilesVersion),
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.floodsafe',
                      maxNativeZoom: 19,
                      panBuffer: 0,
                      tileProvider: widget.tileProvider,
                      errorTileCallback: (_, _, _) => _tileError(),
                    ),
                    if (gps &&
                        selectedPosition != null &&
                        _selected!.accuracyMeters != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: selectedPosition,
                            radius: _selected!.accuracyMeters!,
                            useRadiusInMeter: true,
                            color: blue.withValues(alpha: 0.16),
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
                    Align(
                      alignment: Alignment.bottomRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: const ColoredBox(
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
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final opened = await launchUrl(
                  Uri.parse('https://www.openstreetmap.org/copyright'),
                );
                if (!opened && mounted) {
                  setState(
                    () => _error =
                        'Attribution: https://www.openstreetmap.org/copyright',
                  );
                }
              },
              child: const Text('© OpenStreetMap contributors'),
            ),
            if (_tilesFailed) ...[
              const Text(
                'Some map tiles could not load. Place selection and Home information remain available.',
              ),
              TextButton(
                onPressed: () => setState(() {
                  _tilesFailed = false;
                  _tilesVersion++;
                }),
                child: const Text('Retry map tiles'),
              ),
            ],
            if (_selected != null)
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_selected!.name, style: titleStyle(23)),
                    Text(
                      gps
                          ? 'Device location${_selected!.accuracyMeters == null ? '' : ' · accuracy ±${_selected!.accuracyMeters!.round()} m'}'
                          : 'Approximate neighbourhood centre',
                    ),
                    if (selectedPosition != null)
                      Text(
                        '${selectedPosition.latitude.toStringAsFixed(5)}, ${selectedPosition.longitude.toStringAsFixed(5)}',
                      ),
                    if (gps && _selected!.recordedAt != null)
                      Text(
                        'Captured: ${_selected!.recordedAt!.toUtc().toIso8601String()}',
                      ),
                    if (selectedPosition == null)
                      const Text(
                        'No map position is available for this place. You can still view its information.',
                      ),
                    if (_selected!.isDemo)
                      const Text(
                        'TEST SCENARIO · Not current flood conditions',
                      ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: const Text('View information on Home'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text('Choose a place without using the map', style: titleStyle(22)),
            if (_loading) const Text('Loading places…'),
            if (_error != null) ...[
              Semantics(liveRegion: true, child: Text(_error!)),
              TextButton(onPressed: _load, child: const Text('Retry places')),
            ],
            if (_saved.isNotEmpty) ...[
              const Text('Saved places'),
              for (final saved in _saved)
                ListTile(
                  title: Text(saved.place.name),
                  subtitle: Text(
                    saved.isDefault ? 'Saved · default place' : 'Saved place',
                  ),
                  trailing: const Icon(Icons.bookmark_outline),
                  onTap: () => _select(saved.place),
                ),
            ],
            const Text('Supported neighbourhoods'),
            for (final place in _places)
              ListTile(
                title: Text(place.name),
                subtitle: Text(
                  place.isDemo
                      ? 'Sample assessment · approximate centre'
                      : 'Neighbourhood centre',
                ),
                selected: place.id == _selected?.id,
                onTap: () => _select(place),
              ),
            const SizedBox(height: 16),
            const Text(
              'Blue pins identify places, not flood-risk levels. Use Home for assessment sources and validity. The map requires an internet connection.',
            ),
          ],
        ),
      ),
    );
  }
}
