import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/facturas_store.dart';

class CargaFacturasScreen extends StatefulWidget {
  const CargaFacturasScreen({super.key});

  @override
  State<CargaFacturasScreen> createState() => _CargaFacturasScreenState();
}

class _CargaFacturasScreenState extends State<CargaFacturasScreen> {
  final _store = FacturasStore.instance;
  bool _cargando = false;

  Future<void> _seleccionarArchivos() async {
    final resultado = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: const ['xml', 'html', 'htm'],
    );
    if (resultado == null || !mounted) return;

    setState(() => _cargando = true);
    var procesados = 0;
    var rechazados = 0;
    try {
      for (final archivo in resultado.files) {
        try {
          final contenido = kIsWeb
              ? utf8.decode(archivo.bytes!, allowMalformed: true)
              : await File(archivo.path!).readAsString();
          _store.agregarDesdeTexto(contenido) ? procesados++ : rechazados++;
        } catch (_) {
          rechazados++;
        }
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    if (!mounted) return;
    final detalle = rechazados == 0 ? '' : ' · $rechazados sin datos válidos';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$procesados archivo(s) procesado(s)$detalle')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carga de facturas')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_upload, size: 80, color: Colors.pink),
              const SizedBox(height: 20),
              Text(
                'Sube facturas electrónicas en formato XML o HTML',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Se extraerán el cliente, la fecha, el secuencial y el importe total.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (_cargando)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _seleccionarArchivos,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Seleccionar facturas'),
                ),
              const SizedBox(height: 20),
              Text('Facturas en memoria: ${_store.cantidad}'),
            ],
          ),
        ),
      ),
    );
  }
}
