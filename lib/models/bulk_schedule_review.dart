class BulkScheduleItem {
  const BulkScheduleItem({
    required this.customerId,
    required this.customer,
    required this.commercialName,
    required this.reference,
    required this.invoiceDate,
    required this.classification,
    required this.reason,
    this.termDays,
    this.currentDate,
    this.expectedDate,
    this.differenceDays,
    this.dateSource,
    this.versionToken = '',
    this.balance = 0,
  });
  final String customerId, customer, commercialName, reference;
  final DateTime invoiceDate;
  final int? termDays, differenceDays;
  final DateTime? currentDate, expectedDate;
  final String? dateSource;
  final String versionToken;
  final double balance;
  final String classification, reason;

  factory BulkScheduleItem.fromJson(Map<String, dynamic> json) =>
      BulkScheduleItem(
          customerId: json['customer_id'].toString(),
          customer: json['customer']?.toString() ?? '',
          commercialName: json['commercial_name']?.toString() ?? '',
          reference: json['ref_fact'].toString(),
          invoiceDate: DateTime.parse(json['invoice_date'].toString()),
          termDays: (json['payment_term_days'] as num?)?.toInt(),
          currentDate: _date(json['current_scheduled_date']),
          expectedDate: _date(json['expected_scheduled_date']),
          differenceDays: (json['difference_days'] as num?)?.toInt(),
          dateSource: json['date_source']?.toString(),
          versionToken: json['version_token']?.toString() ?? '',
          balance: (json['balance'] as num?)?.toDouble() ?? 0,
          classification: json['classification'].toString(),
          reason: json['reason']?.toString() ?? 'unknown_source');
}

class BulkScheduleReview {
  const BulkScheduleReview(
      {required this.toleranceDays,
      required this.counts,
      required this.items,
      this.previewId = ''});
  final String previewId;
  final int toleranceDays;
  final Map<String, int> counts;
  final List<BulkScheduleItem> items;

  int count(String key) => counts[key] ?? 0;
  List<BulkScheduleItem> get reviewItems => items
      .where((item) =>
          item.classification == 'manual_review' ||
          item.classification == 'changed_since_preview' ||
          item.classification == 'missing_term')
      .toList();
  List<BulkScheduleItem> get authorizableItems =>
      items.where((item) => item.classification == 'manual_review').toList();

  factory BulkScheduleReview.fromJson(Map<String, dynamic> json) =>
      BulkScheduleReview(
          toleranceDays: (json['tolerance_days'] as num?)?.toInt() ?? 7,
          previewId: json['preview_id']?.toString() ?? '',
          counts: Map<String, dynamic>.from(json['counts'] as Map? ?? const {})
              .map(
                  (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0)),
          items: (json['items'] as List? ?? const [])
              .map((item) => BulkScheduleItem.fromJson(
                  Map<String, dynamic>.from(item as Map)))
              .toList());
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
