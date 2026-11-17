import 'package:flutter/material.dart';
import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/store_screen.dart';

void main() => runApp(const StockCheckApp());

class StockCheckApp extends StatefulWidget {
  const StockCheckApp({super.key});
  @override
  State<StockCheckApp> createState() => _StockCheckAppState();
}

class _StockCheckAppState extends State<StockCheckApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Check',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F5FA8),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.ready) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!state.loggedIn) return LoginScreen(state: state);
          // Store selection is mandatory: nothing else is reachable without it.
          if (state.warehouse == null) return StoreScreen(state: state);
          return ScanScreen(state: state);
        },
      ),
    );
  }
}
