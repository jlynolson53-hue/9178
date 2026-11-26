import '../core/settings.dart';
import 'direct_link_source.dart';
import 'pexels_source.dart';
import 'video_source.dart';

class SourceRegistry {
  final Settings settings;
  late final List<VideoSource> all;

  SourceRegistry(this.settings) {
    all = [PexelsSource(settings), DirectLinkSource(settings)];
  }

  VideoSource get current => byId(settings.sourceId);

  VideoSource byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);
}
