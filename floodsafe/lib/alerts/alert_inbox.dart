import 'dart:async';

import 'package:flutter/material.dart';

import '../ui.dart';
import 'alert_repository.dart';

class AlertInbox extends StatefulWidget {
  const AlertInbox({
    super.key,
    required this.repository,
    required this.onSignIn,
    this.accountId,
    this.placeId,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final AlertRepository repository;
  final VoidCallback onSignIn;
  final String? accountId, placeId;
  final DateTime Function() clock;

  @override
  State<AlertInbox> createState() => _AlertInboxState();
}

class _AlertInboxState extends State<AlertInbox> {
  List<PublicAlert> _alerts = [];
  final Set<String> _acknowledged = {};
  final Set<String> _pending = {};
  bool _loading = true, _failed = false;
  String? _actionError;
  Timer? _poll, _expiry;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant AlertInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.placeId != widget.placeId) {
      _acknowledged.clear();
      _pending.clear();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final request = ++_request;
    _expiry?.cancel();
    setState(() {
      _loading = true;
      _failed = false;
      _alerts = [];
    });
    try {
      final alerts = await widget.repository
          .alerts(placeId: widget.placeId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || request != _request) return;
      setState(() {
        _alerts = alerts
            .where((a) => a.current(widget.clock().toUtc()))
            .toList();
        _loading = false;
      });
      _scheduleExpiry();
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    if (_alerts.isEmpty) return;
    final next = _alerts
        .map((a) => a.validUntil)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final remaining = next.difference(widget.clock().toUtc());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted) return;
      setState(
        () => _alerts.removeWhere((a) => !a.current(widget.clock().toUtc())),
      );
      _scheduleExpiry();
    });
  }

  Future<void> _acknowledge(PublicAlert alert) async {
    if (_pending.contains(alert.id)) return;
    final owner = widget.accountId;
    setState(() {
      _pending.add(alert.id);
      _actionError = null;
    });
    try {
      await widget.repository.acknowledge(alert.id);
      if (!mounted || owner != widget.accountId) return;
      setState(() => _acknowledged.add(alert.id));
    } catch (_) {
      if (!mounted || owner != widget.accountId) return;
      setState(
        () => _actionError = 'Could not record acknowledgement. Check your connection and try again.',
      );
    } finally {
      if (mounted && owner == widget.accountId) {
        setState(() => _pending.remove(alert.id));
      }
    }
  }

  @override
  void dispose() {
    _request++;
    _poll?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  String _time(DateTime time) =>
      '${time.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC';

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Semantics(
        header: true,
        child: Text('Alert inbox', style: titleStyle(28)),
      ),
      const SizedBox(height: 12),
      const Text(
        'Student prototype · TEST ALERTS ONLY. Alerts are reviewed before publication. This inbox updates while it is open.',
      ),
      const SizedBox(height: 8),
      const Text(
        'SMS reaches enrolled test phones without internet, but requires mobile network coverage. Acknowledging an alert records that you read it; it does not confirm that an area is safe.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _loading ? null : _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh alerts'),
      ),
      if (_loading)
        const LinearProgressIndicator(semanticsLabel: 'Loading alerts'),
      if (_failed)
        Semantics(
          liveRegion: true,
          child: const Text(
            'Alerts could not be loaded. Refresh to try again. Unavailable information does not mean no flood risk.',
          ),
        ),
      if (!_loading && !_failed && _alerts.isEmpty)
        Semantics(
          liveRegion: true,
          child: const Text(
            'No current published test alerts. Continue checking official local information.',
          ),
        ),
      if (_actionError != null)
        Semantics(liveRegion: true, child: Text(_actionError!)),
      ..._alerts.map(
        (alert) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'TEST · ${alert.severity.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Text(alert.title, style: titleStyle(22)),
                const SizedBox(height: 8),
                Text('Area: ${alert.locations.join(', ')}'),
                Text('Issued: ${_time(alert.issuedAt)}'),
                Text('Expires: ${_time(alert.validUntil)}'),
                Text('Reference: ${alert.id.substring(0, 8)}'),
                const SizedBox(height: 12),
                Text(alert.message),
                const SizedBox(height: 12),
                Text(
                  'What to do: ${alert.action}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (widget.accountId == null)
                  TextButton(
                    onPressed: widget.onSignIn,
                    child: const Text('Sign in to acknowledge'),
                  )
                else
                  FilledButton(
                    onPressed:
                        _acknowledged.contains(alert.id) ||
                            _pending.contains(alert.id)
                        ? null
                        : () => _acknowledge(alert),
                    child: Text(
                      _acknowledged.contains(alert.id)
                          ? 'Acknowledged'
                          : _pending.contains(alert.id)
                          ? 'Recording…'
                          : 'I have read this alert',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
