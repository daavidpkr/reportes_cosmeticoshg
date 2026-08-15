import 'package:flutter/material.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    required this.monthLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onRefresh,
    super.key,
  });
  final String monthLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (_, constraints) {
        final navigation = Row(children: [
          IconButton(
              tooltip: 'Mes anterior',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: Text(monthLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700))),
          IconButton(
              tooltip: 'Mes siguiente',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right)),
        ]);
        final actions = Row(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton(onPressed: onToday, child: const Text('Hoy')),
          IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh)),
        ]);
        if (constraints.maxWidth < 520) {
          return Column(children: [
            navigation,
            Align(alignment: Alignment.centerRight, child: actions)
          ]);
        }
        return Row(children: [
          Expanded(child: navigation),
          const SizedBox(width: 4),
          actions
        ]);
      });
}
