import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  late SharedPreferences _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
  }

  String get apiKey => _p.getString('apiKey') ?? '';
  set apiKey(String v) {
    _p.setString('apiKey', v.trim());
    notifyListeners();
  }

  String get sourceId => _p.getString('sourceId') ?? 'pexels';
  set sourceId(String v) {
    _p.setString('sourceId', v);
    notifyListeners();
  }

  /// null 表示使用默认目录
  String? get saveDir => _p.getString('saveDir');
  set saveDir(String? v) {
    if (v == null || v.isEmpty) {
      _p.remove('saveDir');
    } else {
      _p.setString('saveDir', v);
    }
    notifyListeners();
  }

  /// highest / hd / sd
  String get preferQuality => _p.getString('preferQuality') ?? 'hd';
  set preferQuality(String v) {
    _p.setString('preferQuality', v);
    notifyListeners();
  }

  int get maxTasks => _p.getInt('maxTasks') ?? 2;
  set maxTasks(int v) {
    _p.setInt('maxTasks', v);
    notifyListeners();
  }

  int get segConcurrency => _p.getInt('segConcurrency') ?? 6;
  set segConcurrency(int v) {
    _p.setInt('segConcurrency', v);
    notifyListeners();
  }

  bool get mergeToMp4 => _p.getBool('mergeToMp4') ?? true;
  set mergeToMp4(bool v) {
    _p.setBool('mergeToMp4', v);
    notifyListeners();
  }

  List<Map<String, String>> get directLinks {
    final raw = _p.getString('directLinks');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void addDirectLink(String title, String url) {
    final l = directLinks..removeWhere((e) => e['url'] == url);
    l.insert(0, {'title': title, 'url': url});
    _p.setString('directLinks', jsonEncode(l));
    notifyListeners();
  }

  void removeDirectLink(String url) {
    final l = directLinks..removeWhere((e) => e['url'] == url);
    _p.setString('directLinks', jsonEncode(l));
    notifyListeners();
  }
}
