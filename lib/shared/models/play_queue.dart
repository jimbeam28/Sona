// lib/shared/models/play_queue.dart
// Data model for the audio playback queue.
// 相等性规则与登记：见 equality_registry.dart（REF-02）
//
// The queue holds an ordered list of audio files and tracks which file is
// currently being played.  It is built by the Browser module (BRW-04) when
// the user taps an audio file, and consumed by the Player module.
//
// PLY-05: 播放队列管理 — adds PlayMode support and queue-navigation logic
// (nextIndex / previousIndex) so the Player module can implement skip-to-next,
// skip-to-previous, and mode-aware queue wrapping.

import 'dart:math';

import '../../features/player/domain/play_mode.dart' show PlayMode;
import '../../features/player/domain/play_mode.dart' as play_mode;
import 'nas_file.dart';

// Re-export PlayMode so existing consumers importing play_queue.dart
// continue to work without changes.
export '../../features/player/domain/play_mode.dart' show PlayMode;

/// Represents a sequential play queue of audio files.
///
/// [files] contains only audio (non-directory) entries, ordered by the
/// current directory sort.  [currentIndex] points to the file that should
/// start playing first.
///
/// [startPositionMs] is an optional resume position (milliseconds).  When
/// non-null the Player module should seek to this position before starting
/// playback.
///
/// [playMode] controls what happens when a track ends (sequential by default).
///
/// When [playMode] is [PlayMode.shuffle], [_shuffleOrder] holds a Fisher-Yates
/// permutation of all indices so that each track plays exactly once per cycle
/// and prev/next are deterministic.
class PlayQueue {
  final List<NasFile> files;
  final int currentIndex;
  final int? startPositionMs;
  final PlayMode playMode;
  final List<int>? _shuffleOrder;
  final int? _shufflePosition;

  /// Creates a [PlayQueue].  When [playMode] is [PlayMode.shuffle], a
  /// Fisher-Yates permutation of [0 .. files.length-1] is generated (seeded
  /// with [random] for testability).  The optional [_shuffleOrder] and
  /// [_shufflePosition] are used when restoring a persisted queue.
  PlayQueue({
    required this.files,
    required this.currentIndex,
    this.startPositionMs,
    this.playMode = PlayMode.sequential,
    List<int>? shuffleOrder,
    int? shufflePosition,
    Random? random,
  })  : _shuffleOrder = shuffleOrder ??
            (playMode == PlayMode.shuffle && files.length > 1
                ? _generateShuffleOrder(files.length, random ?? Random())
                : null),
        _shufflePosition = shufflePosition ??
            (playMode == PlayMode.shuffle && files.length > 1 ? 0 : null);

