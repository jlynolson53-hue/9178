import 'dart:typed_data';

/// 一个 m3u8 分片
class HlsSegment {
  final String url;
  final double duration;
  final int seq; // 媒体序列号，AES 默认 IV 用
  final String? keyUri; // AES-128 密钥地址，null 表示未加密
  final String? ivHex; // 显式 IV（0x...）
  final int? rangeStart; // EXT-X-BYTERANGE
  final int? rangeLength;

  HlsSegment({
    required this.url,
    required this.duration,
    required this.seq,
    this.keyUri,
    this.ivHex,
    this.rangeStart,
    this.rangeLength,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'd': duration,
        'seq': seq,
        'key': keyUri,
        'iv': ivHex,
        'rs': rangeStart,
        'rl': rangeLength,
      };

  factory HlsSegment.fromJson(Map<String, dynamic> j) => HlsSegment(
        url: j['url'] as String,
        duration: (j['d'] as num?)?.toDouble() ?? 0,
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        keyUri: j['key'] as String?,
        ivHex: j['iv'] as String?,
        rangeStart: (j['rs'] as num?)?.toInt(),
        rangeLength: (j['rl'] as num?)?.toInt(),
      );

  /// AES-128 的 IV：有显式 IV 用显式的，否则用媒体序列号（16 字节大端）
  Uint8List iv() {
    final out = Uint8List(16);
    if (ivHex != null) {
      var h = ivHex!.toLowerCase();
      if (h.startsWith('0x')) h = h.substring(2);
      h = h.padLeft(32, '0');
      if (h.length > 32) h = h.substring(h.length - 32);
      for (var i = 0; i < 16; i++) {
        out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    }
    var s = seq;
    for (var i = 15; i >= 8; i--) {
      out[i] = s & 0xff;
      s >>= 8;
    }
    return out;
  }
}

class HlsVariant {
  final String url;
  final int bandwidth;
  final int? width;
  final int? height;
  HlsVariant(this.url, this.bandwidth, this.width, this.height);

  int get shortSide {
    if (width == null || height == null) return 0;
    return width! < height! ? width! : height!;
  }
}

class HlsPlaylist {
  final bool isMaster;
  final List<HlsVariant> variants;
  final List<HlsSegment> segments;
  final String? mapUrl; // fMP4 的初始化分片 EXT-X-MAP
  final String? unsupported; // 不支持的原因（例如 DRM / SAMPLE-AES）

  HlsPlaylist({
    this.isMaster = false,
    this.variants = const [],
    this.segments = const [],
    this.mapUrl,
    this.unsupported,
  });
}

final _attrRe = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

Map<String, String> _attrs(String s) {
  final m = <String, String>{};
  for (final a in _attrRe.allMatches(s)) {
    var v = a.group(2)!;
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      v = v.substring(1, v.length - 1);
    }
    m[a.group(1)!] = v;
  }
  return m;
}

/// 解析 m3u8 文本。[base] 是该 m3u8 自己的地址，用来补全相对路径
HlsPlaylist parseM3u8(String text, Uri base) {
  final lines = text
      .replaceAll('\r', '')
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) {
    throw const FormatException('不是有效的 m3u8 文件');
  }

  // 主列表（多清晰度）
  if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
    final vs = <HlsVariant>[];
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final a = _attrs(lines[i].substring(lines[i].indexOf(':') + 1));
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        if (!lines[j].startsWith('#')) {
          uri = lines[j];
          break;
        }
      }
      if (uri == null) continue;
      int? w, h;
      final res = a['RESOLUTION'];
      if (res != null && res.contains('x')) {
        final p = res.split('x');
        w = int.tryParse(p[0]);
        h = int.tryParse(p[1]);
      }
      vs.add(HlsVariant(base.resolve(uri).toString(),
          int.tryParse(a['BANDWIDTH'] ?? a['AVERAGE-BANDWIDTH'] ?? '') ?? 0, w, h));
    }
    return HlsPlaylist(isMaster: true, variants: vs);
  }

  // 分片列表
  final segs = <HlsSegment>[];
  var seq = 0;
  double dur = 0;
  String? keyUri, ivHex, mapUrl, unsupported;
  int? rangeLen, rangeStart;
  var nextOffset = 0;

  for (final l in lines) {
    if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      seq = int.tryParse(l.split(':')[1]) ?? 0;
    } else if (l.startsWith('#EXTINF:')) {
      dur = double.tryParse(l.substring(8).split(',').first) ?? 0;
    } else if (l.startsWith('#EXT-X-KEY:')) {
      final a = _attrs(l.substring(11));
      final method = (a['METHOD'] ?? 'NONE').toUpperCase();
      if (method == 'NONE') {
        keyUri = null;
        ivHex = null;
      } else if (method == 'AES-128') {
        final u = a['URI'];
        if (u == null || u.startsWith('skd://') || u.startsWith('data:')) {
          unsupported = '不支持的密钥地址：$u';
        } else {
          keyUri = base.resolve(u).toString();
          ivHex = a['IV'];
        }
      } else {
        unsupported = '该视频使用 $method 加密（属于 DRM 版权保护），不支持下载';
      }
    } else if (l.startsWith('#EXT-X-MAP:')) {
      final u = _attrs(l.substring(11))['URI'];
      if (u != null) mapUrl = base.resolve(u).toString();
    } else if (l.startsWith('#EXT-X-BYTERANGE:')) {
      final v = l.substring(17).split('@');
      rangeLen = int.tryParse(v[0]);
      rangeStart = v.length > 1 ? int.tryParse(v[1]) : nextOffset;
    } else if (!l.startsWith('#')) {
      segs.add(HlsSegment(
        url: base.resolve(l).toString(),
        duration: dur,
        seq: seq,
        keyUri: keyUri,
        ivHex: ivHex,
        rangeStart: rangeLen != null ? rangeStart : null,
        rangeLength: rangeLen,
      ));
      if (rangeLen != null) nextOffset = (rangeStart ?? 0) + rangeLen;
      rangeLen = null;
      rangeStart = null;
      seq++;
      dur = 0;
    }
  }
  if (segs.isEmpty && unsupported == null) unsupported = 'm3u8 里没有分片';
  return HlsPlaylist(segments: segs, mapUrl: mapUrl, unsupported: unsupported);
}

/// 按画质偏好从主列表里选一个清晰度
HlsVariant chooseVariant(List<HlsVariant> vs, String pref) {
  final list = [...vs]..sort((a, b) {
      final c = b.shortSide.compareTo(a.shortSide);
      return c != 0 ? c : b.bandwidth.compareTo(a.bandwidth);
    });
  final int? cap = switch (pref) { 'sd' => 540, 'hd' => 1080, _ => null };
  if (cap == null) return list.first;
  for (final v in list) {
    if (v.shortSide == 0 || v.shortSide <= cap) return v;
  }
  return list.last;
}
