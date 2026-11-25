import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const blue = Color(0xFF087F8C);
const navy = Color(0xFF163B46);
const ink = Color(0xFF334155);
const muted = Color(0xFF52646D);
const paper = Color(0xFFF7F8F4);
const accent = Color(0xFFDCECE9);
const line = Color(0xFFD8E3DF);
const red = Color(0xFFB42336);
const green = Color(0xFF178567);

TextStyle titleStyle(double size) => TextStyle(
  fontFamily: 'Georgia Pro',
  fontFamilyFallback: const ['Georgia', 'Lora', 'serif'],
  fontSize: size,
  fontWeight: FontWeight.w700,
  color: navy,
  height: 1.15,
  letterSpacing: -.6,
);

class Brand extends StatelessWidget {
  const Brand({super.key, this.large = false, this.tagline = true});
  final bool large, tagline;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'FloodSafe',
    image: true,
    child: SizedBox(
      width: large ? 310 : 185,
      height: large ? 96 : 56,
      child: const CroppedAsset(
        asset: 'assets/images/floodsafe-brand.png',
        // Display the supplied mark without its surrounding blank canvas.
        source: Rect.fromLTRB(.055, .35, .985, .65),
      ),
    ),
  );
}

/// Crop only at paint time: retain the original supplied image unchanged.
class CroppedAsset extends StatefulWidget {
  const CroppedAsset({
    super.key,
    required this.asset,
    required this.source,
    this.fit = BoxFit.contain,
  });
  final String asset;
  final Rect source;
  final BoxFit fit;
  @override
  State<CroppedAsset> createState() => _CroppedAssetState();
}

class _CroppedAssetState extends State<CroppedAsset> {
  ui.Image? _image;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (mounted) {
        setState(() => _image = frame.image);
      } else {
        frame.image.dispose();
      }
    } catch (_) {
      /* Decorative assets must not block the app. */
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AssetPainter(_image, widget.source, widget.fit),
    size: Size.infinite,
  );
}

class _AssetPainter extends CustomPainter {
  _AssetPainter(this.image, this.crop, this.fit);
  final ui.Image? image;
  final Rect crop;
  final BoxFit fit;
  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) return;
    final source = Rect.fromLTRB(
      crop.left * image.width,
      crop.top * image.height,
      crop.right * image.width,
      crop.bottom * image.height,
    );
    final fitted = applyBoxFit(fit, source.size, size);
    canvas.drawImageRect(
      image,
      Alignment.center.inscribe(fitted.source, source),
      Alignment.center.inscribe(fitted.destination, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _AssetPainter old) =>
      image != old.image || crop != old.crop || fit != old.fit;
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'UI PROTOTYPE'});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: accent,
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
          color: Color(0x0C163B46),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
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
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: ClipRect(child: CustomPaint(painter: LandscapePainter())),
      ),
    ),
  );
}

class LandscapePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;
    final p = Paint();
    c.drawRect(Offset.zero & s, p..color = const Color(0xFFF0F6FF));
    c.drawCircle(
      Offset(w * .8, h * .22),
      math.min(w * .08, h * .17),
      p..color = const Color(0xFFFFE5AC),
    );
    // Quiet sky details stay behind the skyline and never carry information.
    for (final x in [.16, .44]) {
      final cloud = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(w * x, h * .22),
            width: w * .1,
            height: h * .05,
          ),
        )
        ..addOval(
          Rect.fromCenter(
            center: Offset(w * (x + .02), h * .19),
            width: w * .05,
            height: h * .08,
          ),
        );
      c.drawPath(cloud, p..color = Colors.white);
    }
    final random = math.Random(8);
    final count = (w / 38).round().clamp(8, 22);
    final slot = w / count;
    for (var i = 0; i < count; i++) {
      final x = slot * i;
      final bh = h * (.12 + random.nextDouble() * .23);
      final buildingWidth = slot * .74;
      final top = h * .65 - bh;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, buildingWidth, bh),
          const Radius.circular(2),
        ),
        p
          ..color = Color.lerp(
            const Color(0xFFD4E4F4),
            const Color(0xFFA9C8E6),
            random.nextDouble(),
          )!,
      );
      for (var floor = 0; floor < 3; floor++) {
        for (var column = 0; column < 2; column++) {
          c.drawRect(
            Rect.fromLTWH(
              x + buildingWidth * (.2 + column * .4),
              top + bh * (.18 + floor * .24),
              buildingWidth * .12,
              h * .018,
            ),
            p..color = const Color(0xFFECF4FC),
          );
        }
      }
    }
    // A simplified civic tower gives the city silhouette a local reference.
    final tower = Rect.fromLTWH(w * .61, h * .24, w * .065, h * .4);
    c.drawRRect(
      RRect.fromRectAndRadius(tower, Radius.circular(w * .02)),
      p..color = const Color(0xFF90B5D8),
    );
    for (var i = 1; i < 7; i++) {
      c.drawRect(
        Rect.fromLTWH(
          tower.left,
          tower.top + tower.height * i / 7,
          tower.width,
          h * .006,
        ),
        p..color = const Color(0xFFC9DDED),
      );
    }
    c.drawOval(
      Rect.fromCenter(
        center: Offset(tower.center.dx, tower.top),
        width: tower.width * 1.3,
        height: h * .045,
      ),
      p..color = const Color(0xFF739FC6),
    );
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
            const Color(0xFFCCE5E3),
            const Color(0xFF94C8CD),
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
    for (final x in [.1, .88]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * x, h * .72, w * .009, h * .12),
          const Radius.circular(2),
        ),
        p..color = const Color(0xFF2D648E),
      );
      c.drawOval(
        Rect.fromCenter(
          center: Offset(w * (x + .0045), h * .7),
          width: w * .075,
          height: h * .19,
        ),
        p..color = const Color(0xFF438F9B),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
