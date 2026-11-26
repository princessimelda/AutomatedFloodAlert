import 'dart:async';

import 'package:flutter/material.dart';

import 'dashboard/dashboard_data.dart';
import 'data/local_information_repository.dart';
import 'maps/map_locations.dart';
import 'ui.dart';

class RainfallPanel extends StatefulWidget {
  const RainfallPanel({
    super.key,
    required this.place,
    required this.repository,
  });
  final Place place;
  final WeatherRepository repository;
  @override
  State<RainfallPanel> createState() => _RainfallPanelState();
}

class _RainfallPanelState extends State<RainfallPanel> {
  RainfallEstimate? _estimate;
  bool _loading = true;
  String? _error;
  int _request = 0;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RainfallPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.place.id != widget.place.id ||
        oldWidget.place.latitude != widget.place.latitude ||
        oldWidget.place.longitude != widget.place.longitude ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    _expiry?.cancel();
    setState(() {
      _estimate = null;
      _loading = true;
      _error = null;
    });
    final position = mapPosition(widget.place);
    try {
      if (position == null) throw StateError('No location');
      final estimate = await widget.repository
          .rainfall(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 15));
      if (!mounted || request != _request) return;
      if (!estimate.current(DateTime.now().toUtc())) {
        throw StateError('Expired weather');
      }
      setState(() {
        _estimate = estimate;
        _loading = false;
      });
      _expiry = Timer(
        estimate.validUntil.difference(DateTime.now().toUtc()),
        () {
          if (mounted) _load();
        },
      );
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Rainfall information could not be loaded. Try again.';
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _expiry?.cancel();
    super.dispose();
  }

  String _time(DateTime value) {
    final eastAfrica = value.toUtc().add(const Duration(hours: 3));
    return '${eastAfrica.day}/${eastAfrica.month} ${eastAfrica.hour.toString().padLeft(2, '0')}:${eastAfrica.minute.toString().padLeft(2, '0')} EAT';
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rainfall · ${widget.place.name}', style: titleStyle(22)),
        const SizedBox(height: 10),
        if (_loading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading rainfall information',
          ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (estimate != null) ...[
          Text(
            '${estimate.rainMm.toStringAsFixed(1)} mm',
            style: titleStyle(30),
          ),
          Text(
            'Estimated rainfall over the last ${estimate.intervalMinutes} minutes',
          ),
          const SizedBox(height: 12),
          Text(
            '${estimate.forecastRainMm.toStringAsFixed(1)} mm · 24-hour rainfall forecast',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${_time(estimate.forecastStart)} – ${_time(estimate.forecastEnd)}',
          ),
          const SizedBox(height: 10),
          Text(
            'Source: Open-Meteo · Weather estimate for ${_time(estimate.validAt)}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rainfall estimates help you prepare; they do not confirm flooding or that roads are safe.',
          ),
        ],
        TextButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh rainfall'),
        ),
      ],
    );
  }
}
