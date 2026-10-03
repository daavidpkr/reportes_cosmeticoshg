import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const reportFilterColumns = <String>{
  'referencia',
  'cliente',
  'nombre',
  'fecha',
  'factura',
  'vendedor',
  'venta',
  'saldo',
};

class ReportFilterPreferences {
  const ReportFilterPreferences({
    this.query = '',
    this.seller = '',
    this.status = 'todos',
    this.paymentTerm = '',
    this.columnFilters = const {},
    this.sortColumn,
    this.sortAscending = true,
  });

  final String query;
  final String seller;
  final String status;
  final String paymentTerm;
  final Map<String, String> columnFilters;
  final String? sortColumn;
  final bool sortAscending;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'query': query,
        'seller': seller,
        'status': status,
        'paymentTerm': paymentTerm,
        'columnFilters': columnFilters,
        'sortColumn': sortColumn,
        'sortAscending': sortAscending,
      };

  static ReportFilterPreferences? fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['version'] != 1) return null;
    final status = value['status'];
    final paymentTerm = value['paymentTerm'];
    final rawFilters = value['columnFilters'];
    final sortColumn = value['sortColumn'];
    if (status is! String ||
        !const {'todos', 'pagados', 'pendientes', 'anuladas'}
            .contains(status) ||
        paymentTerm is! String ||
        !_validPaymentTerm(paymentTerm) ||
        rawFilters is! Map ||
        (sortColumn != null &&
            (sortColumn is! String ||
                !reportFilterColumns.contains(sortColumn)))) {
      return null;
    }
    final filters = <String, String>{};
    for (final entry in rawFilters.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          !reportFilterColumns.contains(entry.key) ||
          (entry.value as String).trim().isEmpty) {
        return null;
      }
      filters[entry.key as String] = (entry.value as String).trim();
    }
    return ReportFilterPreferences(
      query: value['query'] is String ? (value['query'] as String).trim() : '',
      seller:
          value['seller'] is String ? (value['seller'] as String).trim() : '',
      status: status,
      paymentTerm: paymentTerm,
      columnFilters: filters,
      sortColumn: sortColumn as String?,
      sortAscending: value['sortAscending'] is bool
          ? value['sortAscending'] as bool
          : true,
    );
  }

  static bool _validPaymentTerm(String value) {
    if (value.isEmpty || value == 'sin_establecer') return true;
    final days = int.tryParse(value);
    return days != null && days >= 0 && days <= 3650;
  }
}

class ReportFilterPreferencesStore {
  static const _prefix = 'report_filters_v2';

  Future<ReportFilterPreferences?> load({
    required String userId,
    required String organizationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(userId, organizationId));
    if (raw == null) return null;
    try {
      final parsed = ReportFilterPreferences.fromJson(jsonDecode(raw));
      if (parsed == null) {
        await preferences.remove(_key(userId, organizationId));
      }
      return parsed;
    } on FormatException {
      await preferences.remove(_key(userId, organizationId));
      return null;
    }
  }

  Future<void> save({
    required String userId,
    required String organizationId,
    required ReportFilterPreferences value,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key(userId, organizationId),
      jsonEncode(value.toJson()),
    );
  }

  Future<void> clear({
    required String userId,
    required String organizationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(userId, organizationId));
  }

  String _key(String userId, String organizationId) =>
      '$_prefix:$organizationId:$userId';
}
