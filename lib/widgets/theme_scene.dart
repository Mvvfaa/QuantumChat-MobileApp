import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/qc_theme.dart';

/// Atmospheric "3D" scenery behind chat — mirrors website fun-theme FX.
class ThemeScene extends StatelessWidget {
  const ThemeScene({
    super.key,
    required this.themeId,
    required this.child,
    this.intensity = 1,
    this.animate = true,
  });

  final QcThemeId themeId;
  final Widget child;
  final double intensity;
  /// Home inbox should keep this false — continuous animation skips frames on emulators.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!themeId.isFunTheme) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: animate
                  ? _AnimatedScene(themeId: themeId, intensity: intensity)
                  : CustomPaint(
                      painter: _ThemeScenePainter(
                        themeId: themeId,
                        t: 0.15,
                        stars: const [],
                        particles: const [],
                        intensity: intensity * 0.85,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _AnimatedScene extends StatefulWidget {
  const _AnimatedScene({required this.themeId, required this.intensity});
  final QcThemeId themeId;
  final double intensity;

  @override
  State<_AnimatedScene> createState() => _AnimatedSceneState();
}

class _AnimatedSceneState extends State<_AnimatedScene> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Star> _stars;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(widget.themeId.index * 97 + 13);
    _stars = List.generate(56, (i) => _Star.random(rng, i));
    _particles = List.generate(22, (i) => _Particle.random(rng, i));
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _ThemeScenePainter(
            themeId: widget.themeId,
            t: _ctrl.value,
            stars: _stars,
            particles: _particles,
            intensity: widget.intensity,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.bright,
  });

  final double x;
  final double y;
  final double size;
  final double phase;
  final bool bright;

  factory _Star.random(math.Random rng, int i) {
    return _Star(
      x: rng.nextDouble(),
      y: rng.nextDouble() * 0.55,
      size: rng.nextDouble() * 1.8 + (rng.nextBool() ? 1.4 : 0.6),
      phase: rng.nextDouble(),
      bright: rng.nextDouble() > 0.8,
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.drift,
  });

  final double x;
  final double y;
  final double size;
  final double phase;
  final double drift;

  factory _Particle.random(math.Random rng, int i) {
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: rng.nextDouble() * 6 + 4,
      phase: rng.nextDouble(),
      drift: rng.nextDouble() * 0.08 - 0.04,
    );
  }
}

class _ThemeScenePainter extends CustomPainter {
  _ThemeScenePainter({
    required this.themeId,
    required this.t,
    required this.stars,
    required this.particles,
    required this.intensity,
  });

