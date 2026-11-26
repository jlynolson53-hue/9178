import 'package:flutter/material.dart';

import '../core/app_state.dart';
import 'downloads_page.dart';
import 'mine_page.dart';
import 'search_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [SearchPage(), DownloadsPage(), MinePage()],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final running = downloads.tasks.where((t) => t.active).length;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: running > 0,
                  label: Text('$running'),
                  child: const Icon(Icons.download_outlined),
                ),
                label: '下载',
              ),
              const NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
            ],
          );
        },
      ),
    );
  }
}
