import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/board.dart';
import 'bom_widgets.dart';

const _boardColor = Color(0xFF1F5C45);
const _edgeColor = Color(0xFFE8D27A);
const _silkColor = Color(0xFFF2F2F2);
const _padColor = Color(0xFFC9A95B);
const _drillColor = Color(0xFF173F31);
const _hiColor = Color(0xFFFF5A1F);
const _doneColor = Color(0xFF4CD07D);

/// The PCB with [highlight] parts marked, like ibom's board view: zoom with
/// the scroll wheel or pinch, drag to pan, click a part to pick it.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.board,
    required this.highlight,
    required this.checked,
    this.onTapRef,
  });

  final BoardGeometry board;

  /// References to point at (the scanned or selected line).
  final Set<String> highlight;

  /// References whose line is checked off.
  final Set<String> checked;
  final ValueChanged<String>? onTapRef;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  final _zoom = TransformationController();
  String _side = 'F';

  @override
  void didUpdateWidget(BoardView old) {
    super.didUpdateWidget(old);
    // Flip to the side the highlighted parts are on.
    if (widget.highlight.isNotEmpty &&
        !_sameSet(widget.highlight, old.highlight)) {
      final sides = {
        for (final r in widget.highlight) widget.board.footprint(r)?.layer,
      }..remove(null);
      if (sides.length == 1 && !sides.contains(_side)) {
        setState(() => _side = sides.first!);
      }
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    final hasBack = board.hasSide('B');
    final theme = Theme.of(context);
    final missing = [
      for (final r in widget.highlight)
        if (board.footprint(r) == null) r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasBack)
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'F', label: Text('正面')),
                    ButtonSegment(value: 'B', label: Text('背面')),
                  ],
                  selected: {_side},
                  onSelectionChanged: (s) => setState(() => _side = s.first),
                ),
              _legend(_hiColor, '目前這顆料'),
              _legend(_doneColor, '已打勾'),
              TextButton.icon(
                onPressed: () => _zoom.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen, size: 18),
                label: const Text('重設縮放'),
              ),
              if (missing.isNotEmpty)
                Text(
                  '板子上找不到：${missing.join(', ')}',
                  style: const TextStyle(color: kOrange),
                ),
            ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final fit = _Fit(board, size, _side == 'B');
                return InteractiveViewer(
                  transformationController: _zoom,
                  minScale: 1,
                  maxScale: 12,
                  child: GestureDetector(
                    onTapUp: widget.onTapRef == null
                        ? null
                        : (d) {
                            final (x, y) = fit.toBoard(d.localPosition);
                            final f = board.footprintAt(x, y, _side);
                            if (f != null) widget.onTapRef!(f.ref);
                          },
                    child: CustomPaint(
                      size: size,
                      painter: _BoardPainter(
                        board: board,
                        fit: fit,
                        side: _side,
                        highlight: widget.highlight,
                        checked: widget.checked,
                        labelStyle: theme.textTheme.labelLarge!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(text),
    ],
  );
}

/// Board mm <-> widget pixels: the board fitted and centred, mirrored for
/// the back side.
class _Fit {
  _Fit(this.board, Size size, this.mirror) {
    const pad = 24.0;
    scale = math
        .min(
          (size.width - 2 * pad) / board.width,
          (size.height - 2 * pad) / board.height,
        )
        .clamp(0.01, double.infinity);
    ox = (size.width - board.width * scale) / 2;
    oy = (size.height - board.height * scale) / 2;
  }

  final BoardGeometry board;
  final bool mirror;
  late final double scale, ox, oy;

  Offset toScreen(double x, double y) => Offset(
    ox + (mirror ? board.maxX - x : x - board.minX) * scale,
    oy + (y - board.minY) * scale,
  );

  (double, double) toBoard(Offset p) => (
    mirror
        ? board.maxX - (p.dx - ox) / scale
        : board.minX + (p.dx - ox) / scale,
    board.minY + (p.dy - oy) / scale,
  );

  /// Puts the canvas in board mm.
  void apply(Canvas canvas) {
    canvas.translate(ox, oy);
    canvas.scale(scale);
    if (mirror) {
      canvas.translate(board.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.translate(-board.minX, -board.minY);
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.fit,
    required this.side,
    required this.highlight,
    required this.checked,
    required this.labelStyle,
  });

  final BoardGeometry board;
  final _Fit fit;
  final String side;
  final Set<String> highlight;
  final Set<String> checked;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    fit.apply(canvas);

    // Board body.
    final fill = Paint()..color = _boardColor;
    if (board.outline.isNotEmpty) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final o in board.outline) {
        path.addPath(_path(o), Offset.zero);
      }
      canvas.drawPath(path, fill);
    } else {
      canvas.drawRect(
        Rect.fromLTRB(board.minX, board.minY, board.maxX, board.maxY),
        fill,
      );
    }

    // Checked parts, under everything else.
    final done = Paint()..color = _doneColor.withValues(alpha: 0.45);
    for (final f in board.footprints) {
      if (f.layer == side && checked.contains(f.ref)) {
        canvas.drawPath(_box(f), done);
      }
    }

    // Silkscreen.
    for (final s in board.silk[side] ?? const <BoardShape>[]) {
      _stroke(canvas, s, _silkColor);
    }

    // Pads.
    final padPaint = Paint()..color = _padColor;
    final drillPaint = Paint()..color = _drillColor;
    for (final f in board.footprints) {
      for (final p in f.pads) {
        if (side == 'F' ? !p.front : !p.back) continue;
        _pad(canvas, p, padPaint, drillPaint);
      }
    }

    // Edge cuts on top.
    for (final e in board.edges) {
      _stroke(canvas, e, _edgeColor, minWidth: 0.2);
    }

    // The highlighted parts.
    final hiFill = Paint()..color = _hiColor.withValues(alpha: 0.75);
    final hiLine = Paint()
      ..color = _hiColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.25;
    final hiPad = Paint()..color = const Color(0xFFFFE0B2);
    for (final f in board.footprints) {
      if (f.layer != side || !highlight.contains(f.ref)) continue;
      canvas.drawPath(_box(f), hiFill);
      canvas.drawPath(_box(f), hiLine);
      for (final p in f.pads) {
        if (side == 'F' ? p.front : p.back) _pad(canvas, p, hiPad, null);
      }
    }
    canvas.restore();

    // Rings and labels in screen space so they stay readable.
    final ring = Paint()
      ..color = _hiColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    for (final f in board.footprints) {
      if (f.layer != side || !highlight.contains(f.ref)) continue;
      final (cx, cy) = f.center;
      final c = fit.toScreen(cx, cy);
      final r = math.max(
        16.0,
        math.sqrt(f.w * f.w + f.h * f.h) * fit.scale / 2 + 8,
      );
      canvas.drawCircle(c, r, halo);
      canvas.drawCircle(c, r, ring);
      _label(canvas, f.ref, c.translate(0, -r - 4));
    }
  }

  void _label(Canvas canvas, String text, Offset bottomCenter) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
      center: bottomCenter.translate(0, -tp.height / 2 - 3),
      width: tp.width + 12,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = _hiColor,
    );
    tp.paint(canvas, rect.topLeft + const Offset(6, 3));
  }

  Path _path(BoardShape s) {
    final p = s.points;
    final path = Path()..moveTo(p[0], p[1]);
    for (var i = 2; i + 1 < p.length; i += 2) {
      path.lineTo(p[i], p[i + 1]);
    }
    if (s.closed) path.close();
    return path;
  }

  void _stroke(
    Canvas canvas,
    BoardShape s,
    Color color, {
    double minWidth = 0,
  }) {
    if (s.points.length < 4) return;
    final paint = Paint()..color = color;
    if (s.filled) {
      canvas.drawPath(_path(s), paint);
    } else {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(s.width, minWidth)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_path(s), paint);
    }
  }

  Path _box(BoardFootprint f) {
    final c = f.corners;
    return Path()
      ..moveTo(c[0].$1, c[0].$2)
      ..lineTo(c[1].$1, c[1].$2)
      ..lineTo(c[2].$1, c[2].$2)
      ..lineTo(c[3].$1, c[3].$2)
      ..close();
  }

  void _pad(Canvas canvas, BoardPad p, Paint paint, Paint? drill) {
    canvas.save();
    canvas.translate(p.x, p.y);
    canvas.rotate(-p.angle * math.pi / 180);
    final rect = Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h);
    switch (p.shape) {
      case 'circle':
        canvas.drawCircle(Offset.zero, math.min(p.w, p.h) / 2, paint);
      case 'oval':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            Radius.circular(math.min(p.w, p.h) / 2),
          ),
          paint,
        );
      case 'roundrect':
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(p.radius)),
          paint,
        );
      default:
        canvas.drawRect(rect, paint);
    }
    if (drill != null && p.drillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.drillW,
            height: p.drillH,
          ),
          Radius.circular(math.min(p.drillW, p.drillH) / 2),
        ),
        drill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.board != board ||
      old.side != side ||
      old.fit.scale != fit.scale ||
      old.fit.ox != fit.ox ||
      !_sameSet(old.highlight, highlight) ||
      !_sameSet(old.checked, checked);
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
