import '../core/settings.dart';
import '../models/video.dart';
import 'video_source.dart';

/// “直链 / M3U8”源：手动粘贴的 m3u8 或 mp4 地址，用来播放和批量下载 HLS 视频
class DirectLinkSource extends VideoSource {
  final Settings settings;
  DirectLinkSource(this.settings);

  /// 公开测试流，方便验证 m3u8 下载与合并
  static const samples = [
    {'title': '测试流 · Big Buck Bunny (HLS)', 'url': 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'},
    {'title': '测试流 · Apple BipBop (HLS)', 'url': 'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8'},
  ];

  @override
  String get id => 'direct';
  @override
  String get name => '直链 / M3U8';
  @override
  String get emptyQueryLabel => '我的链接';

  static VideoItem itemFor(String title, String url) {
    final kind = VideoStream.detectKind(url);
    return VideoItem(
      sourceId: 'direct',
      id: url,
      title: title.isEmpty ? Uri.tryParse(url)?.pathSegments.lastOrNull ?? url : title,
      pageUrl: url,
      streams: [
        VideoStream(
          url: url,
          label: kind == StreamKind.hls ? 'M3U8（下载时按设置选清晰度）' : '原始文件',
          kind: kind,
        )
      ],
    );
  }

  @override
  Future<PageResult> search(String query, int page) async {
    if (page > 1) return const PageResult([], false);
    final links = [...settings.directLinks];
    for (final s in samples) {
      if (!links.any((e) => e['url'] == s['url'])) links.add(s);
    }
    final q = query.trim().toLowerCase();
    final items = links
        .where((e) =>
            q.isEmpty ||
            (e['title'] ?? '').toLowerCase().contains(q) ||
            (e['url'] ?? '').toLowerCase().contains(q))
        .map((e) => itemFor(e['title'] ?? '', e['url'] ?? ''))
        .toList();
    return PageResult(items, false);
  }

  @override
  Future<VideoItem> detail(VideoItem item) async => item;
}
