import 'dart:developer' as developer;

enum CatalogFileStage {
  metadata,
  signedUrl,
  httpDownload,
  validation,
  cache,
  viewer,
  export,
}

class CatalogFileException implements Exception {
  const CatalogFileException({
    required this.stage,
    required this.userMessage,
    this.httpStatus,
    this.detail,
  });

  final CatalogFileStage stage;
  final String userMessage;
  final int? httpStatus;
  final String? detail;

  @override
  String toString() => detail == null ? userMessage : '$userMessage ($detail)';
}

String sanitizeCatalogError(Object error) {
  var text = error.toString();
  text = text.replaceAll(RegExp(r'https?://\S+'), '[url]');
  text = text.replaceAll(
    RegExp(
      r'(token|apikey|authorization)\s*[:=]\s*(?:bearer\s+)?[^\s,;]+',
      caseSensitive: false,
    ),
    r'$1=[oculto]',
  );
  text = text.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
    '[jwt oculto]',
  );
  if (text.length > 280) text = '${text.substring(0, 280)}…';
  return text;
}

void logCatalogFileError(
  CatalogFileStage stage,
  Object error, {
  int? httpStatus,
  String? catalogId,
}) {
  developer.log(
    'stage=${stage.name} status=${httpStatus ?? '-'} '
    'catalog=${catalogId ?? '-'} error=${sanitizeCatalogError(error)}',
    name: 'catalogos.file',
    level: 1000,
  );
}
