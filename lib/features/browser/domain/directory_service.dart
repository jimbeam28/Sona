// lib/features/browser/domain/directory_service.dart
// Sort option state + sortFiles 顶层函数（DirectoryService 类已删除，REF-06）。
// Zero Flutter dependencies — pure Dart.

import 'package:state_notifier/state_notifier.dart';

import '../../../shared/models/nas_file.dart';

/// Sort orders for the file/directory list.
enum SortOption {
  /// Sort by name in ascending alphabetical order (A-Z).
  nameAsc,

  /// Sort by name in descending alphabetical order (Z-A).
  nameDesc,

  /// Sort by last-modified time, newest first.
  modifiedDesc,
}

/// REF-01-A6: domain abstraction for persisting the sort option — the
/// provider layer supplies a SharedPreferences-backed implementation.
abstract class ISortOptionPersist {
  /// Reads the persisted sort option name, or null when never stored.
  String? readSortOption();

  /// Persists the sort option under its enum name.
  void writeSortOption(String name);
}

/// Manages the current sort option, persisting through [ISortOptionPersist].
class SortOptionNotifier extends StateNotifier<SortOption> {
  final ISortOptionPersist? _persist;
  SortOptionNotifier(this._persist) : super(SortOption.nameAsc) {
    final persist = _persist;
    if (persist != null) {
      final saved = persist.readSortOption();
      if (saved != null) {
        state = SortOption.values.cast<SortOption?>().firstWhere(
            (e) => e!.name == saved,
            orElse: () => SortOption.nameAsc)!;
      }
    }
  }
  void setOption(SortOption option) {
    if (state == option) return;
    state = option;
    _persist?.writeSortOption(option.name);
  }
}

/// Returns a new list sorted according to [option].
///
/// Directories always appear before files regardless of the sort option
/// (BRW-T42).  Within each group entries are ordered by the selected
/// criterion.
List<NasFile> sortFiles(List<NasFile> files, SortOption option) {
  final sorted = files.toList();
  sorted.sort((a, b) {
    // Directories always first
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    // Within the same category, apply the selected sort
    switch (option) {
      case SortOption.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortOption.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
      case SortOption.modifiedDesc:
        final aTime = a.modifiedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.modifiedAt?.millisecondsSinceEpoch ?? 0;
        return bTime.compareTo(aTime); // newest first
    }
  });
  return sorted;
}
