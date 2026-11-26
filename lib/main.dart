import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppState();
  runApp(const PexApp());
}

class PexApp extends StatelessWidget {
  const PexApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorSchemeSeed: const Color(0xFF05A081),
          brightness: b,
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'PexDL',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}
