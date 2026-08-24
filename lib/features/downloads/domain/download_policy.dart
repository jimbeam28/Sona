// lib/features/downloads/domain/download_policy.dart
// DL-01-S4 pure filename-policy surface.
//
// The implementations are single-sourced in core/services so the download
// engine (core layer) and this feature share one body without a core→feature
// import; this file re-exports them for feature-side consumers. Purity
// contract: zero IO imports (file existence is injected as the existsProbe
// callback of [resolveCollision]) and zero pattern literals.

export '../../../core/services/download_filename_policy.dart'
    show kMaxDownloadBaseNameLength, resolveCollision, sanitizeBaseName;
