import 'dart:math' as math;

import 'package:flutter/material.dart';

const blue = Color(0xFF125DD8);
const navy = Color(0xFF123D70);
const ink = Color(0xFF152C46);
const muted = Color(0xFF697C91);
const paper = Color(0xFFF5F8FD);
const line = Color(0xFFE0E8F2);
const red = Color(0xFFD83C4C);
const green = Color(0xFF178567);

TextStyle titleStyle(double size) => TextStyle(
  fontFamily: 'Lora',
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: ink,
  height: 1.15,
  letterSpacing: -.6,
);

class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false, this.tagline = true});
  final bool large, tagline;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: large ? 310 : 185),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: large ? 64 : 43,
            height: large ? 70 : 48,
            child: CustomPaint(painter: BrandPainter()),
          ),
          SizedBox(width: large ? 14 : 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FloodSafe',
                style: titleStyle(large ? 36 : 25).copyWith(color: navy),
              ),
              if (tagline)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Stay informed. Stay safe.',
                    style: TextStyle(fontSize: large ? 13 : 10, color: muted),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 70);
    final drop = Path()
      ..moveTo(34, 1)
      ..cubicTo(29, 1, 13, 26, 13, 34)
      ..cubicTo(13, 51, 52, 51, 52, 34)
      ..cubicTo(52, 25, 38, 1, 34, 1);
    canvas.drawPath(
      drop,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF338DFF), blue])
            .createShader(const Rect.fromLTWH(10, 0, 45, 50)),
    );
    canvas.drawPath(
      Path()
        ..moveTo(23, 35)
        ..lineTo(30, 40)
        ..lineTo(42, 22),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5,
    );
    for (var i = 0; i < 2; i++) {
      final y = 47.0 + i * 12;
      canvas.drawPath(
        Path()
          ..moveTo(0, y + 9)
          ..cubicTo(21, y - 17, 37, y + 20, 64, y - 5)
          ..cubicTo(51, y + 28, 23, y - 2, 0, y + 9),
        Paint()..color = i == 0 ? navy : const Color(0xFF5AA8EA),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'UI PROTOTYPE'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFECF3FF),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: blue,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x060E3F77),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: titleStyle(23))),
      ?trailing,
    ],
  );
}

void showInfo(
  BuildContext context,
  String title,
  String message, {
  IconData icon = Icons.info_outline,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(icon, color: blue, size: 34),
      title: Text(title, style: titleStyle(25), textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Text(message, style: const TextStyle(color: muted, height: 1.6)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class Landscape extends StatelessWidget {
  const Landscape({super.key, this.height = 220});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: LandscapePainter()),
  );
}

class LandscapePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final p = Paint();
    c.drawCircle(
      Offset(w * .78, h * .25),
      h * .19,
      p..color = const Color(0xFFE5F0FC),
    );
    final random = math.Random(8);
    for (var i = 0; i < 30; i++) {
      final x = w * i / 30;
      final bh = h * (.08 + random.nextDouble() * .28);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, h * .66 - bh, w / 36, bh),
          const Radius.circular(2),
        ),
        p
          ..color = Color.lerp(
            const Color(0xFFDBEAF8),
            const Color(0xFFB6D3ED),
            random.nextDouble(),
          )!,
      );
      if (i % 6 == 0) {
        c.drawRect(Rect.fromLTWH(x + w / 80, h * .66 - bh - 12, 3, 12), p);
      }
    }
    for (var i = 0; i < 3; i++) {
      final y = h * (.52 + i * .16);
      final path = Path()
        ..moveTo(0, y)
        ..cubicTo(w * .3, y - h * .25, w * .55, y + h * .35, w, y - h * .05)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      c.drawPath(
        path,
        p
          ..color = [
            const Color(0xFFCCE1F8),
            const Color(0xFF92C1EE),
            const Color(0xFF3E86CE),
          ][i],
      );
    }
    final river = Path()
      ..moveTo(w * .77, h * .73)
      ..cubicTo(w * .58, h * .8, w * .27, h * .81, w * .42, h)
      ..lineTo(w * .78, h)
      ..cubicTo(w * .34, h * .91, w * .78, h * .8, w * .8, h * .73)
      ..close();
    c.drawPath(river, p..color = const Color(0xFFDAEDFE));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
