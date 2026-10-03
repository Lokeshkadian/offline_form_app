import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/record_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/home_screen.dart';
import 'services/server_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ServerConfig.load();

  final recordProvider = RecordProvider();
  await recordProvider.loadRecords();

  final syncProvider = SyncProvider(recordProvider: recordProvider)
    ..startMonitoring();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: recordProvider),
        ChangeNotifierProvider.value(value: syncProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Form App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}
