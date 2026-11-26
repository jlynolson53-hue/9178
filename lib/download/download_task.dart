import '../models/video.dart';

enum TaskStatus { queued, running, paused, merging, done, failed }

extension TaskStatusText on TaskStatus {
  String get text => switch (this) {
        TaskStatus.queued => '等待中',
        TaskStatus.running => '下载中',
        TaskStatus.paused => '已暂停',
        TaskStatus.merging => '合并中',
        TaskStatus.done => '已完成',
        TaskStatus.failed => '失败',
      };
}

class DownloadTask {
  final String id;
  final VideoItem item;
  final String url;
  final StreamKind kind;
  final String qualityLabel;
  final int createdAt;

  TaskStatus status;
  int received; // 已下载字节
  int total; // MP4 总字节，未知为 0
  int segDone; // HLS 已完成分片
  int segTotal;
  String? error;
  String? outputPath;

  // 运行时字段（不保存）
  double speed = 0; // 字节/秒

  DownloadTask({
    required this.id,
    required this.item,
    required this.url,
    required this.kind,
    required this.qualityLabel,
    required this.createdAt,
    this.status = TaskStatus.queued,
    this.received = 0,
    this.total = 0,
    this.segDone = 0,
    this.segTotal = 0,
    this.error,
    this.outputPath,
  });

  double get progress {
    if (status == TaskStatus.done) return 1;
    if (kind == StreamKind.hls) return segTotal == 0 ? 0 : segDone / segTotal;
    return total == 0 ? 0 : received / total;
  }

  bool get active => status == TaskStatus.running || status == TaskStatus.merging;

  Map<String, dynamic> toJson() => {
        'id': id,
        'item': item.toJson(),
        'url': url,
        'kind': kind.name,
        'q': qualityLabel,
        'createdAt': createdAt,
        'status': status.name,
        'received': received,
        'total': total,
        'segDone': segDone,
        'segTotal': segTotal,
        'error': error,
        'out': outputPath,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
        id: j['id'] as String,
        item: VideoItem.fromJson((j['item'] as Map).cast<String, dynamic>()),
        url: j['url'] as String,
        kind: StreamKind.values.byName(j['kind'] as String),
        qualityLabel: (j['q'] ?? '') as String,
        createdAt: (j['createdAt'] as num).toInt(),
        status: TaskStatus.values.byName(j['status'] as String),
        received: (j['received'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        segDone: (j['segDone'] as num?)?.toInt() ?? 0,
        segTotal: (j['segTotal'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        outputPath: j['out'] as String?,
      );
}
