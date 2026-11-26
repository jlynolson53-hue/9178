import '../models/video.dart';

/// 接口源适配器。新增一个源 = 实现这个类 + 在 SourceRegistry 里注册
abstract class VideoSource {
  String get id;
  String get name;

  /// 空关键词时显示的内容（例如热门）
  String get emptyQueryLabel;

  Future<PageResult> search(String query, int page);

  /// 补全详情（拿到全部播放流）。列表里已有流的源可直接返回
  Future<VideoItem> detail(VideoItem item);
}

class SourceException implements Exception {
  final String message;
  SourceException(this.message);
  @override
  String toString() => message;
}
