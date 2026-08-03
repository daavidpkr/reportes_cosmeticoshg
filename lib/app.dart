import 'package:flutter/material.dart';

import 'screens/reporte_screen.dart';

class CosmeticosHGApp extends StatelessWidget {
  const CosmeticosHGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosméticos HG - Reportes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        useMaterial3: true,
      ),
      home: const ReporteScreen(),
    );
  }
}
