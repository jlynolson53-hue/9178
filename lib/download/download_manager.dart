import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../core/settings.dart';
import '../models/video.dart';
import 'aes.dart';
import 'download_task.dart';
import 'hls.dart';

class _Paused implements Exception {}

/// 下载引擎：任务队列 + 并发 + 断点续传 + m3u8（AES-128）+ 合并 MP4
class DownloadManager extends ChangeNotifier {
  final Settings settings;
  DownloadManager(this.settings);

  final List<DownloadTask> tasks = [];
  final Map<String, CancelToken> _tokens = {};
  late Directory _workRoot; // 临时分片目录
  late File _dbFile;
  Timer? _notifyTimer;
  bool _dirty = false;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
    },
  ));

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _workRoot = Directory(p.join(support.path, 'dl_work'))..createSync(recursive: true);
    _dbFile = File(p.join(support.path, 'tasks.json'));
    if (_dbFile.existsSync()) {
      try {
        final list = jsonDecode(_dbFile.readAsStringSync()) as List;
        for (final e in list) {
          final t = DownloadTask.fromJson((e as Map).cast<String, dynamic>());
          // 上次退出时还在下载的，统一改成暂停，由用户继续（断点续传）
          if (t.active) t.status = TaskStatus.paused;
          tasks.add(t);
        }
      } catch (_) {}
    }
  }

  // ---------------- 对外接口 ----------------

  Future<String> defaultSaveDir() async {
    final ext = await getExternalStorageDirectory();
    final base = ext ?? await getApplicationDocumentsDirectory();
    return p.join(base.path, 'PexDL');
  }

  Future<String> saveDir() async => settings.saveDir ?? await defaultSaveDir();

  /// 批量添加，返回实际新增数量（已存在且未失败的会跳过）
  int addAll(List<(VideoItem, VideoStream)> list) {
    var n = 0;
    for (final (item, stream) in list) {
      final dup = tasks.any((t) => t.url == stream.url && t.status != TaskStatus.failed);
      if (dup) continue;
      tasks.insert(
        0,
        DownloadTask(
          id: '${DateTime.now().microsecondsSinceEpoch}_$n',
          item: item,
          url: stream.url,
          kind: stream.kind,
          qualityLabel: stream.label,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      n++;
    }
    _changed(immediate: true);
    _pump();
    return n;
  }

  void pause(DownloadTask t) {
    if (t.status == TaskStatus.queued || t.status == TaskStatus.running) {
      t.status = TaskStatus.paused;
      _tokens.remove(t.id)?.cancel('paused');
      t.speed = 0;
      _changed(immediate: true);
      _pump();
    }
  }

  void resume(DownloadTask t) {
    if (t.status == TaskStatus.paused || t.status == TaskStatus.failed) {
      t.status = TaskStatus.queued;
      t.error = null;
      _changed(immediate: true);
      _pump();
    }
  }

  void pauseAll() {
    for (final t in tasks) {
      pause(t);
    }
  }

  void resumeAll() {
    for (final t in tasks) {
      if (t.status == TaskStatus.paused || t.status == TaskStatus.failed) {
        t.status = TaskStatus.queued;
        t.error = null;
      }
    }
    _changed(immediate: true);
    _pump();
  }

  Future<void> remove(DownloadTask t, {bool deleteFile = false}) async {
    _tokens.remove(t.id)?.cancel('removed');
    tasks.remove(t);
    final work = Directory(p.join(_workRoot.path, t.id));
    if (work.existsSync()) await work.delete(recursive: true);
    if (deleteFile && t.outputPath != null) {
      final f = File(t.outputPath!);
      if (f.existsSync()) await f.delete();
    }
    _changed(immediate: true);
    _pump();
  }

  void clearFinished() {
    tasks.removeWhere((t) => t.status == TaskStatus.done);
    _changed(immediate: true);
  }

  // ---------------- 调度 ----------------

  void _pump() {
    final running = tasks.where((t) => t.status == TaskStatus.running || t.status == TaskStatus.merging).length;
    var slots = settings.maxTasks - running;
    if (slots <= 0) return;
    // 先加入的先下载（列表是倒序插入的）
    for (final t in tasks.reversed.toList()) {
      if (slots <= 0) break;
      if (t.status == TaskStatus.queued) {
        slots--;
        _run(t);
      }
    }
  }

  Future<void> _run(DownloadTask t) async {
    t.status = TaskStatus.running;
    t.error = null;
    final token = CancelToken();
    _tokens[t.id] = token;
    _changed(immediate: true);
    try {
      final work = Directory(p.join(_workRoot.path, t.id))..createSync(recursive: true);
      final outDir = Directory(await saveDir())..createSync(recursive: true);
      final baseName = sanitizeFileName('${t.item.title}_${t.item.id.hashCode.toUnsigned(32)}');
      if (t.kind == StreamKind.hls) {
        await _runHls(t, token, work, outDir, baseName);
      } else {
        await _runMp4(t, token, work, outDir, baseName);
      }
      t.status = TaskStatus.done;
      t.speed = 0;
      if (work.existsSync()) await work.delete(recursive: true);
    } on _Paused {
      // 已暂停，保留临时文件以便续传
    } catch (e) {
      if (token.isCancelled || t.status == TaskStatus.paused) {
        // 暂停导致的取消
      } else {
        t.status = TaskStatus.failed;
        t.error = _errText(e);
        t.speed = 0;
      }
    } finally {
      _tokens.remove(t.id);
      _changed(immediate: true);
      _pump();
    }
  }

  String _errText(Object e) {
    if (e is DioException) {
      final c = e.response?.statusCode;
      if (c != null) return 'HTTP $c';
      return e.message ?? e.type.name;
    }
    if (e is FileSystemException) return '写入失败：${e.message}（检查保存目录权限）';
    return e.toString();
  }

  void _checkPaused(DownloadTask t, CancelToken token) {
    if (token.isCancelled || t.status == TaskStatus.paused || !tasks.contains(t)) {
      throw _Paused();
    }
  }

  // ---------------- MP4（HTTP Range 断点续传） ----------------

  Future<void> _runMp4(DownloadTask t, CancelToken token, Directory work, Directory outDir, String baseName) async {
    final part = File(p.join(work.path, 'video.part'));
    var have = part.existsSync() ? part.lengthSync() : 0;

    final resp = await _dio.get<ResponseBody>(
      t.url,
      cancelToken: token,
      options: Options(
        responseType: ResponseType.stream,
        headers: have > 0 ? {'Range': 'bytes=$have-'} : null,
        validateStatus: (s) => s != null && (s == 200 || s == 206 || s == 416),
      ),
    );
    final code = resp.statusCode ?? 200;
    if (code == 416) {
      // 已经下载完整
    } else {
      if (code == 200 && have > 0) {
        have = 0; // 服务器不支持 Range，从头下载
      }
      final len = int.tryParse(resp.headers.value('content-length') ?? '') ?? 0;
      t.total = len > 0 ? have + len : 0;
      t.received = have;
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var lastBytes = have;
      var lastTime = DateTime.now();
      try {
        await for (final chunk in resp.data!.stream) {
          sink.add(chunk);
          t.received += chunk.length;
          final now = DateTime.now();
          final dt = now.difference(lastTime).inMilliseconds;
          if (dt >= 800) {
            t.speed = (t.received - lastBytes) * 1000 / dt;
            lastBytes = t.received;
            lastTime = now;
            _changed();
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      _checkPaused(t, token);
      if (t.total > 0 && part.lengthSync() < t.total) {
        throw Exception('下载不完整，请重试（会自动续传）');
      }
    }
    final ext = _extOf(t.url, 'mp4');
    final out = await _uniqueFile(outDir, baseName, ext);
    await _moveFile(part, out);
    t.outputPath = out.path;
    t.total = t.received = out.lengthSync();
  }

  String _extOf(String url, String def) {
    final e = p.extension(Uri.tryParse(url)?.path ?? '').replaceFirst('.', '').toLowerCase();
    return (e.isNotEmpty && e.length <= 4) ? e : def;
  }

  // ---------------- HLS / m3u8 ----------------

  Future<void> _runHls(DownloadTask t, CancelToken token, Directory work, Directory outDir, String baseName) async {
    final planFile = File(p.join(work.path, 'plan.json'));
    List<HlsSegment> segs;
    String? mapUrl;

    if (planFile.existsSync()) {
      final j = jsonDecode(planFile.readAsStringSync()) as Map<String, dynamic>;
      segs = (j['segs'] as List).map((e) => HlsSegment.fromJson((e as Map).cast<String, dynamic>())).toList();
      mapUrl = j['map'] as String?;
    } else {
      var url = t.url;
      var pl = parseM3u8(await _getText(url, token), Uri.parse(url));
      var depth = 0;
      while (pl.isMaster) {
        if (pl.variants.isEmpty || ++depth > 3) throw Exception('m3u8 主列表里没有可用清晰度');
        url = chooseVariant(pl.variants, settings.preferQuality).url;
        pl = parseM3u8(await _getText(url, token), Uri.parse(url));
      }
      if (pl.unsupported != null) throw Exception(pl.unsupported);
      segs = pl.segments;
      mapUrl = pl.mapUrl;
      planFile.writeAsStringSync(jsonEncode({
        'segs': segs.map((e) => e.toJson()).toList(),
        'map': mapUrl,
      }));
    }

    t.segTotal = segs.length;
    String segPath(int i) => p.join(work.path, 'seg_${i.toString().padLeft(6, '0')}.ts');

    // 统计已完成分片（断点续传）
    t.segDone = 0;
    t.received = 0;
    for (var i = 0; i < segs.length; i++) {
      final f = File(segPath(i));
      if (f.existsSync()) {
        t.segDone++;
        t.received += f.lengthSync();
      }
    }
    _changed();

    final keyCache = <String, Uint8List>{};
    Future<Uint8List> getKey(String uri) async {
      final c = keyCache[uri];
      if (c != null) return c;
      final r = await _dio.get<List<int>>(uri,
          cancelToken: token, options: Options(responseType: ResponseType.bytes));
      final k = Uint8List.fromList(r.data!);
      if (k.length != 16) throw Exception('AES 密钥长度异常（${k.length} 字节）');
      keyCache[uri] = k;
      return k;
    }

    var next = 0;
    var lastBytes = t.received;
    var lastTime = DateTime.now();

    Future<void> worker() async {
      while (true) {
        _checkPaused(t, token);
        if (next >= segs.length) return;
        final i = next++;
        final out = File(segPath(i));
        if (out.existsSync()) continue;
        final s = segs[i];

        Uint8List? data;
        Object? lastErr;
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            final headers = <String, dynamic>{};
            if (s.rangeLength != null) {
              final st = s.rangeStart ?? 0;
              headers['Range'] = 'bytes=$st-${st + s.rangeLength! - 1}';
            }
            final r = await _dio.get<List<int>>(s.url,
                cancelToken: token,
                options: Options(responseType: ResponseType.bytes, headers: headers));
            data = Uint8List.fromList(r.data!);
            break;
          } catch (e) {
            if (token.isCancelled) throw _Paused();
            lastErr = e;
            await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          }
        }
        if (data == null) throw lastErr ?? Exception('分片 $i 下载失败');

        if (s.keyUri != null) {
          final key = await getKey(s.keyUri!);
          data = await compute(_decryptJob, [data, key, s.iv()]);
        }
        final tmp = File('${out.path}.tmp');
        await tmp.writeAsBytes(data, flush: true);
        await tmp.rename(out.path); // 写完再改名：存在即代表完整

        t.segDone++;
        t.received += data.length;
        final now = DateTime.now();
        final dt = now.difference(lastTime).inMilliseconds;
        if (dt >= 800) {
          t.speed = (t.received - lastBytes) * 1000 / dt;
          lastBytes = t.received;
          lastTime = now;
        }
        _changed();
      }
    }

    final n = settings.segConcurrency.clamp(1, 16);
    await Future.wait(List.generate(n, (_) => worker()));
    _checkPaused(t, token);

    // ---- 合并 ----
    t.status = TaskStatus.merging;
    t.speed = 0;
    _changed(immediate: true);

    final isFmp4 = mapUrl != null;
    final joined = File(p.join(work.path, isFmp4 ? 'joined.mp4' : 'joined.ts'));
    final sink = joined.openWrite();
    try {
      if (isFmp4) {
        final r = await _dio.get<List<int>>(mapUrl!,
            cancelToken: token, options: Options(responseType: ResponseType.bytes));
        sink.add(r.data!);
      }
      for (var i = 0; i < segs.length; i++) {
        sink.add(await File(segPath(i)).readAsBytes());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    File result = joined;
    String ext = isFmp4 ? 'mp4' : 'ts';
    if (!isFmp4 && settings.mergeToMp4) {
      final mp4 = File(p.join(work.path, 'out.mp4'));
      if (mp4.existsSync()) mp4.deleteSync();
      final session = await FFmpegKit.executeWithArguments([
        '-y', '-i', joined.path, '-map', '0', '-c', 'copy',
        '-bsf:a', 'aac_adtstoasc', '-movflags', '+faststart', mp4.path,
      ]);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && mp4.existsSync() && mp4.lengthSync() > 0) {
        result = mp4;
        ext = 'mp4';
      } else {
        // 转封装失败时保留 .ts（大多数播放器都能播放）
        t.error = '转 MP4 失败，已保存为 .ts';
      }
    }
    final out = await _uniqueFile(outDir, baseName, ext);
    await _moveFile(result, out);
    t.outputPath = out.path;
    t.received = out.lengthSync();
    t.segDone = t.segTotal;
  }

  Future<String> _getText(String url, CancelToken token) async {
    final r = await _dio.get<String>(url,
        cancelToken: token, options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  // ---------------- 文件工具 ----------------

  Future<File> _uniqueFile(Directory dir, String base, String ext) async {
    var f = File(p.join(dir.path, '$base.$ext'));
    var i = 1;
    while (f.existsSync()) {
      f = File(p.join(dir.path, '${base}_$i.$ext'));
      i++;
    }
    return f;
  }

  Future<void> _moveFile(File from, File to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      // 跨存储分区不能直接改名：复制后删除
      await from.copy(to.path);
      await from.delete();
    }
  }

  // ---------------- 持久化与刷新 ----------------

  void _changed({bool immediate = false}) {
    _dirty = true;
    if (immediate) {
      _flush();
      return;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 400), _flush);
  }

  void _flush() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
    try {
      _dbFile.writeAsStringSync(jsonEncode(tasks.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

Uint8List _decryptJob(List<Uint8List> a) => aes128Decrypt(a[0], a[1], a[2]);
