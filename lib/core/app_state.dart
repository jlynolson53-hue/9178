import '../download/download_manager.dart';
import '../sources/source_registry.dart';
import 'library_store.dart';
import 'settings.dart';

/// 全局单例（参考 FocuBili 的“本机数据 + 模块化服务”思路，这里用最简单的 ChangeNotifier 实现）
late final Settings settings;
late final LibraryStore libraryStore;
late final SourceRegistry sources;
late final DownloadManager downloads;

Future<void> initAppState() async {
  settings = Settings();
  await settings.load();
  libraryStore = LibraryStore();
  await libraryStore.load();
  sources = SourceRegistry(settings);
  downloads = DownloadManager(settings);
  await downloads.init();
}
