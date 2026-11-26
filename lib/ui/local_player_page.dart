import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/format.dart';

/// 播放已下载到本机的文件
class LocalPlayerPage extends StatefulWidget {
  final String path;
  final String title;
  const LocalPlayerPage({super.key, required this.path, required this.title});
  @override
  State<LocalPlayerPage> createState() => _LocalPlayerPageState();
}

class _LocalPlayerPageState extends State<LocalPlayerPage> {
  VideoPlayerController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = File(widget.path);
    if (!f.existsSync()) {
      _error = '文件不存在（可能已被移动或删除）';
      return;
    }
    final c = VideoPlayerController.file(f);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _c = c);
      c.play();
    }).catchError((e) {
      if (mounted) setState(() => _error = '无法播放：$e');
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                      child: Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: c,
                    builder: (_, v, __) => Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      child: Row(children: [
                        IconButton(
                          icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                          onPressed: () => v.isPlaying ? c.pause() : c.play(),
                        ),
                        Text(fmtPos(v.position), style: const TextStyle(color: Colors.white)),
                        Expanded(child: VideoProgressIndicator(c, allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
                        Text(fmtPos(v.duration), style: const TextStyle(color: Colors.white)),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
