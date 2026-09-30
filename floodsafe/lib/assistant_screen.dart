import 'package:flutter/material.dart';

import 'ui.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<({bool user, String text})> _messages = [];
  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? prompt]) {
    final text = (prompt ?? _input.text).trim();
    if (text.isEmpty) return;
    final q = text.toLowerCase();
    final response = q.contains('route') || q.contains('safe')
        ? 'The Home tab includes an illustrative route preview. It shows how route guidance could look, but it is not a verified safe route. Live routing will be added later.'
        : q.contains('risk') || q.contains('flood')
        ? 'On the Home tab, you can explore sample high, moderate, and low risk layers around Nairobi. These are demonstration areas, not current flood predictions. The research model is still being developed.'
        : q.contains('news') || q.contains('update')
        ? 'Open Flood News to preview weather alerts, river-level updates, and safety articles. Every story in this prototype is sample content; live sources will be connected later.'
        : 'Thanks for trying FloodSafe. This is a scripted preview, so I cannot answer live questions yet. Try asking about the risk map, news, or the demo route.';
    setState(
      () => _messages.addAll([
        (user: true, text: text),
        (user: false, text: response),
      ]),
    );
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DemoBadge(label: 'SCRIPTED PREVIEW · NO LIVE AI'),
                const SizedBox(height: 14),
                Text(
                  'A helping hand,\nwhen you need it.',
                  style: titleStyle(32),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A preview of your FloodSafe assistant.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(24),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Surface(
                    color: Color(0xFFEAF2FF),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: blue),
                        SizedBox(height: 12),
                        Text(
                          'Hello, Nairobi 👋',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'I’m your FloodSafe demo assistant. Explore how the app could help you understand local risk and find useful updates.',
                          style: TextStyle(color: navy, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            'Explain the risk map',
                            'Show me flood news',
                            'How do routes work?',
                          ]
                          .map(
                            (q) => ActionChip(
                              label: Text(
                                q,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: blue,
                                ),
                              ),
                              onPressed: () => _send(q),
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: line),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 22),
                ..._messages.map(
                  (m) => Align(
                    alignment: m.user
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(17),
                      constraints: const BoxConstraints(maxWidth: 570),
                      decoration: BoxDecoration(
                        color: m.user ? blue : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: m.user ? null : Border.all(color: line),
                      ),
                      child: Text(
                        m.text,
                        style: TextStyle(
                          color: m.user ? Colors.white : ink,
                          height: 1.6,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('assistant-input'),
                    controller: _input,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Ask about the demo…',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: () => _send(),
                  tooltip: 'Send message',
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
