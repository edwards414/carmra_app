import 'dart:math' as math;

/// The parts of an ibom `pcbdata` the board view draws: outline, silkscreen
/// and footprints, in mm (KiCad coordinates, y down).
class BoardGeometry {
  BoardGeometry({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.outline,
    required this.edges,
    required this.silk,
    required this.footprints,
  });

  final double minX, minY, maxX, maxY;

  /// Closed board outlines (edge cuts chained into loops), for the fill.
  final List<BoardShape> outline;

  /// Edge cuts as drawn.
  final List<BoardShape> edges;

  /// Silkscreen per side, `F` and `B`.
  final Map<String, List<BoardShape>> silk;
  final List<BoardFootprint> footprints;

  double get width => maxX - minX;
  double get height => maxY - minY;

  bool hasSide(String side) =>
      footprints.any((f) => f.layer == side) ||
      (silk[side]?.isNotEmpty ?? false);

  BoardFootprint? footprint(String ref) {
    for (final f in footprints) {
      if (f.ref == ref) return f;
    }
    return null;
  }

  /// The smallest footprint on [side] whose box contains the point (mm).
  BoardFootprint? footprintAt(double x, double y, String side) {
    BoardFootprint? best;
    for (final f in footprints) {
      if (f.layer != side || !f.contains(x, y)) continue;
      if (best == null || f.w * f.h < best.w * best.h) best = f;
    }
    return best;
  }

