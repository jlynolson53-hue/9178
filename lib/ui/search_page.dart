import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../models/video.dart';
import '../sources/direct_link_source.dart';
import '../sources/video_source.dart';
import 'detail_page.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<VideoItem> _items = [];
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  int _gen = 0; // 防止旧请求覆盖新结果

  VideoSource get _src => sources.current;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _load();
    });
    settings.addListener(_onSettings);
    _refresh();
  }

  String _lastSource = '';
  String _lastKey = '';
  void _onSettings() {
    // 切换源或填写 Key 后自动刷新
    if (settings.sourceId != _lastSource || settings.apiKey != _lastKey) _refresh();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _lastSource = settings.sourceId;
    _lastKey = settings.apiKey;
    _gen++;
    setState(() {
      _items.clear();
      _selected.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final gen = _gen;
    setState(() => _loading = true);
    try {
      final r = await _src.search(_ctrl.text, _page);
      if (gen != _gen || !mounted) return;
      setState(() {
        final keys = _items.map((e) => e.key).toSet();
        _items.addAll(r.items.where((e) => !keys.contains(e.key)));
        _hasMore = r.hasMore;
        _page++;
      });
    } catch (e) {
      if (gen != _gen || !mounted) return;
      setState(() {
        _error = e is SourceException ? e.message : '$e';
        _hasMore = false;
      });
    } finally {
      if (gen == _gen && mounted) setState(() => _loading = false);
    }
  }

  void _toggle(VideoItem v) {
    setState(() {
      if (!_selected.remove(v.key)) _selected.add(v.key);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  Future<void> _batchDownload(List<VideoItem> list) async {
    if (list.isEmpty) return;
    final pairs = <(VideoItem, VideoStream)>[];
    for (final v in list) {
      final s = pickStream(v.streams, settings.preferQuality);
      if (s != null) pairs.add((v, s));
    }
    final n = downloads.addAll(pairs);
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    toast(context, n == 0 ? '这些视频都已在下载列表里' : '已加入 $n 个下载任务');
  }

  Future<void> _addLinks() async {
    final title = TextEditingController();
    final links = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加 m3u8 / mp4 链接'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: links,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '链接（每行一个，可批量）',
                hintText: 'https://.../index.m3u8\n也支持 “标题\$链接” 格式',
              ),
            ),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: '标题前缀（可选）'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    var i = 0;
    final lines = links.text.split(RegExp(r'[\r\n#]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    for (final line in lines.toList().reversed) {
      String t = '', u = line;
      if (line.contains(r'$')) {
        final idx = line.indexOf(r'$');
        t = line.substring(0, idx).trim();
        u = line.substring(idx + 1).trim();
      }
      if (!u.startsWith('http')) continue;
      if (t.isEmpty && title.text.trim().isNotEmpty) t = '${title.text.trim()} ${lines.length - i}';
      settings.addDirectLink(t, u);
      i++;
    }
    if (mounted) toast(context, '已添加 $i 个链接');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDirect = _src is DirectLinkSource;
    final selectedItems = _items.where((e) => _selected.contains(e.key)).toList();
    return Scaffold(
      appBar: AppBar(
        title: _selecting ? Text('已选 ${_selected.length} 个') : const Text('PexDL'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              )
            : null,
        actions: _selecting
            ? [
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == _items.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(_items.map((e) => e.key));
                    }
                  }),
                  child: Text(_selected.length == _items.length ? '全不选' : '全选'),
                ),
                IconButton(
                  tooltip: '批量下载',
                  icon: const Icon(Icons.download),
                  onPressed: () => _batchDownload(selectedItems),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  tooltip: '切换接口源',
                  icon: const Icon(Icons.swap_horiz),
                  initialValue: settings.sourceId,
                  onSelected: (id) => settings.sourceId = id,
                  itemBuilder: (_) => [
                    for (final s in sources.all) PopupMenuItem(value: s.id, child: Text(s.name)),
                  ],
                ),
                IconButton(
                  tooltip: '多选下载',
                  icon: const Icon(Icons.checklist),
                  onPressed: _items.isEmpty ? null : () => setState(() => _selecting = true),
                ),
              ],
      ),
      floatingActionButton: isDirect && !_selecting
          ? FloatingActionButton.extended(
              onPressed: _addLinks,
              icon: const Icon(Icons.add_link),
              label: const Text('添加链接'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SearchBar(
              controller: _ctrl,
              hintText: isDirect ? '筛选我的链接' : '搜索 ${_src.name} 视频（英文关键词效果更好）',
              leading: const Icon(Icons.search),
              trailing: [
                Chip(label: Text(_src.name), visualDensity: VisualDensity.compact),
              ],
              onSubmitted: (_) => _refresh(),
            ),
          ),
          if (_ctrl.text.isEmpty && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text(_src.emptyQueryLabel, style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (!isDirect)
                  Text('视频来自 Pexels', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _refresh, child: const Text('重试')),
          ]),
        ),
      );
    }
    if (_items.isEmpty) return const Center(child: Text('没有结果'));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.98,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
          }
          final v = _items[i];
          return VideoCard(
            item: v,
            selecting: _selecting,
            selected: _selected.contains(v.key),
            onTap: () {
              if (_selecting) {
                _toggle(v);
              } else {
                Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(item: v)));
              }
            },
            onLongPress: () {
              if (!_selecting) setState(() => _selecting = true);
              _toggle(v);
            },
          );
        },
      ),
    );
  }
}
