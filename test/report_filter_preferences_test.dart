import 'package:cosmeticos_hg_reportes/services/report_filter_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('restaura filtros y orden válidos', () {
    final value = ReportFilterPreferences.fromJson({
      'version': 1,
      'query': ' cliente ',
      'seller': '01 - Ana',
      'status': 'pendientes',
      'paymentTerm': '30',
      'columnFilters': {'referencia': '0001'},
      'sortColumn': 'referencia',
      'sortAscending': false,
    });

    expect(value, isNotNull);
    expect(value!.query, 'cliente');
    expect(value.columnFilters, {'referencia': '0001'});
    expect(value.sortColumn, 'referencia');
    expect(value.sortAscending, isFalse);
  });

  test('descarta versiones, columnas y plazos inválidos', () {
    expect(
      ReportFilterPreferences.fromJson({
        'version': 0,
        'status': 'todos',
        'paymentTerm': '',
        'columnFilters': <String, String>{},
      }),
      isNull,
    );
    expect(
      ReportFilterPreferences.fromJson({
        'version': 1,
        'status': 'todos',
        'paymentTerm': '-1',
        'columnFilters': {'desconocida': 'x'},
      }),
      isNull,
    );
  });

  test('aísla la configuración por usuario y organización', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ReportFilterPreferencesStore();
    await store.save(
      userId: 'user-a',
      organizationId: 'org-a',
      value: const ReportFilterPreferences(query: 'cliente a'),
    );

    expect(
      (await store.load(userId: 'user-a', organizationId: 'org-a'))?.query,
      'cliente a',
    );
    expect(
      await store.load(userId: 'user-a', organizationId: 'org-b'),
      isNull,
    );
    expect(
      await store.load(userId: 'user-b', organizationId: 'org-a'),
      isNull,
    );
  });
}