  /// Fisher-Yates shuffle returning a random permutation of [0 .. n-1].
  static List<int> _generateShuffleOrder(int n, Random rng) {
    final order = List<int>.generate(n, (i) => i);
    for (int i = n - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    return order;
  }

  /// Public Fisher-Yates permutation generator (BUG-04-S2/S3).
  ///
  /// Lets the orchestration layer reshuffle a fresh round when the current
  /// permutation is exhausted, without reaching into private state.
  static List<int> generateShuffleOrder(int n, Random rng) =>
      _generateShuffleOrder(n, rng);

  /// The file currently being played.
  NasFile get current => files[currentIndex];

  /// Whether there is another file after the current one.
  bool get hasNext => currentIndex < files.length - 1;

  /// Whether there is a file before the current one.
  bool get hasPrevious => currentIndex > 0;

  /// Total number of audio files in the queue.
  int get length => files.length;

  /// Returns a copy of this queue with a different [playMode].
  ///
  /// Entering [PlayMode.shuffle] generates a fresh Fisher-Yates permutation
  /// and locates [_shufflePosition] on the current track's slot within it
  /// (`order[pos] == currentIndex`) — the same invariant maintained by
  /// [withIndex] (BUG-04-S4), [fromMap] (BUG-14 normalisation) and the
  /// orchestration-layer round regeneration, so the pointer can never
  /// desynchronise from the current track.  [currentIndex] is structurally
  /// part of a fresh permutation (it covers `0 .. files.length-1`), hence no
  /// BUG-04-S4-style end-of-order degradation is needed here.
  ///
  /// Leaving shuffle clears the permutation and pointer, keeping the model
  /// invariant `_shuffleOrder != null ⟺ playMode == PlayMode.shuffle`: a
  /// persisted non-shuffle queue never carries a stale order, and switching
  /// back to shuffle later always starts a fresh round (new-queue semantics).
  ///
  /// Idempotent: returns `this` when [mode] == [playMode], so repeated mode
  /// toggles never reshuffle a running round.
  PlayQueue withMode(PlayMode mode, {Random? random}) {
    if (mode == playMode) return this;
    if (mode == PlayMode.shuffle && files.length > 1) {
      final order = generateShuffleOrder(files.length, random ?? Random());
      return PlayQueue(
        files: files,
        currentIndex: currentIndex,
        startPositionMs: startPositionMs,
        playMode: mode,
        shuffleOrder: order,
        shufflePosition: order.indexOf(currentIndex),
      );
    }
    return PlayQueue(
      files: files,
      currentIndex: currentIndex,
      startPositionMs: startPositionMs,
      playMode: mode,
      // Non-shuffle target (or single-track shuffle): null order/position so
      // the constructor keeps them cleared.
      shuffleOrder: null,
      shufflePosition: null,
    );
  }

  /// Returns a copy of this queue with a different [currentIndex].
  ///
  /// BUG-04-S4 (cr-20260724-0110 MDL4): in shuffle mode [_shufflePosition]
  /// is relocated to the position of [newIndex] within the shuffle order, so
  /// a manual track selection can never desynchronise [currentIndex] from
  /// the shuffle pointer (the pre-fix behaviour replayed the just-selected
  /// track on "next").  When [newIndex] is not part of the current
  /// permutation (e.g. a track inserted via [insertAfterCurrent], which is
  /// deliberately excluded from the running round), the pointer degrades to
  /// the END of the order — the next [advanceShuffle] then reports the round
  /// as exhausted and the orchestration layer reshuffles a fresh round.
  PlayQueue withIndex(int newIndex) {
    int? newPos = _shufflePosition;
    final order = _shuffleOrder;
    if (order != null) {
      final idx = order.indexOf(newIndex);
      newPos = idx >= 0 ? idx : order.length - 1;
      if (newPos < 0) newPos = null;
    }
    return PlayQueue(
      files: files,
      currentIndex: newIndex,
      startPositionMs: startPositionMs,
      playMode: playMode,
      shuffleOrder: _shuffleOrder,
      shufflePosition: newPos,
    );
  }

  /// Returns a copy of this queue with a different [startPositionMs].
  PlayQueue withStartPosition(int? ms) => PlayQueue(
        files: files,
        currentIndex: currentIndex,
        startPositionMs: ms,
        playMode: playMode,
        shuffleOrder: _shuffleOrder,
        shufflePosition: _shufflePosition,
      );

  /// Returns a copy of this queue with the track at [index] removed.
  ///
  /// Adjusts [currentIndex] so it still points to the same logical track:
  /// - If the removed track is before [currentIndex], decrement
  /// - If the removed track IS [currentIndex], keep the same index (the next
  ///   track shifts into this position) unless it was the last track
  ///
  /// BUG-24 (cr-20260823-1421 F2): in shuffle mode the running permutation is
  /// REMAPPED, not regenerated — every surviving index is shifted so it keeps
  /// pointing at the same logical track, and the pointer stays anchored on
  /// [currentIndex] (`order[pos] == currentIndex`, the same invariant kept by
  /// [withIndex]/[fromMap]/[insertAfterCurrent]).  The old regenerate-on-
  /// remove behaviour desynchronised the pointer (fresh order with position
  /// 0), making "next" replay the current track and "previous" jump randomly.
  /// Single-track remnants keep the no-permutation convention.
  PlayQueue withoutIndex(int index) {
    final newList = files.toList();
    newList.removeAt(index);
    if (newList.isEmpty) {
      return PlayQueue(
        files: newList,
        currentIndex: 0,
        startPositionMs: null,
        playMode: playMode,
      );
    }
    int newIndex = currentIndex;
    if (index < currentIndex) {
      newIndex = currentIndex - 1;
    } else if (index == currentIndex) {
      if (currentIndex >= newList.length) {
        newIndex = newList.length - 1;
      }
    }
    List<int>? newOrder;
    int? newPos;
    if (playMode == PlayMode.shuffle &&
        newList.length > 1 &&
        _shuffleOrder != null) {
      // BUG-24-ALG1: drop the removed slot, shift every surviving index that
      // sat right of it, then re-anchor the pointer on the new current slot.
      newOrder = _shuffleOrder
          .where((i) => i != index)
          .map((i) => i > index ? i - 1 : i)
          .toList();
      final anchor = newOrder.indexOf(newIndex);
      newPos = anchor >= 0 ? anchor : newOrder.length - 1;
    }
    return PlayQueue(
      files: newList,
      currentIndex: newIndex,
      startPositionMs: index == currentIndex ? null : startPositionMs,
      playMode: playMode,
      shuffleOrder: newOrder,
      shufflePosition: newPos,
    );
  }

  /// Returns a copy of this queue with [file] inserted immediately after
  /// the current track (at `currentIndex + 1`).
  ///
  /// [currentIndex] is preserved (still points to the same logical track).
  /// BUG-04-S1: the shuffle order is remapped — every entry greater than
  /// [currentIndex] is shifted by one, so the permutation keeps pointing at
  /// the same logical tracks and nothing is skipped or duplicated.  The
  /// newly inserted file is NOT added to the running shuffle round (it
  /// joins the next reshuffled round).  No de-duplication is performed:
  /// repeated inserts of the same [file] produce repeated copies.
  PlayQueue insertAfterCurrent(NasFile file) {
    final newFiles = files.toList()..insert(currentIndex + 1, file);
    List<int>? newOrder = _shuffleOrder;
    if (newOrder != null) {
      newOrder = newOrder.map((i) => i > currentIndex ? i + 1 : i).toList();
    }
    return PlayQueue(
      files: newFiles,
      currentIndex: currentIndex,
      startPositionMs: startPositionMs,
      playMode: playMode,
      shuffleOrder: newOrder,
      shufflePosition: _shufflePosition,
    );
  }

  /// Returns a copy of this queue with the track at [from] relocated to
  /// index [to].
  ///
  /// PLY-01: pure display-order reorder for non-shuffle queues. The current
  /// track follows the move: relocating the current track itself moves the
  /// pointer to [to]; otherwise the pointer compensates for the shift so it
  /// keeps pointing at the same logical track (ALG1, docs/features/PLY-01.md
  /// §6).
  ///
  /// Defensive short-circuits return `this` unchanged (zero-copy): from ==
  /// to, out-of-range indices, single-track queue, and shuffle mode — the
  /// shuffle permutation is a second coordinate system a display-order move
  /// cannot remap consistently (PLY-01-INV3 model gate; UI gate = S8).
  ///
  /// Single-writer discipline (PLY-01-INV2): production callers must go
  /// through `PlaybackOrchestrator.moveTrack`; UI code never calls this
  /// directly (same constraint as [insertAfterCurrent]).
  PlayQueue move(int from, int to) {
    if (from == to ||
        from < 0 ||
        from >= files.length ||
        to < 0 ||
        to >= files.length ||
        files.length <= 1 ||
        playMode == PlayMode.shuffle) {
      return this;
    }
    final movedFile = files[from];
    final newFiles = files.toList()
      ..removeAt(from)
      ..insert(to, movedFile);
    // ALG1: newList = files..removeAt(from)..insert(to,f);
    // from==c → to; else tempC = c-(from<c?1:0), newC = tempC+(tempC>=to?1:0)
    final int newCurrent;
    if (from == currentIndex) {
      newCurrent = to;
    } else {
      final tempC = currentIndex - (from < currentIndex ? 1 : 0);
      newCurrent = tempC + (tempC >= to ? 1 : 0);
    }
    return PlayQueue(
      files: newFiles,
      currentIndex: newCurrent,
      startPositionMs: startPositionMs,
      playMode: playMode,
      shuffleOrder: _shuffleOrder,
      shufflePosition: _shufflePosition,
    );
  }

  // ── Queue navigation (PLY-05) ──────────────────────────────────────────

  /// Returns the index of the next track in shuffle order, or `null` when
  /// there is no next track in the current mode.
  ///
  /// For [PlayMode.shuffle] this advances through the Fisher-Yates
  /// permutation.  The caller should use [withIndex] to persist the new
  /// position.
  int? nextShuffleIndex() {
    final order = _shuffleOrder;
    final pos = _shufflePosition;
    if (order == null || pos == null || pos >= order.length - 1) return null;
    return order[pos + 1];
  }

  /// Returns the index of the previous track in shuffle history.
  int? previousShuffleIndex() {
    final order = _shuffleOrder;
    final pos = _shufflePosition;
    if (order == null || pos == null || pos <= 0) return null;
    return order[pos - 1];
  }

  /// Advances [_shufflePosition] by one and returns a new queue.
  /// Returns `null` when already at the end of the shuffle order.
  PlayQueue? advanceShuffle() {
    final order = _shuffleOrder;
    final pos = _shufflePosition;
    if (order == null || pos == null || pos >= order.length - 1) return null;
    final newPos = pos + 1;
    return PlayQueue(
      files: files,
      currentIndex: order[newPos],
      startPositionMs: null,
      playMode: playMode,
      shuffleOrder: order,
      shufflePosition: newPos,
    );
  }

  /// Goes back one step in shuffle history and returns a new queue.
  /// Returns `null` when already at the start of the shuffle order.
  PlayQueue? retreatShuffle() {
    final order = _shuffleOrder;
    final pos = _shufflePosition;
    if (order == null || pos == null || pos <= 0) return null;
    final newPos = pos - 1;
    return PlayQueue(
      files: files,
      currentIndex: order[newPos],
      startPositionMs: null,
      playMode: playMode,
      shuffleOrder: order,
      shufflePosition: newPos,
    );
  }

  /// Returns the index of the next track given [mode], or `null` when
  /// playback should stop (sequential mode at end of queue).
  ///
  /// [current] is the current index (0-based).  [length] is the number of
  /// items in the queue.  [random] is used for shuffle mode; if not
  /// provided a default [Random] is used.  Providing a seeded [Random]
  /// makes the function deterministic for testing.
  ///
  /// PLY-T32 (sequential at end → null), PLY-T33 (repeatAll wraps),
  /// PLY-T34 (shuffle returns different index), PLY-T35 (repeatOne).
  /// Delegates to [play_mode.nextIndex] in domain/play_mode.dart.
  ///
  /// Kept as a static method on PlayQueue for backward compatibility.
  static int? nextIndex(int current, int length, PlayMode mode,
          {Random? random}) =>
      play_mode.nextIndex(current, length, mode, random: random);

  /// Delegates to [play_mode.previousIndex] in domain/play_mode.dart.
  ///
  /// Kept as a static method on PlayQueue for backward compatibility.
  static int? previousIndex(int current, int length, PlayMode mode,
          {Random? random}) =>
      play_mode.previousIndex(current, length, mode, random: random);

  // ── Persistence helpers (PLY-T37) ───────────────────────────────────────

  /// Serialises this queue to a JSON-compatible map.
  ///
  /// File identities are stored as paths; the caller is responsible for
  /// reconstructing [NasFile] objects on deserialisation.
  /// Shuffle order is persisted so restored queues retain the same sequence.
  Map<String, dynamic> toMap() => {
        'filePaths': files.map((f) => f.path).toList(),
        'currentIndex': currentIndex,
        'startPositionMs': startPositionMs,
        'playMode': playMode.name,
        if (_shuffleOrder != null) 'shuffleOrder': _shuffleOrder,
        if (_shufflePosition != null) 'shufflePosition': _shufflePosition,
      };

  /// Reconstructs a [PlayQueue] from a previously-serialised map and a
  /// list of resolved [NasFile] objects.
  ///
  /// The [files] list must be provided externally because [NasFile]
  /// carries metadata that cannot be serialised inline (it is rebuilt from
  /// the file system or cache on app restart).
  factory PlayQueue.fromMap(Map<String, dynamic> map, List<NasFile> files) {
    final modeName = map['playMode'] as String?;
    final mode = modeName != null
        ? PlayMode.values.firstWhere((m) => m.name == modeName,
            orElse: () => PlayMode.sequential)
        : PlayMode.sequential;
    final currentIndex = map['currentIndex'] as int? ?? 0;
    final shuffleOrderRaw = map['shuffleOrder'] as List<dynamic>?;
    final shuffleOrder = shuffleOrderRaw
        ?.map((e) => (e as num).toInt())
        .where((e) => e >= 0 && e < files.length)
        .toList();
    // BUG-14 robustness: normalise the restored position so it can never
    // point outside the (possibly filtered) permutation.  The OOB filter
    // above may shrink the order when files were deleted from the NAS
    // between persist and restore; an out-of-bounds position would make
    // advanceShuffle/retreatShuffle index outside the list (RangeError).
    // Degradation: relocate to the current track's slot when it is still in
    // the order, otherwise to the end of the order (no crash, sequence
    // continues from a consistent state).
    var shufflePosition = map['shufflePosition'] as int?;
    if (shuffleOrder == null) {
      shufflePosition = null;
    } else if (shuffleOrder.isEmpty) {
      shufflePosition = 0;
    } else if (shufflePosition == null ||
        shufflePosition < 0 ||
        shufflePosition >= shuffleOrder.length) {
      final relocated = shuffleOrder.indexOf(currentIndex);
      shufflePosition = relocated >= 0 ? relocated : shuffleOrder.length - 1;
    }
    return PlayQueue(
      files: files,
      currentIndex: currentIndex,
      startPositionMs: map['startPositionMs'] as int?,
      playMode: mode,
      shuffleOrder: shuffleOrder,
      shufflePosition: shufflePosition,
    );
  }

  @override
  String toString() =>
      'PlayQueue(files: ${files.length}, currentIndex: $currentIndex, '
      'startPositionMs: $startPositionMs, playMode: $playMode)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayQueue &&
          _listEquals(files, other.files) &&
          currentIndex == other.currentIndex &&
          startPositionMs == other.startPositionMs &&
          playMode == other.playMode &&
          _listEquals(_shuffleOrder, other._shuffleOrder) &&
          _shufflePosition == other._shufflePosition;

  @override
  int get hashCode => Object.hash(
      Object.hashAll(files),
      currentIndex,
      startPositionMs,
      playMode,
      Object.hashAll(_shuffleOrder ?? const []),
      _shufflePosition);
}

/// Shallow list equality helper used by [PlayQueue.==].
/// Both [a] and [b] may be null; two nulls are considered equal.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
