String _two(int v) => v.toString().padLeft(2, '0');

String fmtDuration(int? sec) {
  if (sec == null || sec < 0) return '';
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

String fmtPos(Duration d) => fmtDuration(d.inSeconds);

String fmtBytes(int? b) {
  if (b == null || b <= 0) return '--';
  const u = ['B', 'KB', 'MB', 'GB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

String fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.month}-${d.day} ${_two(d.hour)}:${_two(d.minute)}';
}

String sanitizeFileName(String s) {
  var r = s.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
  if (r.length > 80) r = r.substring(0, 80);
  return r.isEmpty ? 'video' : r;
}
