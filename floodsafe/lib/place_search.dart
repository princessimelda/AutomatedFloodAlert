import 'package:flutter/material.dart';

import 'dashboard/dashboard_data.dart';
import 'data/local_information_repository.dart';
import 'ui.dart';

class NairobiPlaceSearch extends StatefulWidget {
  const NairobiPlaceSearch({
    super.key,
    this.repository,
    required this.onSelected,
    this.onQueryChanged,
    this.label = 'Search places',
    this.fieldKey,
  });
  final PlaceSearchRepository? repository;
  final ValueChanged<Place> onSelected;
  final ValueChanged<String>? onQueryChanged;
  final String label;
  final Key? fieldKey;
  @override
  State<NairobiPlaceSearch> createState() => _NairobiPlaceSearchState();
}

class _NairobiPlaceSearchState extends State<NairobiPlaceSearch> {
  final _controller = TextEditingController();
  List<FoundPlace>? _results;
  bool _loading = false;
  String? _error;
  int _request = 0;

  void _change(String query) {
    _request++;
    setState(() {
      _results = null;
      _error = null;
      _loading = false;
    });
    widget.onQueryChanged?.call(query);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 3 || widget.repository == null || _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
    });
    try {
      final results = await widget.repository!
          .searchPlaces(query)
          .timeout(const Duration(seconds: 15));
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = 'Place search could not load. Check your connection and try Search again.';
      });
    }
  }

  @override
  void dispose() {
    _request++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: widget.fieldKey,
      controller: _controller,
      textInputAction: TextInputAction.search,
      maxLength: 120,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'Neighbourhood, road or landmark',
        counterText: '',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear place search',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  _change('');
                },
              ),
      ),
      onChanged: _change,
      onSubmitted: (_) => _search(),
    );
    final button = FilledButton.icon(
      onPressed: _loading || _controller.text.trim().length < 3
          ? null
          : _search,
      icon: const Icon(Icons.search),
      label: const Text('Search'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.repository == null)
          field
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          ),
        if (widget.repository != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Search the Nairobi area. Press Search or Enter.',
              style: TextStyle(color: muted),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(
              semanticsLabel: 'Searching Nairobi places',
            ),
          ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        if (_results != null) ...[
          if (_results!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No places found in the Nairobi area. Try another spelling or a nearby landmark.',
              ),
            ),
          for (final result in _results!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined, color: blue),
              title: Text(result.place.name),
              subtitle: Text(result.description),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _request++;
                setState(() {
                  _results = null;
                  _loading = false;
                  _controller.text = result.place.name;
                });
                widget.onSelected(result.place);
              },
            ),
          const Text(
            'Place names © OpenStreetMap contributors',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
