enum CatalogFilter { all, newItems, updated }

enum CatalogStatus { borrador, publicado }

class Catalog {
  const Catalog({
    required this.id,
    required this.organizationId,
    required this.title,
    required this.version,
    required this.status,
    required this.active,
    required this.order,
    required this.createdAt,
    required this.updatedAt,
    this.filePath,
    this.coverPath,
    this.pageCount,
    this.publishedAt,
    this.publicUpdatedAt,
    this.isNew = false,
    this.isUpdated = false,
  });

  final String id;
  final String organizationId;
  final String title;
  final String? filePath;
  final String? coverPath;
  final int version;
  final int? pageCount;
  final CatalogStatus status;
  final bool active;
  final int order;
  final DateTime? publishedAt;
  final DateTime? publicUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isNew;
  final bool isUpdated;

  String get expectedFilePath => '$organizationId/$id/v$version/catalogo.pdf';

  bool get hasExpectedFilePath => filePath == expectedFilePath;

  bool get canOpen => status == CatalogStatus.publicado && hasExpectedFilePath;

  bool get filePending => !canOpen;

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
        id: json['id'].toString(),
        organizationId: json['organization_id'].toString(),
        title: json['titulo']?.toString() ?? '',
        filePath: json['archivo_path']?.toString(),
        coverPath: json['portada_path']?.toString(),
        version: (json['version'] as num?)?.toInt() ?? 1,
        pageCount: (json['numero_paginas'] as num?)?.toInt(),
        status: json['estado'] == 'publicado'
            ? CatalogStatus.publicado
            : CatalogStatus.borrador,
        active: json['activo'] == true,
        order: (json['orden'] as num?)?.toInt() ?? 0,
        publishedAt: _date(json['fecha_publicacion']),
        publicUpdatedAt: _date(json['fecha_actualizacion']),
        createdAt:
            _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt:
            _date(json['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        isNew: json['es_nuevo'] == true,
        isUpdated: json['es_actualizado'] == true,
      );

  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'id': id,
        'organization_id': organizationId,
        'titulo': title,
        'archivo_path': filePath,
        'portada_path': coverPath,
        'version': version,
        'numero_paginas': pageCount,
        'estado': status.name,
        'activo': active,
        'orden': order,
        'fecha_publicacion': publishedAt?.toIso8601String(),
        'fecha_actualizacion': publicUpdatedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'es_nuevo': isNew,
        'es_actualizado': isUpdated,
      };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
}

String safeCatalogFileName(String title, int version) {
  final clean = title
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[. ]+$'), '');
  final base = clean.isEmpty ? 'catalogo' : clean;
  return '$base-v$version.pdf';
}

bool catalogMatchesFilter(Catalog catalog, CatalogFilter filter) =>
    switch (filter) {
      CatalogFilter.all => true,
      CatalogFilter.newItems => catalog.isNew,
      CatalogFilter.updated => catalog.isUpdated,
    };

bool isValidPdfBytes(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2D;
