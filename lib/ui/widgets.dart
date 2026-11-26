import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/video.dart';

class VideoCard extends StatelessWidget {
  final VideoItem item;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const VideoCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Cover(url: item.cover, kind: item.streams.firstOrNull?.kind),
                ),
                if (item.duration != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _Tag(fmtDuration(item.duration)),
                  ),
                if (item.streams.any((s) => s.kind == StreamKind.hls))
                  const Positioned(left: 6, bottom: 6, child: _Tag('M3U8')),
                if (selecting)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? cs.primary : Colors.white,
                      shadows: const [Shadow(blurRadius: 4)],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium),
          if (item.author != null)
            Text(item.author!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }
}

class Cover extends StatelessWidget {
  final String? url;
  final StreamKind? kind;
  const Cover({super.key, this.url, this.kind});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    final ph = Container(
      color: bg,
      alignment: Alignment.center,
      child: Icon(kind == StreamKind.hls ? Icons.live_tv : Icons.movie_outlined, size: 36),
    );
    if (url == null || url!.isEmpty) return ph;
    return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
      );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}
