import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../models/video.dart';
import 'detail_page.dart';
import 'widgets.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, libraryStore]),
        builder: (context, _) => ListView(children: [
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('收藏'),
            trailing: Text('${libraryStore.favorites.length}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const _ListPage(history: false))),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('观看记录'),
            trailing: Text('${libraryStore.history.length}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const _ListPage(history: true))),
          ),
          const Divider(),
          _sectionTitle(context, '接口源'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Pexels API Key'),
            subtitle: Text(settings.apiKey.isEmpty
                ? '未填写（到 pexels.com/api 免费申请）'
                : '已填写：${settings.apiKey.substring(0, settings.apiKey.length.clamp(0, 6))}******'),
            onTap: () => _editKey(context),
          ),
          for (final s in sources.all)
            RadioListTile<String>(
              value: s.id,
              groupValue: settings.sourceId,
              onChanged: (v) => settings.sourceId = v!,
              title: Text(s.name),
            ),
          const Divider(),
          _sectionTitle(context, '下载'),
          FutureBuilder(
            future: downloads.saveDir(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('保存目录'),
              subtitle: Text(snap.data ?? '...'),
              onTap: () => _pickDir(context),
              trailing: settings.saveDir == null
                  ? null
                  : IconButton(
                      tooltip: '恢复默认',
                      icon: const Icon(Icons.restore),
                      onPressed: () => settings.saveDir = null,
                    ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('推荐画质（批量下载 / m3u8 选清晰度）'),
            trailing: DropdownButton<String>(
              value: settings.preferQuality,
              onChanged: (v) => settings.preferQuality = v!,
              items: const [
                DropdownMenuItem(value: 'highest', child: Text('最高')),
                DropdownMenuItem(value: 'hd', child: Text('≤1080p')),
                DropdownMenuItem(value: 'sd', child: Text('≤540p')),
              ],
            ),
          ),
          _slider(context, '同时下载任务数', settings.maxTasks, 1, 5, (v) => settings.maxTasks = v),
          _slider(context, 'm3u8 分片并发数', settings.segConcurrency, 1, 16, (v) => settings.segConcurrency = v),
          SwitchListTile(
            secondary: const Icon(Icons.merge_type),
            title: const Text('m3u8 合并后转成 MP4'),
            subtitle: const Text('关闭则直接保存为 .ts 文件（更快）'),
            value: settings.mergeToMp4,
            onChanged: (v) => settings.mergeToMp4 = v,
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于'),
            subtitle: Text('PexDL 1.0.0 · 私人本地使用\n视频由 Pexels 提供（pexels.com）'),
          ),
        ]),
      ),
    );
  }

  Widget _sectionTitle(BuildContext c, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(s, style: Theme.of(c).textTheme.titleSmall?.copyWith(color: Theme.of(c).colorScheme.primary)),
      );

  Widget _slider(BuildContext c, String title, int value, int min, int max, ValueChanged<int> on) => ListTile(
        title: Text('$title：$value'),
        subtitle: Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: (v) => on(v.round()),
        ),
      );

  Future<void> _editKey(BuildContext context) async {
    final c = TextEditingController(text: settings.apiKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Pexels API Key'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: '粘贴你的 API Key'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) settings.apiKey = c.text;
  }

  Future<void> _pickDir(BuildContext context) async {
    // Android 11+ 写入自选的公共目录需要“所有文件访问权限”
    var st = await Permission.manageExternalStorage.status;
    if (!st.isGranted) st = await Permission.manageExternalStorage.request();
    if (!st.isGranted) {
      final s2 = await Permission.storage.request(); // Android 10 及以下
      if (!s2.isGranted && context.mounted) {
        toast(context, '没有存储权限，只能使用默认目录');
        return;
      }
    }
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择保存目录');
    if (dir != null) {
      settings.saveDir = dir;
      if (context.mounted) toast(context, '新下载将保存到：$dir');
    }
  }
}

class _ListPage extends StatelessWidget {
  final bool history;
  const _ListPage({required this.history});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: libraryStore,
      builder: (context, _) {
        final List<(VideoItem, String)> rows = history
            ? libraryStore.history.map((h) {
                final pct = (h.durationMs != null && h.durationMs! > 0)
                    ? ' · 看到 ${(h.positionMs * 100 / h.durationMs!).round()}%'
                    : '';
                return (h.item, '${fmtDate(h.time)}$pct');
              }).toList()
            : libraryStore.favorites.map((v) => (v, v.author ?? v.sourceId)).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(history ? '观看记录' : '收藏'),
            actions: [
              if (history && rows.isNotEmpty)
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: libraryStore.clearHistory,
                ),
              if (!history && rows.isNotEmpty)
                IconButton(
                  tooltip: '全部下载',
                  icon: const Icon(Icons.download),
                  onPressed: () {
                    final pairs = <(VideoItem, VideoStream)>[];
                    for (final (v, _) in rows) {
                      final s = pickStream(v.streams, settings.preferQuality);
                      if (s != null) pairs.add((v, s));
                    }
                    toast(context, '已加入 ${downloads.addAll(pairs)} 个下载任务');
                  },
                ),
            ],
          ),
          body: rows.isEmpty
              ? const Center(child: Text('空空如也'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final (v, sub) = rows[i];
                    return ListTile(
                      leading: SizedBox(width: 80, height: 50,
                          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Cover(url: v.cover))),
                      title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(sub),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(item: v))),
                      trailing: history
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.favorite, color: Colors.redAccent),
                              onPressed: () => libraryStore.toggleFavorite(v),
                            ),
                    );
                  },
                ),
        );
      },
    );
  }
}
