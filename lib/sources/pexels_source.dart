import 'package:dio/dio.dart';

import '../core/settings.dart';
import '../models/video.dart';
import 'video_source.dart';

/// Pexels 官方视频接口
/// 文档：https://www.pexels.com/api/documentation/#videos
/// 新路径为 https://api.pexels.com/v1/videos/...
class PexelsSource extends VideoSource {
  final Settings settings;
  PexelsSource(this.settings);

  static const _base = 'https://api.pexels.com/v1/videos';
  static const _perPage = 30;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  String get id => 'pexels';
  @override
  String get name => 'Pexels';
  @override
  String get emptyQueryLabel => '热门视频';

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> q) async {
    final key = settings.apiKey;
    if (key.isEmpty) {
      throw SourceException('还没有填写 Pexels API Key：请到“我的 → 设置”里填写');
    }
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '$_base$path',
        queryParameters: q,
        options: Options(headers: {'Authorization': key}),
      );
      return r.data ?? {};
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) throw SourceException('API Key 无效（$code）');
      if (code == 429) throw SourceException('请求过于频繁：Pexels 默认每小时 200 次');
      throw SourceException('网络错误：${e.message ?? code}');
    }
  }

  @override
  Future<PageResult> search(String query, int page) async {
    final q = query.trim();
    final data = q.isEmpty
        ? await _get('/popular', {'page': page, 'per_page': _perPage})
        : await _get('/search', {'query': q, 'page': page, 'per_page': _perPage});
    final list = (data['videos'] as List? ?? [])
        .map((e) => _parse((e as Map).cast<String, dynamic>()))
        .toList();
    return PageResult(list, data['next_page'] != null && list.isNotEmpty);
  }

  @override
  Future<VideoItem> detail(VideoItem item) async {
    if (item.streams.isNotEmpty) return item;
    final data = await _get('/videos/${item.id}', {});
    return _parse(data);
  }

  VideoItem _parse(Map<String, dynamic> v) {
    final files = (v['video_files'] as List? ?? []).map((e) => (e as Map).cast<String, dynamic>());
    final streams = <VideoStream>[];
    for (final f in files) {
      final link = f['link'] as String?;
      if (link == null || link.isEmpty) continue;
      final w = (f['width'] as num?)?.toInt();
      final h = (f['height'] as num?)?.toInt();
      final quality = (f['quality'] ?? '').toString();
      final kind = VideoStream.detectKind(link,
          fileType: f['file_type']?.toString(), quality: quality);
      final fps = (f['fps'] as num?)?.round();
      final res = (w != null && h != null) ? '${w}x$h' : quality.toUpperCase();
      streams.add(VideoStream(
        url: link,
        kind: kind,
        width: w,
        height: h,
        label: [res, if (fps != null && fps > 0) '${fps}fps', if (quality.isNotEmpty) quality]
            .join(' · '),
      ));
    }
    // HLS 放最前，其余按分辨率从高到低
    streams.sort((a, b) {
      if (a.kind != b.kind) return a.kind == StreamKind.hls ? -1 : 1;
      return b.shortSide.compareTo(a.shortSide);
    });
    final user = (v['user'] as Map?)?.cast<String, dynamic>();
    final url = v['url'] as String?;
    return VideoItem(
      sourceId: id,
      id: v['id'].toString(),
      title: _titleFromUrl(url) ?? 'Pexels 视频 ${v['id']}',
      cover: v['image'] as String?,
      duration: (v['duration'] as num?)?.toInt(),
      author: user?['name'] as String?,
      authorUrl: user?['url'] as String?,
      pageUrl: url,
      width: (v['width'] as num?)?.toInt(),
      height: (v['height'] as num?)?.toInt(),
      streams: streams,
    );
  }

  /// Pexels 视频没有标题字段，从页面地址里提取：.../video/ocean-waves-1234/ -> Ocean waves
  String? _titleFromUrl(String? url) {
    if (url == null) return null;
    final seg = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg == null || seg.isEmpty) return null;
    var slug = seg.last.replaceAll(RegExp(r'-?\d+$'), '').replaceAll('-', ' ').trim();
    if (slug.isEmpty) return null;
    return slug[0].toUpperCase() + slug.substring(1);
  }
}