  factory BoardGeometry.fromJson(Map<String, dynamic> j) => BoardGeometry(
    minX: _d(j['minX']),
    minY: _d(j['minY']),
    maxX: _d(j['maxX']),
    maxY: _d(j['maxY']),
    outline: _shapes(j['outline']),
    edges: _shapes(j['edges']),
    silk: {
      for (final e in (j['silk'] as Map<String, dynamic>).entries)
        e.key: _shapes(e.value),
    },
    footprints: [
      for (final f in j['footprints'] as List)
        BoardFootprint.fromJson(f as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'minX': minX,
    'minY': minY,
    'maxX': maxX,
    'maxY': maxY,
    'outline': [for (final s in outline) s.toJson()],
    'edges': [for (final s in edges) s.toJson()],
    'silk': {
      for (final e in silk.entries)
        e.key: [for (final s in e.value) s.toJson()],
    },
    'footprints': [for (final f in footprints) f.toJson()],
  };
}

/// A polyline, or a polygon when [closed].
class BoardShape {
  const BoardShape(
    this.points, {
    this.closed = false,
    this.filled = false,
    this.width = 0.15,
  });

  /// x0, y0, x1, y1, ...
  final List<double> points;
  final bool closed;
  final bool filled;
  final double width;

  factory BoardShape.fromJson(Map<String, dynamic> j) => BoardShape(
    [for (final v in j['p'] as List) _d(v)],
    closed: j['c'] == true,
    filled: j['f'] == true,
    width: _d(j['w'] ?? 0.15),
  );

  Map<String, dynamic> toJson() => {
    'p': [for (final v in points) _round(v)],
    if (closed) 'c': true,
    if (filled) 'f': true,
    'w': _round(width),
  };
}

class BoardPad {
  const BoardPad({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.angle,
    required this.shape,
    required this.radius,
    required this.front,
    required this.back,
    this.drillW = 0,
    this.drillH = 0,
  });

  final double x, y, w, h, angle;

  /// rect, roundrect, oval, circle (others are drawn as rect).
  final String shape;
  final double radius;
  final bool front, back;
  final double drillW, drillH;

  factory BoardPad.fromJson(Map<String, dynamic> j) => BoardPad(
    x: _d(j['x']),
    y: _d(j['y']),
    w: _d(j['w']),
    h: _d(j['h']),
    angle: _d(j['a']),
    shape: j['s'] as String,
    radius: _d(j['r'] ?? 0),
    front: j['F'] == true,
    back: j['B'] == true,
    drillW: _d(j['dw'] ?? 0),
    drillH: _d(j['dh'] ?? 0),
  );

  Map<String, dynamic> toJson() => {
    'x': _round(x),
    'y': _round(y),
    'w': _round(w),
    'h': _round(h),
    'a': _round(angle),
    's': shape,
    if (radius > 0) 'r': _round(radius),
    if (front) 'F': true,
    if (back) 'B': true,
    if (drillW > 0) 'dw': _round(drillW),
    if (drillH > 0) 'dh': _round(drillH),
  };
}

/// A footprint and its box: drawn at [x],[y], rotated by -[angle] degrees,
/// then offset by [relX],[relY] with size [w] x [h] (ibom's bbox).
class BoardFootprint {
  const BoardFootprint({
    required this.ref,
    required this.layer,
    required this.x,
    required this.y,
    required this.relX,
    required this.relY,
    required this.w,
    required this.h,
    required this.angle,
    required this.pads,
  });

  final String ref;

  /// `F` or `B`.
  final String layer;
  final double x, y, relX, relY, w, h, angle;
  final List<BoardPad> pads;

  /// Centre of the box in board coordinates.
  (double, double) get center => _toBoard(relX + w / 2, relY + h / 2);

  /// Corners of the box in board coordinates.
  List<(double, double)> get corners => [
    _toBoard(relX, relY),
    _toBoard(relX + w, relY),
    _toBoard(relX + w, relY + h),
    _toBoard(relX, relY + h),
  ];

  bool contains(double px, double py) {
    // Undo the translate and rotate, then compare with the box.
    final t = angle * math.pi / 180;
    final dx = px - x, dy = py - y;
    final lx = dx * math.cos(t) - dy * math.sin(t);
    final ly = dx * math.sin(t) + dy * math.cos(t);
    return lx >= relX && lx <= relX + w && ly >= relY && ly <= relY + h;
  }

  (double, double) _toBoard(double lx, double ly) {
    final t = -angle * math.pi / 180;
    return (
      x + lx * math.cos(t) - ly * math.sin(t),
      y + lx * math.sin(t) + ly * math.cos(t),
    );
  }

  factory BoardFootprint.fromJson(Map<String, dynamic> j) => BoardFootprint(
    ref: j['ref'] as String,
    layer: j['layer'] as String,
    x: _d(j['x']),
    y: _d(j['y']),
    relX: _d(j['rx']),
    relY: _d(j['ry']),
    w: _d(j['w']),
    h: _d(j['h']),
    angle: _d(j['a']),
    pads: [
      for (final p in j['pads'] as List)
        BoardPad.fromJson(p as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'layer': layer,
    'x': _round(x),
    'y': _round(y),
    'rx': _round(relX),
    'ry': _round(relY),
    'w': _round(w),
    'h': _round(h),
    'a': _round(angle),
    'pads': [for (final p in pads) p.toJson()],
  };
}

/// Reads the board out of a decoded ibom `pcbdata`. Returns null when it has
/// no outline.
BoardGeometry? boardFromPcbdata(Map<String, dynamic> pcbdata) {
  final bbox = pcbdata['edges_bbox'];
  final edgesRaw = pcbdata['edges'];
  if (bbox is! Map || edgesRaw is! List) return null;

  final edges = _drawings(edgesRaw);
  final silk = <String, List<BoardShape>>{'F': [], 'B': []};
  final drawings = pcbdata['drawings'];
  if (drawings is Map && drawings['silkscreen'] is Map) {
    final s = drawings['silkscreen'] as Map;
    for (final side in ['F', 'B']) {
      if (s[side] is List) silk[side]!.addAll(_drawings(s[side] as List));
    }
  }

  final footprints = <BoardFootprint>[];
  for (final f in (pcbdata['footprints'] as List?) ?? const []) {
    if (f is! Map) continue;
    final b = f['bbox'];
    if (b is! Map) continue;
    // Older ibom versions keep footprint silkscreen in the footprint.
    for (final d in (f['drawings'] as List?) ?? const []) {
      if (d is Map && silk.containsKey(d['layer']) && d['drawing'] is Map) {
        silk[d['layer']]!.addAll(_drawings([d['drawing']]));
      }
    }
    footprints.add(
      BoardFootprint(
        ref: f['ref'].toString(),
        layer: f['layer'] == 'B' ? 'B' : 'F',
        x: _xy(b['pos']).$1,
        y: _xy(b['pos']).$2,
        relX: _xy(b['relpos']).$1,
        relY: _xy(b['relpos']).$2,
        w: _xy(b['size']).$1,
        h: _xy(b['size']).$2,
        angle: _d(b['angle'] ?? 0),
        pads: [
          for (final p in (f['pads'] as List?) ?? const [])
            if (p is Map)
              BoardPad(
                x: _xy(p['pos']).$1,
                y: _xy(p['pos']).$2,
                w: _xy(p['size']).$1,
                h: _xy(p['size']).$2,
                angle: _d(p['angle'] ?? 0),
                shape: p['shape']?.toString() ?? 'rect',
                radius: _d(p['radius'] ?? 0),
                front: (p['layers'] as List?)?.contains('F') ?? false,
                back: (p['layers'] as List?)?.contains('B') ?? false,
                drillW: p['drillsize'] is List ? _xy(p['drillsize']).$1 : 0,
                drillH: p['drillsize'] is List ? _xy(p['drillsize']).$2 : 0,
              ),
        ],
      ),
    );
  }

  return BoardGeometry(
    minX: _d(bbox['minx']),
    minY: _d(bbox['miny']),
    maxX: _d(bbox['maxx']),
    maxY: _d(bbox['maxy']),
    outline: chainOutline(edges),
    edges: edges,
    silk: silk,
    footprints: footprints,
  );
}

/// Joins edge polylines whose ends meet into closed loops.
List<BoardShape> chainOutline(List<BoardShape> edges, {double tol = 0.02}) {
  final open = [
    for (final e in edges)
      if (e.points.length >= 4) [...e.points],
  ];
  final loops = <BoardShape>[];
  bool near(double ax, double ay, double bx, double by) =>
      (ax - bx).abs() <= tol && (ay - by).abs() <= tol;

  while (open.isNotEmpty) {
    final chain = open.removeAt(0);
    var grew = true;
    while (grew) {
      grew = false;
      final ex = chain[chain.length - 2], ey = chain[chain.length - 1];
      for (var i = 0; i < open.length; i++) {
        final p = open[i];
        final n = p.length;
        if (near(ex, ey, p[0], p[1])) {
          chain.addAll(p.sublist(2));
        } else if (near(ex, ey, p[n - 2], p[n - 1])) {
          for (var k = n - 4; k >= 0; k -= 2) {
            chain.addAll([p[k], p[k + 1]]);
          }
        } else {
          continue;
        }
        open.removeAt(i);
        grew = true;
        break;
      }
    }
    final closedLoop =
        chain.length >= 6 &&
        near(chain[0], chain[1], chain[chain.length - 2], chain.last);
    if (closedLoop) loops.add(BoardShape(chain, closed: true, filled: true));
  }
  return loops;
}

List<BoardShape> _drawings(List raw) {
  final out = <BoardShape>[];
  for (final d in raw) {
    if (d is! Map) continue;
    final width = _d(d['width'] ?? d['thickness'] ?? 0.15);
    final svg = d['svgpath'];
    if (svg is String) {
      out.addAll(_svgPolylines(svg, width));
      continue;
    }
    switch (d['type']) {
      case 'segment':
        final (x1, y1) = _xy(d['start']);
        final (x2, y2) = _xy(d['end']);
        out.add(BoardShape([x1, y1, x2, y2], width: width));
      case 'rect':
        final (x1, y1) = _xy(d['start']);
        final (x2, y2) = _xy(d['end']);
        out.add(
          BoardShape(
            [x1, y1, x2, y1, x2, y2, x1, y2],
            closed: true,
            filled: d['filled'] == 1,
            width: width,
          ),
        );
      case 'circle':
        final (cx, cy) = _xy(d['start']);
        out.add(
          BoardShape(
            _arc(cx, cy, _d(d['radius']), 0, 360),
            closed: true,
            filled: d['filled'] == 1,
            width: width,
          ),
        );
      case 'arc':
        final (cx, cy) = _xy(d['start']);
        var a0 = _d(d['startangle']), a1 = _d(d['endangle']);
        if (a1 < a0) a1 += 360;
        out.add(
          BoardShape(_arc(cx, cy, _d(d['radius']), a0, a1), width: width),
        );
      case 'curve':
        out.add(
          BoardShape(
            _bezier(
              _xy(d['start']),
              _xy(d['cpa']),
              _xy(d['cpb']),
              _xy(d['end']),
            ),
            width: width,
          ),
        );
      case 'polygon':
        final (px, py) = _xy(d['pos'] ?? const [0, 0]);
        final t = -_d(d['angle'] ?? 0) * math.pi / 180;
        for (final poly in (d['polygons'] as List?) ?? const []) {
          final pts = <double>[];
          for (final p in poly as List) {
            final (x, y) = _xy(p);
            pts.addAll([
              px + x * math.cos(t) - y * math.sin(t),
              py + x * math.sin(t) + y * math.cos(t),
            ]);
          }
          if (pts.length >= 6) {
            out.add(
              BoardShape(
                pts,
                closed: true,
                filled: d['filled'] != 0,
                width: width,
              ),
            );
          }
        }
    }
  }
  return out;
}

/// KiCad text and some shapes come as SVG paths of M/L commands.
List<BoardShape> _svgPolylines(String path, double width) {
  final out = <BoardShape>[];
  var current = <double>[];
  final re = RegExp(r'([MLZ])([^MLZ]*)', caseSensitive: false);
  for (final m in re.allMatches(path)) {
    final cmd = m.group(1)!.toUpperCase();
    final nums = RegExp(
      r'-?\d*\.?\d+(?:e-?\d+)?',
    ).allMatches(m.group(2)!).map((n) => double.parse(n.group(0)!)).toList();
    if (cmd == 'M') {
      if (current.length >= 4) out.add(BoardShape(current, width: width));
      current = nums.length >= 2 ? [nums[0], nums[1], ...nums.skip(2)] : [];
    } else if (cmd == 'L') {
      current.addAll(nums);
    } else if (cmd == 'Z' && current.length >= 4) {
      current.addAll([current[0], current[1]]);
    }
  }
  if (current.length >= 4) out.add(BoardShape(current, width: width));
  return out;
}

List<double> _arc(double cx, double cy, double r, double a0, double a1) {
  final steps = math.max(8, ((a1 - a0).abs() / 7.5).ceil());
  return [
    for (var i = 0; i <= steps; i++) ...[
      cx + r * math.cos((a0 + (a1 - a0) * i / steps) * math.pi / 180),
      cy + r * math.sin((a0 + (a1 - a0) * i / steps) * math.pi / 180),
    ],
  ];
}

List<double> _bezier(
  (double, double) p0,
  (double, double) p1,
  (double, double) p2,
  (double, double) p3,
) {
  const steps = 24;
  return [
    for (var i = 0; i <= steps; i++)
      ...() {
        final t = i / steps, u = 1 - t;
        final a = u * u * u,
            b = 3 * u * u * t,
            c = 3 * u * t * t,
            d = t * t * t;
        return [
          a * p0.$1 + b * p1.$1 + c * p2.$1 + d * p3.$1,
          a * p0.$2 + b * p1.$2 + c * p2.$2 + d * p3.$2,
        ];
      }(),
  ];
}

(double, double) _xy(Object? v) {
  if (v is List && v.length >= 2) return (_d(v[0]), _d(v[1]));
  return (0, 0);
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

double _round(double v) => (v * 1000).roundToDouble() / 1000;

List<BoardShape> _shapes(Object? v) => [
  for (final s in (v as List?) ?? const [])
    BoardShape.fromJson(s as Map<String, dynamic>),
];
