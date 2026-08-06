// test/helpers/fake_progress_dao.dart
// Shared in-memory FakeProgressDao (REF-02-S11).
//
// Implements the IProgressDao contract (post-REF-02 surface, rawInsert 已移出
// 契约) — 纯 Dart 内存实现，无 SQLite 依赖。用于 ProgressService 构造注入：
// REF-02 后 ProgressService({required IProgressDao dao}) 不再有无参默认值，
// 只测 notifier 状态机（不碰 DAO）的用例注入本 fake 即可。

import 'package:nas_audio_player/core/contracts/database_contract.dart';
import 'package:nas_audio_player/shared/models/play_progress.dart';

/// Minimal in-memory [IProgressDao] backed by a (connectionId, filePath) map.
class FakeProgressDao implements IProgressDao {
  final Map<(int, String), PlayProgress> _store = {};

  @override
  Future<bool?> upsert({
    required int connectionId,
    required String filePath,
    required int positionMs,
    int? durationMs,
  }) async {
    _store[(connectionId, filePath)] = PlayProgress(
      connectionId: connectionId,
      filePath: filePath,
      positionMs: positionMs,
      durationMs: durationMs,
      lastPlayedAt: DateTime.now(),
    );
    return true;
  }

  @override
  Future<void> delete(int connectionId, String filePath) async {
    _store.remove((connectionId, filePath));
  }

  @override
  Future<PlayProgress?> find(int connectionId, String filePath) async {
    return _store[(connectionId, filePath)];
  }

  @override
  Future<PlayProgress?> findLatest() async {
    final all = _store.values.toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return all.isEmpty ? null : all.first;
  }

  @override
  Future<List<PlayProgress>> getRecentlyPlayed({int limit = 20}) async {
    final all = _store.values.toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return all.take(limit).toList();
  }

  @override
  Future<List<PlayProgress>> findByConnection(int connectionId) async {
    return _store.values.where((p) => p.connectionId == connectionId).toList();
  }

  @override
  Future<void> deleteByConnection(int connectionId) async {
    _store.removeWhere((key, _) => key.$1 == connectionId);
  }

  @override
  Future<int> count() async => _store.length;
}
