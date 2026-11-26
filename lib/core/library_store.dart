import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video.dart';

class HistoryEntry {
  final VideoItem item;
  final int time;
  final int positionMs;
  final int? durationMs;

  HistoryEntry(this.item, this.time, this.positionMs, this.durationMs);

  Map<String, dynamic> toJson() => {
        'item': item.toJson(),
        'time': time,
        'pos': positionMs,
        'dur': durationMs,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        VideoItem.fromJson((j['item'] as Map).cast<String, dynamic>()),
        (j['time'] as num?)?.toInt() ?? 0,
        (j['pos'] as num?)?.toInt() ?? 0,
        (j['dur'] as num?)?.toInt(),
      );
}

/// 收藏与观看记录：全部存在本机
class LibraryStore extends ChangeNotifier {
  late SharedPreferences _p;
  final List<VideoItem> favorites = [];
  final List<HistoryEntry> history = [];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    try {
      final f = _p.getString('favorites');
      if (f != null) {
        favorites.addAll((jsonDecode(f) as List)
            .map((e) => VideoItem.fromJson((e as Map).cast<String, dynamic>())));
      }
      final h = _p.getString('history');
      if (h != null) {
        history.addAll((jsonDecode(h) as List)
            .map((e) => HistoryEntry.fromJson((e as Map).cast<String, dynamic>())));
      }
    } catch (_) {}
  }

  void _save() {
    _p.setString('favorites', jsonEncode(favorites.map((e) => e.toJson()).toList()));
    _p.setString('history', jsonEncode(history.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  bool isFavorite(String key) => favorites.any((v) => v.key == key);

  void toggleFavorite(VideoItem v) {
    if (isFavorite(v.key)) {
      favorites.removeWhere((e) => e.key == v.key);
    } else {
      favorites.insert(0, v);
    }
    _save();
  }

  void addHistory(VideoItem v, int positionMs, int? durationMs) {
    history.removeWhere((e) => e.item.key == v.key);
    history.insert(0, HistoryEntry(v, DateTime.now().millisecondsSinceEpoch, positionMs, durationMs));
    if (history.length > 300) history.removeRange(300, history.length);
    _save();
  }

  int positionOf(String key) {
    for (final e in history) {
      if (e.item.key == key) return e.positionMs;
    }
    return 0;
  }

  void clearHistory() {
    history.clear();
    _save();
  }
}
