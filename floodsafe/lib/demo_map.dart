import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui.dart';

class DemoMap extends StatefulWidget {
  const DemoMap({
    super.key,
    required this.location,
    required this.showLocation,
    required this.route,
    this.height = 430,
  });
  final String location;
  final bool showLocation, route;
  final double height;
  @override
  State<DemoMap> createState() => _DemoMapState();
}

class _DemoMapState extends State<DemoMap> {
  final _transform = TransformationController();
  bool _risk = true;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 3.0);
    _transform.value = Matrix4.identity()..scaleByDouble(next, next, 1, 1);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (_, constraints) => InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 3,
                child: Semantics(
                  label: 'Illustrative Nairobi map. Sample flood risk areas, not live geographic data.',
                  image: true,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: NairobiMapPainter(
                      risk: _risk,
                      route: widget.route,
                      showLocation: widget.showLocation,
                      location: widget.location,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: 15,
            left: 15,
            child: DemoBadge(label: 'ILLUSTRATIVE MAP'),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: Column(
              children: [
                _control(
                  Icons.layers_outlined,
                  'Toggle sample risk layers',
                  () => setState(() => _risk = !_risk),
                  active: _risk,
                ),
                const SizedBox(height: 9),
                _control(
                  Icons.my_location_rounded,
                  'Recenter map',
                  () => _transform.value = Matrix4.identity(),
                ),
                const SizedBox(height: 9),
                _control(Icons.add, 'Zoom in', () => _zoom(1.25)),
                const SizedBox(height: 5),
                _control(Icons.remove, 'Zoom out', () => _zoom(.8)),
              ],
            ),
          ),
          Positioned(
            left: 14,
            bottom: 28,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x10000000), blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MAP LEGEND',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 7),
                  _legend(const Color(0xFFF29D9F), 'High risk'),
                  _legend(const Color(0xFFF7D8AD), 'Moderate risk'),
                  _legend(const Color(0xFFB6D9F8), 'Low risk'),
                  if (widget.route) _legend(green, 'Demo route'),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 6,
            right: 12,
            child: Text(
              'FloodSafe illustration · Not for navigation',
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _control(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: const Color(0x20000000),
    borderRadius: BorderRadius.circular(13),
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, color: active ? blue : navy, size: 22),
    ),
  );
  Widget _legend(Color color, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 10, color: ink)),
      ],
    ),
  );
}

