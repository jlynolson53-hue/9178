import 'dart:math' as math;

enum StreamKind { mp4, hls }

class VideoStream {
  final String url;
  final String label;
  final StreamKind kind;
  final int? width;
  final int? height;

  const VideoStream({
    required this.url,
    required this.label,
    required this.kind,
    this.width,
    this.height,
  });

  /// 短边像素，用来判断 720p / 1080p（兼容竖屏视频）
  int get shortSide {
    if (width == null || height == null) return height ?? width ?? 0;
    return math.min(width!, height!);
  }

  String get kindLabel => kind == StreamKind.hls ? 'M3U8' : 'MP4';

  static StreamKind detectKind(String url, {String? fileType, String? quality}) {
    final u = url.toLowerCase();
    final t = (fileType ?? '').toLowerCase();
    if (u.contains('.m3u8') || t.contains('mpegurl') || quality == 'hls') {
      return StreamKind.hls;
    }
    return StreamKind.mp4;
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'label': label,
        'kind': kind.name,
        'width': width,
        'height': height,
      };

  factory VideoStream.fromJson(Map<String, dynamic> j) => VideoStream(
        url: j['url'] as String,
        label: (j['label'] ?? '') as String,
        kind: StreamKind.values.byName((j['kind'] ?? 'mp4') as String),
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
      );
}

class VideoItem {
  final String sourceId;
  final String id;
  final String title;
  final String? cover;
  final int? duration;
  final String? author;
  final String? authorUrl;
  final String? pageUrl;
  final int? width;
  final int? height;
  final List<VideoStream> streams;

  const VideoItem({
    required this.sourceId,
    required this.id,
    required this.title,
    this.cover,
    this.duration,
    this.author,
    this.authorUrl,
    this.pageUrl,
    this.width,
    this.height,
    this.streams = const [],
  });

  String get key => '$sourceId:$id';

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'id': id,
        'title': title,
        'cover': cover,
        'duration': duration,
        'author': author,
        'authorUrl': authorUrl,
        'pageUrl': pageUrl,
        'width': width,
        'height': height,
        'streams': streams.map((e) => e.toJson()).toList(),
      };

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        sourceId: j['sourceId'] as String,
        id: j['id'].toString(),
        title: (j['title'] ?? '') as String,
        cover: j['cover'] as String?,
        duration: (j['duration'] as num?)?.toInt(),
        author: j['author'] as String?,
        authorUrl: j['authorUrl'] as String?,
        pageUrl: j['pageUrl'] as String?,
        width: (j['width'] as num?)?.toInt(),
        height: (j['height'] as num?)?.toInt(),
        streams: ((j['streams'] as List?) ?? [])
            .map((e) => VideoStream.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class PageResult {
  final List<VideoItem> items;
  final bool hasMore;
  const PageResult(this.items, this.hasMore);
}

/// 按“推荐画质”挑选下载流：优先 MP4，没有 MP4 才用 M3U8
VideoStream? pickStream(List<VideoStream> streams, String pref) {
  if (streams.isEmpty) return null;
  final mp4 = streams.where((s) => s.kind == StreamKind.mp4).toList();
  if (mp4.isEmpty) return streams.first;
  mp4.sort((a, b) => b.shortSide.compareTo(a.shortSide));
  final int? cap = switch (pref) { 'sd' => 540, 'hd' => 1080, _ => null };
  if (cap == null) return mp4.first;
  for (final s in mp4) {
    if (s.shortSide <= cap) return s;
  }
  return mp4.last;
}
