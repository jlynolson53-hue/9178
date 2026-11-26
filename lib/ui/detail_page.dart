import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../models/video.dart';
import '../sources/video_source.dart';
import 'widgets.dart';

class DetailPage extends StatefulWidget {
  final VideoItem item;
  const DetailPage({super.key, required this.item});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late VideoItem _item = widget.item;
  VideoStream? _playing;
  VideoPlayerController? _ctrl;
  String? _error;
  bool _loadingDetail = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      _item = await sources.byId(_item.sourceId).detail(_item);
      if (!mounted) return;
      // 在线播放默认用 HLS（如有），否则选一个 ≤720p 的 MP4，省流量
      final hls = _item.streams.where((s) => s.kind == StreamKind.hls).firstOrNull;
      final play = hls ?? pickStream(_item.streams, 'sd') ?? _item.streams.firstOrNull;
      if (play != null) await _play(play);
    } catch (e) {
      if (mounted) setState(() => _error = e is SourceException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  Future<void> _play(VideoStream s) async {
    final old = _ctrl;
    final oldPos = old?.value.position;
    _savePosition();
    setState(() {
      _playing = s;
      _ctrl = null;
      _error = null;
    });
    await old?.dispose();
    final c = VideoPlayerController.networkUrl(
      Uri.parse(s.url),
      formatHint: s.kind == StreamKind.hls ? VideoFormat.hls : null,
    );
    try {
      await c.initialize();
      final resume = oldPos ?? Duration(milliseconds: libraryStore.positionOf(_item.key));
      if (resume > const Duration(seconds: 3) && resume < c.value.duration - const Duration(seconds: 3)) {
        await c.seekTo(resume);
      }
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _ctrl = c);
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
    } catch (e) {
      c.dispose();
      if (mounted) setState(() => _error = '播放失败：$e');
    }
  }

  void _savePosition() {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    libraryStore.addHistory(_item, c.value.position.inMilliseconds, c.value.duration.inMilliseconds);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savePosition();
    if (_ctrl == null) libraryStore.addHistory(_item, 0, null);
    _ctrl?.dispose();
    super.dispose();
  }

  void _download(VideoStream s) {
    final n = downloads.addAll([(_item, s)]);
    toast(context, n == 0 ? '已经在下载列表里了' : '已加入下载：${s.label}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ListenableBuilder(
            listenable: libraryStore,
            builder: (_, __) {
              final fav = libraryStore.isFavorite(_item.key);
              return IconButton(
                tooltip: fav ? '取消收藏' : '收藏',
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.redAccent : null),
                onPressed: () => libraryStore.toggleFavorite(_item),
              );
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _player()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_item.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 12, children: [
                if (_item.author != null) Text('作者：${_item.author}'),
                if (_item.width != null) Text('原始 ${_item.width}x${_item.height}'),
                if (_item.duration != null) Text('时长 ${fmtDuration(_item.duration)}'),
              ]),
              if (_item.sourceId == 'pexels')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Video by ${_item.author ?? 'unknown'} on Pexels',
                      style: TextStyle(color: cs.outline, fontSize: 12)),
                ),
              const SizedBox(height: 16),
              Row(children: [
                Text('清晰度 / 文件', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_item.streams.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final s = pickStream(_item.streams, settings.preferQuality);
                      if (s != null) _download(s);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('按推荐画质下载'),
                  ),
              ]),
              const SizedBox(height: 4),
              if (_loadingDetail) const LinearProgressIndicator(),
            ]),
          ),
          for (final s in _item.streams)
            ListTile(
              leading: Icon(s.kind == StreamKind.hls ? Icons.stream : Icons.movie_outlined,
                  color: _playing?.url == s.url ? cs.primary : null),
              title: Text(s.label.isEmpty ? s.kindLabel : s.label),
              subtitle: Text(s.kindLabel),
              selected: _playing?.url == s.url,
              onTap: () => _play(s),
              trailing: IconButton(
                tooltip: '下载这个',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _download(s),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _player() {
    final c = _ctrl;
    if (_error != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return Stack(fit: StackFit.expand, children: [
        Cover(url: _item.cover),
        const Center(child: CircularProgressIndicator()),
      ]);
    }
    return Container(
      color: Colors.black,
      child: Stack(alignment: Alignment.bottomCenter, children: [
        Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
          child: ValueListenableBuilder(
            valueListenable: c,
            builder: (_, v, __) => Center(
              child: AnimatedOpacity(
                opacity: v.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.play_circle_fill, size: 56, color: Colors.white70),
              ),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: c,
          builder: (_, v, __) => Container(
            color: Colors.black38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Text(fmtPos(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              Expanded(
                child: VideoProgressIndicator(c, allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
              ),
              Text(fmtPos(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
              PopupMenuButton<double>(
                tooltip: '倍速',
                icon: Text('${v.playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12)),
                onSelected: (s) => c.setPlaybackSpeed(s),
                itemBuilder: (_) => [
                  for (final s in [0.5, 1.0, 1.25, 1.5, 2.0, 3.0])
                    PopupMenuItem(value: s, child: Text('${s}x')),
                ],
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
