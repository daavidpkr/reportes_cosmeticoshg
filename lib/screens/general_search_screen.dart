import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/invoice_batch_importer.dart';

/// Paged organization-scoped invoice lookup. The table intentionally contains
/// no buyer identification; that value is an internal import-only identity.
class GeneralSearchScreen extends StatefulWidget {
  const GeneralSearchScreen({super.key});

  @override
  State<GeneralSearchScreen> createState() => _GeneralSearchScreenState();
}

class _GeneralSearchScreenState extends State<GeneralSearchScreen> {
  static const _pageSize = 50;
  final _controller = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  bool _hasMore = true;
  final _rows = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load(replace: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _load(replace: true));
    setState(() {});
  }

  Future<void> _load({required bool replace}) async {
    if (_loading || (!replace && !_hasMore)) return;
    final generation = ++_generation;
    final query = _controller.text.replaceAll(RegExp(r'\s+'), '').trim();
    setState(() => _loading = true);
    try {
      final from = replace ? 0 : _rows.length;
      var request = Supabase.instance.client
          .from('facturas_maestras')
          .select('ref_fact,nro_fact,cliente,nombre_comercial,fecha,venta');
      if (query.isNotEmpty) {
        final safe = query.replaceAll(',', ' ');
        request = request.or(
            'ref_fact.ilike.%$safe%,nro_fact.ilike.%$safe%,cliente.ilike.%$safe%,nombre_comercial.ilike.%$safe%');
      }
      final value = await request.range(from, from + _pageSize - 1);
      if (!mounted || generation != _generation) {
        return;
      }
      final page = List<Map<String, dynamic>>.from(value);
      final target = replace ? page : [..._rows, ...page];
      target.sort((a, b) => compareInvoiceReferences(
          a['ref_fact']?.toString() ?? '', b['ref_fact']?.toString() ?? ''));
      setState(() {
        _rows
          ..clear()
          ..addAll(target);
        _hasMore = page.length == _pageSize;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo buscar facturas.')));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Búsqueda general',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: InputDecoration(
                  hintText:
                      'Buscar por referencia, factura, cliente o nombre comercial',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            _load(replace: true);
                          }))),
          const SizedBox(height: 12),
          if (_loading && _rows.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rows.isEmpty)
            const Expanded(child: Center(child: Text('No existen resultados.')))
          else
            Expanded(
                child: ListView(children: [
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                      columns: const [
                        DataColumn(label: Text('REF.')),
                        DataColumn(label: Text('FACTURA')),
                        DataColumn(label: Text('CLIENTE')),
                        DataColumn(label: Text('NOMBRE COMERCIAL')),
                        DataColumn(label: Text('FECHA')),
                        DataColumn(label: Text('VENTA'))
                      ],
                      rows: _rows
                          .map((row) => DataRow(cells: [
                                DataCell(
                                    Text(row['ref_fact']?.toString() ?? '')),
                                DataCell(
                                    Text(row['nro_fact']?.toString() ?? '')),
                                DataCell(
                                    Text(row['cliente']?.toString() ?? '')),
                                DataCell(Text(
                                    row['nombre_comercial']?.toString() ?? '')),
                                DataCell(Text(row['fecha']?.toString() ?? '')),
                                DataCell(Text(
                                    '\$${(row['venta'] as num?)?.toStringAsFixed(2) ?? '0.00'}'))
                              ]))
                          .toList())),
              if (_hasMore)
                Center(
                    child: TextButton.icon(
                        onPressed:
                            _loading ? null : () => _load(replace: false),
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.expand_more),
                        label: const Text('Cargar más'))),
            ])),
        ]),
      );
}
