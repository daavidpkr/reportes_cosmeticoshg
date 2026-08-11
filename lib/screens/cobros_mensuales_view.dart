import 'package:flutter/material.dart';

import '../services/supabase_reportes_service.dart';
import '../theme/hg_theme.dart';

class CobrosMensualesView extends StatefulWidget {
  const CobrosMensualesView({super.key});

  @override
  State<CobrosMensualesView> createState() => _CobrosMensualesViewState();
}

class _CobrosMensualesViewState extends State<CobrosMensualesView> {
  final _service = SupabaseReportesService();
  late Future<List<CobroMensual>> _cobros;

  @override
  void initState() {
    super.initState();
    _cobros = _service.obtenerCobrosMensuales();
  }

  Future<void> _actualizar() async {
    final consulta = _service.obtenerCobrosMensuales();
    setState(() => _cobros = consulta);
    await consulta;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CobroMensual>>(
        future: _cobros,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _EstadoError(error: snapshot.error, actualizar: _actualizar);
          }
          final cobros = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _actualizar,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              children: [
                Text(
                  'Reporte por cobrar por meses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.hg.panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: cobros.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                'No hay reportes mensuales creados.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.hg.mutedText),
                              ),
                            )
                          : Table(
                              columnWidths: const {
                                0: FlexColumnWidth(1.5),
                                1: FlexColumnWidth(1),
                              },
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: context.hg.tableHeader,
                                  ),
                                  children: const [
                                    _Celda(texto: 'Mes', encabezado: true),
                                    _Celda(
                                      texto: 'Valor por cobrar',
                                      encabezado: true,
                                      alinearDerecha: true,
                                    ),
                                  ],
                                ),
                                ...cobros.map(
                                  (cobro) => TableRow(
                                    children: [
                                      _Celda(texto: cobro.nombre),
                                      _Celda(
                                        texto:
                                            '\$${cobro.valorPorCobrar.toStringAsFixed(2)}',
                                        alinearDerecha: true,
                                        resaltar: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _Celda extends StatelessWidget {
  const _Celda({
    required this.texto,
    this.encabezado = false,
    this.alinearDerecha = false,
    this.resaltar = false,
  });

  final String texto;
  final bool encabezado;
  final bool alinearDerecha;
  final bool resaltar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          texto,
          textAlign: alinearDerecha ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            fontWeight:
                encabezado || resaltar ? FontWeight.w700 : FontWeight.w500,
            color: resaltar ? context.hg.warning : null,
          ),
        ),
      );
}

class _EstadoError extends StatelessWidget {
  const _EstadoError({required this.error, required this.actualizar});

  final Object? error;
  final Future<void> Function() actualizar;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  color: context.hg.danger, size: 36),
              const SizedBox(height: 12),
              const Text('No se pudieron cargar los cobros mensuales.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: actualizar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}