class NairobiMapPainter extends CustomPainter {
  NairobiMapPainter({
    required this.risk,
    required this.route,
    required this.showLocation,
    required this.location,
  });
  final bool risk, route, showLocation;
  final String location;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEDF0EB),
    );
    final rng = math.Random(44);
    for (var i = 0; i < 100; i++) {
      final x = rng.nextDouble() * w, y = rng.nextDouble() * h;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            y,
            15 + rng.nextDouble() * 45,
            12 + rng.nextDouble() * 25,
          ),
          const Radius.circular(3),
        ),
        Paint()
          ..color = i % 4 == 0
              ? const Color(0xFFD9E5D4)
              : const Color(0xFFE1E5DF),
      );
    }
    final park = Path()
      ..moveTo(w * .51, 0)
      ..lineTo(w * .82, 0)
      ..lineTo(w * .75, h * .28)
      ..lineTo(w * .6, h * .33)
      ..close();
    canvas.drawPath(park, Paint()..color = const Color(0xFFD4E5CF));
    for (var i = -6; i < 18; i++) {
      final x = i * w / 12;
      canvas.drawLine(
        Offset(x, -10),
        Offset(x + w * .45, h + 10),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 5,
      );
      canvas.drawLine(
        Offset(-10, i * h / 12),
        Offset(w + 10, i * h / 12 - h * .32),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 4,
      );
    }
    final road = Path()
      ..moveTo(w * .82, -20)
      ..cubicTo(w * .7, h * .4, w * .73, h * .58, w * 1.1, h);
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFFD9D4C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15,
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFFFFF6DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10,
    );
    final cross = Path()
      ..moveTo(-20, h * .72)
      ..cubicTo(w * .4, h * .56, w * .5, h * .37, w + 20, h * .29);
    canvas.drawPath(
      cross,
      Paint()
        ..color = const Color(0xFFD6D9D3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13,
    );
    canvas.drawPath(
      cross,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    final river = Path()
      ..moveTo(w * .2, -20)
      ..cubicTo(w * .21, h * .18, w * .44, h * .3, w * .4, h * .46)
      ..cubicTo(w * .36, h * .73, w * .67, h * .65, w * .69, h + 20);
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFC2DEF1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 40,
    );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFF8ABFE0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15,
    );
    if (risk) {
      final high = Path()
        ..moveTo(0, h * .23)
        ..cubicTo(w * .12, h * .3, w * .15, h * .49, w * .25, h * .6)
        ..cubicTo(w * .26, h * .75, w * .05, h * .6, 0, h * .56)
        ..close();
      canvas.drawPath(high, Paint()..color = const Color(0xA9F0999B));
      canvas.drawPath(
        high,
        Paint()
          ..color = const Color(0xFFD78388)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final moderate = Path()
        ..moveTo(w * .7, h * .4)
        ..cubicTo(w * .86, h * .35, w * .86, h * .6, w, h * .63)
        ..lineTo(w, h * .97)
        ..cubicTo(w * .72, h * .86, w * .61, h * .67, w * .7, h * .4)
        ..close();
      canvas.drawPath(moderate, Paint()..color = const Color(0xABF5D0A2));
      canvas.drawOval(
        Rect.fromLTWH(w * .74, h * .5, w * .16, h * .48),
        Paint()..color = const Color(0xA9F0999B),
      );
    }
    _label(canvas, 'NAIROBI', Offset(w * .48, h * .08), 11, muted, spacing: 3);
    _label(canvas, 'Kibera', Offset(w * .14, h * .35), 14, ink);
    _label(canvas, 'Laini Saba', Offset(w * .57, h * .29), 13, ink);
    _label(
      canvas,
      'Nairobi River',
      Offset(w * .30, h * .21),
      12,
      const Color(0xFF347BA7),
    );
    _label(canvas, 'Ngong Road', Offset(w * .76, h * .83), 11, muted);
    _label(canvas, 'Woodley', Offset(w * .45, h * .88), 12, muted);
    Offset point = switch (location) {
      'Westlands' => Offset(w * .31, h * .25),
      'Embakasi' => Offset(w * .68, h * .49),
      'Kasarani' => Offset(w * .57, h * .25),
      _ => Offset(w * .43, h * .5),
    };
    if (route) {
      final path = Path()
        ..moveTo(point.dx, point.dy)
        ..lineTo(w * .51, h * .6)
        ..lineTo(w * .58, h * .6)
        ..lineTo(w * .65, h * .73);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeJoin = StrokeJoin.round,
      );
      for (final metric in path.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 16) {
          canvas.drawPath(
            metric.extractPath(d, math.min(d + 9, metric.length)),
            Paint()
              ..color = green
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..strokeCap = StrokeCap.round,
          );
        }
      }
      canvas.drawCircle(
        Offset(w * .65, h * .73),
        17,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(Offset(w * .65, h * .73), 14, Paint()..color = green);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.home_rounded.codePoint),
          style: TextStyle(
            fontFamily: Icons.home_rounded.fontFamily,
            fontSize: 19,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w * .65 - 9, h * .73 - 10));
      _pill(
        canvas,
        'Demo assembly point',
        Offset(w * .65, h * .73 + 27),
        green,
      );
    }
    if (showLocation) {
      canvas.drawCircle(
        point,
        30,
        Paint()..color = blue.withValues(alpha: .12),
      );
      canvas.drawCircle(point, 13, Paint()..color = Colors.white);
      canvas.drawCircle(point, 9, Paint()..color = blue);
      _pill(canvas, '$location · demo', Offset(point.dx, point.dy - 36), blue);
    }
    canvas.restore();
  }

  void _label(
    Canvas c,
    String text,
    Offset point,
    double size,
    Color color, {
    double spacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: spacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, point);
  }

  void _pill(Canvas c, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 20,
      height: 27,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = color,
    );
    tp.paint(c, Offset(rect.left + 10, rect.top + 7));
  }

  @override
  bool shouldRepaint(covariant NairobiMapPainter old) =>
      risk != old.risk ||
      route != old.route ||
      showLocation != old.showLocation ||
      location != old.location;
}