  final QcThemeId themeId;
  final double t;
  final List<_Star> stars;
  final List<_Particle> particles;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    switch (themeId) {
      case QcThemeId.aurora:
        _paintAurora(canvas, size);
      case QcThemeId.moonveil:
        _paintMoonveil(canvas, size);
      case QcThemeId.sakura:
        _paintSakura(canvas, size);
      case QcThemeId.sunset:
        _paintSunset(canvas, size);
      case QcThemeId.ocean:
        _paintOcean(canvas, size);
      case QcThemeId.nebula:
        _paintNebula(canvas, size);
      case QcThemeId.dreamcloud:
        _paintDreamcloud(canvas, size);
      default:
        break;
    }
  }

  void _paintSky(Canvas canvas, Size size, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter}) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        begin.alongSize(size),
        end.alongSize(size),
        colors,
      );
    canvas.drawRect(rect, paint);
  }

  void _paintStars(Canvas canvas, Size size, {Color color = Colors.white}) {
    for (final s in stars) {
      final twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin((t + s.phase) * math.pi * 2));
      final p = Paint()
        ..color = color.withValues(alpha: (s.bright ? 0.95 : 0.55) * twinkle * intensity)
        ..maskFilter = s.bright ? const MaskFilter.blur(BlurStyle.normal, 1.2) : null;
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.size, p);
    }
  }

  void _paintGlow(Canvas canvas, Size size, Offset center, double radius, Color color, double alpha) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          color.withValues(alpha: alpha * intensity),
          color.withValues(alpha: 0),
        ],
      );
    canvas.drawCircle(center, radius, paint);
  }

  Path _treePath(Size size, double baseY) {
    // Simplified jagged pine silhouette across the width.
    final path = Path()..moveTo(0, size.height);
    path.lineTo(0, baseY + 8);
    final peaks = <double>[0.03, 0.08, 0.14, 0.22, 0.30, 0.40, 0.52, 0.62, 0.72, 0.82, 0.90, 0.97];
    for (final px in peaks) {
      final x = px * size.width;
      final h = 28 + (math.sin(px * 18) * 18).abs() + (px * 12);
      path.lineTo(x - 10, baseY);
      path.lineTo(x, baseY - h);
      path.lineTo(x + 12, baseY);
    }
    path
      ..lineTo(size.width, baseY + 6)
      ..lineTo(size.width, size.height)
      ..close();
    return path;
  }

  void _paintAurora(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFF050E14),
      Color(0xFF0A1F2C),
      Color(0xFF123342),
      Color(0xFF071420),
    ]);

    final drift = math.sin(t * math.pi * 2) * 18;
    _paintGlow(canvas, size, Offset(size.width * 0.25 + drift, size.height * 0.22), size.width * 0.45, const Color(0xFF2DD4BF), 0.28);
    _paintGlow(canvas, size, Offset(size.width * 0.72 - drift, size.height * 0.18), size.width * 0.4, const Color(0xFFA78BFA), 0.22);
    _paintGlow(canvas, size, Offset(size.width * 0.5, size.height * 0.28), size.width * 0.55, const Color(0xFF67E8F9), 0.12);

    // Soft aurora bands
    final band = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height * 0.12),
        Offset(size.width, size.height * 0.38),
        [
          const Color(0x002DD4BF),
          const Color(0x662DD4BF),
          const Color(0x44818CF8),
          const Color(0x002DD4BF),
        ],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.45, size.height * 0.24 + drift * 0.3), width: size.width * 1.1, height: size.height * 0.22), band);

    _paintStars(canvas, size);

    // Moon
    final moonCenter = Offset(size.width * 0.78, size.height * 0.14);
    _paintGlow(canvas, size, moonCenter, 42, const Color(0xFFCCFBF1), 0.35);
    canvas.drawCircle(moonCenter, 16, Paint()..color = const Color(0xFFE8FFFB).withValues(alpha: 0.92));

    final shoreline = size.height * 0.62;
    // Water
    final waterRect = Rect.fromLTRB(0, shoreline, size.width, size.height);
    canvas.drawRect(
      waterRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shoreline),
          Offset(0, size.height),
          const [
            Color(0x66123442),
            Color(0xCC050E14),
            Color(0xFF02080C),
          ],
        ),
    );
    // Water glow reflection
    _paintGlow(canvas, size, Offset(size.width * 0.4, shoreline + 36), size.width * 0.5, const Color(0xFF2DD4BF), 0.16);
    _paintGlow(canvas, size, Offset(size.width * 0.7, shoreline + 28), size.width * 0.35, const Color(0xFFA78BFA), 0.12);

    // Trees + reflection
    final trees = _treePath(size, shoreline);
    canvas.drawPath(trees, Paint()..color = const Color(0xFF02080C));
    canvas.save();
    canvas.translate(0, shoreline * 2 + 8);
    canvas.scale(1, -0.55);
    canvas.drawPath(trees, Paint()..color = const Color(0x6602080C));
    canvas.restore();

    // Soft water fade
    canvas.drawRect(
      waterRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shoreline),
          Offset(0, size.height),
          [
            Colors.transparent,
            const Color(0x9902080C),
          ],
        ),
    );
  }

  void _paintMoonveil(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFF14122A),
      Color(0xFF1C1A3A),
      Color(0xFF262347),
    ]);
    _paintGlow(canvas, size, Offset(size.width * 0.75, size.height * 0.16), 70, const Color(0xFFC4B5FD), 0.35);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.16), 28, Paint()..color = const Color(0xFFEDE9FE).withValues(alpha: 0.9));
    _paintGlow(canvas, size, Offset(size.width * 0.2, size.height * 0.7), size.width * 0.4, const Color(0xFF8B5CF6), 0.18);
    _paintStars(canvas, size, color: const Color(0xFFE9D5FF));
  }

  void _paintSakura(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFFFFF5F7),
      Color(0xFFFFE4EA),
      Color(0xFFFFF8F9),
    ]);
    _paintGlow(canvas, size, Offset(size.width * 0.85, size.height * 0.12), 90, const Color(0xFFF9A8D4), 0.35);
    _paintGlow(canvas, size, Offset(size.width * 0.15, size.height * 0.75), 100, const Color(0xFFF472B6), 0.18);
    for (final p in particles) {
      final y = ((p.y + t * 0.35 + p.phase) % 1.15) - 0.1;
      final x = (p.x + p.drift * math.sin((t + p.phase) * math.pi * 2)) * size.width;
      final petal = Paint()..color = Color.lerp(const Color(0xFFFFD9E6), const Color(0xFFF472B6), p.phase)!.withValues(alpha: 0.7 * intensity);
      canvas.save();
      canvas.translate(x, y * size.height);
      canvas.rotate((t + p.phase) * math.pi * 2);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), petal);
      canvas.restore();
    }
  }

  void _paintSunset(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFF1A0E12),
      Color(0xFF4A1D1A),
      Color(0xFF8A2B3C),
      Color(0xFFE2792A),
      Color(0xFF1E1114),
    ], begin: Alignment.topCenter, end: Alignment.bottomCenter);
    _paintGlow(canvas, size, Offset(size.width * 0.5, size.height * 0.18), size.width * 0.5, const Color(0xFFFFD88A), 0.35);
    _paintGlow(canvas, size, Offset(size.width * 0.2, size.height * 0.55), size.width * 0.35, const Color(0xFFEA580C), 0.2);
    for (final p in particles) {
      final y = 1 - ((p.y + t * 0.25 + p.phase) % 1.0);
      final x = (p.x + p.drift) * size.width;
      canvas.drawCircle(
        Offset(x, y * size.height * 0.7),
        p.size * 0.35,
        Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.55 * intensity),
      );
    }
    final ground = size.height * 0.72;
    canvas.drawPath(_treePath(size, ground), Paint()..color = const Color(0xFF0A0405));
  }

  void _paintOcean(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFF02100F),
      Color(0xFF031917),
      Color(0xFF052220),
      Color(0xFF021513),
    ]);
    _paintGlow(canvas, size, Offset(size.width * 0.5, 0), size.width * 0.7, const Color(0xFF22D3EE), 0.18);
    _paintGlow(canvas, size, Offset(size.width * 0.3, size.height * 0.55), size.width * 0.4, const Color(0xFF0891B2), 0.2);
    for (final p in particles) {
      final y = 1 - ((p.y + t * 0.2 + p.phase) % 1.05);
      final x = (p.x + math.sin((t + p.phase) * math.pi * 2) * p.drift) * size.width;
      canvas.drawCircle(
        Offset(x, y * size.height),
        p.size * 0.28,
        Paint()
          ..color = const Color(0xFF99F6E4).withValues(alpha: 0.45 * intensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _paintNebula(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFF0A0518),
      Color(0xFF120A24),
      Color(0xFF1C1036),
    ]);
    _paintGlow(canvas, size, Offset(size.width * 0.5, size.height * 0.42), size.width * 0.38, const Color(0xFFD946EF), 0.32);
    _paintGlow(canvas, size, Offset(size.width * 0.28, size.height * 0.3), size.width * 0.35, const Color(0xFF7C3AED), 0.22);
    _paintGlow(canvas, size, Offset(size.width * 0.72, size.height * 0.55), size.width * 0.32, const Color(0xFF60A5FA), 0.2);
    _paintStars(canvas, size, color: const Color(0xFFF5D0FE));
  }

  void _paintDreamcloud(Canvas canvas, Size size) {
    _paintSky(canvas, size, const [
      Color(0xFFFDF3FB),
      Color(0xFFFBE7F7),
      Color(0xFFFEF7FD),
    ]);
    _paintGlow(canvas, size, Offset(size.width * 0.2, size.height * 0.2), 100, const Color(0xFFF9A8D4), 0.3);
    _paintGlow(canvas, size, Offset(size.width * 0.8, size.height * 0.35), 120, const Color(0xFFD8B4FE), 0.28);
    for (final p in particles) {
      final x = ((p.x + t * 0.08 * (p.drift >= 0 ? 1 : -1) + p.phase) % 1.2) - 0.1;
      final y = p.y * size.height * 0.7;
      final cloud = Paint()..color = Colors.white.withValues(alpha: 0.55 * intensity);
      final cx = x * size.width;
      canvas.drawCircle(Offset(cx, y), p.size * 1.4, cloud);
      canvas.drawCircle(Offset(cx + p.size, y + 2), p.size * 1.1, cloud);
      canvas.drawCircle(Offset(cx - p.size * 0.8, y + 3), p.size, cloud);
    }
  }

  @override
  bool shouldRepaint(covariant _ThemeScenePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.themeId != themeId;
  }
}

/// Glass-style bubble decoration used when a fun theme is active.
BoxDecoration glassBubbleDecoration({
  required bool mine,
  required QcColors colors,
  required bool scenic,
}) {
  if (!scenic) {
    return BoxDecoration(
      color: mine ? colors.bubbleMine : colors.bubbleTheirs,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(mine ? 18 : 5),
        bottomRight: Radius.circular(mine ? 5 : 18),
      ),
    );
  }

  return BoxDecoration(
    color: (mine ? colors.bubbleMine : colors.bubbleTheirs).withValues(alpha: mine ? 0.88 : 0.62),
    borderRadius: BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine ? 18 : 5),
      bottomRight: Radius.circular(mine ? 5 : 18),
    ),
    border: Border.all(
      color: (mine ? colors.accentCyan : colors.accent).withValues(alpha: 0.22),
    ),
    boxShadow: [
      BoxShadow(
        color: (mine ? colors.accent : colors.accentCyan).withValues(alpha: 0.22),
        blurRadius: 16,
        spreadRadius: 0.5,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: colors.isDark ? 0.28 : 0.08),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
