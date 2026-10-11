import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'rc_controller_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Blocca lo schermo in Landscape (Orizzontale)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Attiva lo schermo intero totale nascondendo le barre di Android
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      //Forza il tema chiaro per disattivare la Dark Mode del telefono
      themeMode: ThemeMode.light, 
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5), // Sfondo Grigio Chiaro / Bianco Ghiaccio
      ),
      //theme: ThemeData.dark().copyWith(
      //  scaffoldBackgroundColor: const Color(0xFF141519), // Grigio scuro di fondo hi-tech
      //),
      home: RcControllerPage(),
    );
  }
}
