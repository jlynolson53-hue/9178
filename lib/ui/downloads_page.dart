import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../download/download_task.dart';
import '../models/video.dart';
import 'local_player_page.dart';
import 'widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final tasks = downloads.tasks;
        final doing = tasks.where((t) => t.status != TaskStatus.done).toList();
        final done = tasks.where((t) => t.status == TaskStatus.done).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('下载管理'),
            actions: [
              IconButton(tooltip: '全部开始', icon: const Icon(Icons.play_arrow), onPressed: downloads.resumeAll),
              IconButton(tooltip: '全部暂停', icon: const Icon(Icons.pause), onPressed: downloads.pauseAll),
              IconButton(
                tooltip: '清除已完成记录（不删文件）',
                icon: const Icon(Icons.cleaning_services_outlined),
                onPressed: done.isEmpty ? null : downloads.clearFinished,
              ),
            ],
          ),
          body: tasks.isEmpty
              ? const Center(child: Text('还没有下载任务\n在搜索页长按视频可以多选批量下载', textAlign: TextAlign.center))
              : ListView(
                  children: [
                    if (doing.isNotEmpty) _header(context, '进行中（${doing.length}）'),
                    for (final t in doing) _TaskTile(t),
                    if (done.isNotEmpty) _header(context, '已完成（${done.length}）'),
                    for (final t in done) _TaskTile(t),
                    const SizedBox(height: 24),
                  ],
                ),
        );
      },
    );
  }

  Widget _header(BuildContext c, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(s, style: Theme.of(c).textTheme.titleSmall),
      );
}

class _TaskTile extends StatelessWidget {
  final DownloadTask t;
  const _TaskTile(this.t);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHls = t.kind == StreamKind.hls;
    final detail = <String>[
      t.status.text,
      if (isHls && t.segTotal > 0) '分片 ${t.segDone}/${t.segTotal}',
      if (!isHls || t.status == TaskStatus.done)
        t.total > 0 && t.status != TaskStatus.done ? '${fmtBytes(t.received)} / ${fmtBytes(t.total)}' : fmtBytes(t.received)
      else
        fmtBytes(t.received),
      if (t.status == TaskStatus.running && t.speed > 0) '${fmtBytes(t.speed.round())}/s',
    ].join('  ·  ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: t.status == TaskStatus.done && t.outputPath != null
            ? () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => LocalPlayerPage(path: t.outputPath!, title: t.item.title)))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            SizedBox(
              width: 96,
              height: 60,
              child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Cover(url: t.item.cover, kind: t.kind)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${isHls ? 'M3U8' : 'MP4'} · ${t.qualityLabel}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.outline)),
                const SizedBox(height: 4),
                if (t.status != TaskStatus.done)
                  LinearProgressIndicator(
                    value: t.status == TaskStatus.merging ? null : t.progress,
                    borderRadius: BorderRadius.circular(4),
                  ),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 12)),
                if (t.error != null)
                  Text(t.error!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.error)),
                if (t.status == TaskStatus.done && t.outputPath != null)
                  Text(t.outputPath!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: cs.outline)),
              ]),
            ),
            _actions(context),
          ]),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      switch (t.status) {
        TaskStatus.running || TaskStatus.queued =>
          IconButton(tooltip: '暂停', icon: const Icon(Icons.pause), onPressed: () => downloads.pause(t)),
        TaskStatus.paused || TaskStatus.failed =>
          IconButton(tooltip: '继续', icon: const Icon(Icons.play_arrow), onPressed: () => downloads.resume(t)),
        _ => const SizedBox(height: 48),
      },
      IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline),
        onPressed: t.status == TaskStatus.merging ? null : () => _confirmDelete(context),
      ),
    ]);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    var delFile = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('删除任务'),
          content: t.status == TaskStatus.done
              ? CheckboxListTile(
                  value: delFile,
                  onChanged: (v) => set(() => delFile = v ?? false),
                  title: const Text('同时删除已下载的文件'),
                )
              : const Text('未完成的临时分片会一起删除'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
          ],
        ),
      ),
    );
    if (ok == true) await downloads.remove(t, deleteFile: delFile);
  }
}
