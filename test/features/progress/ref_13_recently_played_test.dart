// test/features/progress/ref_13_recently_played_test.dart
// REF-13 门禁测试（spec docs/features/REF-13.md §5.4 指定文件）。
//
// 锚定删除 upsert/clear 对 recentlyPlayedProvider 的无效 invalidate：
//   - S5 invalidate 集收敛：progress_provider.dart 中 recentlyPlayedProvider(
//     调用（除定义）零命中；progressForFileProvider 与 latestPlayedProgressProvider
//     invalidate 各 ≥1 处
//   - S6 写路径行为回归：upsert/clear 后 progressForFile/latestPlayed 仍刷新
//   - INV1 写路径 invalidate 集 == 真实订阅面
//   - INV2 recentlyPlayedProvider 查询能力保留（DAO getRecentlyPlayed + 定义 + di re-export）

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/progress_dao.dart';
import 'package:nas_audio_player/features/progress/progress_provider.dart';

import '../../helpers/test_database.dart';

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  group('REF-13: 删除 recentlyPlayedProvider 无效 invalidate', () {
    test('REF-13-S5: progress_provider.dart 中 recentlyPlayedProvider( 零命中（除定义）',
        () {
      final content = File(
              '${Directory.current.path}/lib/features/progress/progress_provider.dart')
          .readAsStringSync();

      // 定义形态存在（INV2 保留）
      expect(content, contains('final recentlyPlayedProvider'),
          reason: 'INV2: recentlyPlayedProvider 定义必须保留');

      // invalidate(recentlyPlayedProvider(...)) 调用零命中（已删除）
      expect(
          RegExp(r'ref\.invalidate\(recentlyPlayedProvider\(')
              .allMatches(content)
              .length,
          0,
          reason: 'invalidate(recentlyPlayedProvider(...)) 调用必须全部删除');
    });

    test(
        'REF-13-S5: progressForFileProvider / latestPlayedProgressProvider invalidate 各 ≥1',
        () {
      final content = File(
              '${Directory.current.path}/lib/features/progress/progress_provider.dart')
          .readAsStringSync();

      expect(
          RegExp(r'ref\.invalidate\(progressForFileProvider\(')
              .allMatches(content)
              .length,
          greaterThanOrEqualTo(1),
          reason: 'progressForFileProvider 的 invalidate 必须保留（真实订阅方）');
      expect(
          RegExp(r'ref\.invalidate\(latestPlayedProgressProvider\)')
              .allMatches(content)
              .length,
          greaterThanOrEqualTo(1),
          reason: 'latestPlayedProgressProvider 的 invalidate 必须保留（启动恢复）');
    });

    test('REF-13-S5 REF-13-INV2: progress_dao.dart 仍含 getRecentlyPlayed', () {
      final content = File(
              '${Directory.current.path}/lib/core/database/dao/progress_dao.dart')
          .readAsStringSync();
      expect(content, contains('getRecentlyPlayed'),
          reason: 'INV2: DAO getRecentlyPlayed 查询能力必须保留');
    });

    test('REF-13-S5 REF-13-INV2: shared/di 仍 re-export recentlyPlayedProvider',
        () {
      final content =
          File('${Directory.current.path}/lib/shared/di/providers.dart')
              .readAsStringSync();
      expect(content, contains('recentlyPlayedProvider'),
          reason: 'INV2: shared/di re-export 必须保留（未来功能位）');
    });

    test('REF-13-S6: upsert 后 progressForFileProvider 刷新返回新值', () async {
      final db = await openTestDatabase(TestSchema.progress);
      addTearDown(() async => db.close());
      await seedConnection(db);
      final dao = ProgressDao();

      final container = ProviderContainer(overrides: [
        progressDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);

      // 初始无进度
      final before = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/a.mp3'))
              .future);
      expect(before, isNull);

      // upsert 一条 ≥5s 的进度
      container.read(upsertProgressProvider)(
        connectionId: 1,
        filePath: '/a.mp3',
        positionMs: 30000,
        durationMs: 120000,
      );

      // 轮询等待异步-void 写入落库（upsert provider 返回 void，无法直接 await）
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        final p = await dao.find(1, '/a.mp3');
        if (p != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // 刷新后返回新值（S6：progressForFile 仍被 invalidate）
      final after = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/a.mp3'))
              .future);
      expect(after, isNotNull,
          reason: 'upsert 后 progressForFileProvider 应刷新返回新值');
      expect(after!.positionMs, 30000);
    });

    test('REF-13-S6: clear 后 progressForFileProvider 刷新返回 null', () async {
      final db = await openTestDatabase(TestSchema.progress);
      addTearDown(() async => db.close());
      await seedConnection(db);
      final dao = ProgressDao();

      final container = ProviderContainer(overrides: [
        progressDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);

      // 先存一条（轮询等待落库）
      container.read(upsertProgressProvider)(
        connectionId: 1,
        filePath: '/a.mp3',
        positionMs: 30000,
        durationMs: 120000,
      );
      final deadline0 = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline0)) {
        final p = await dao.find(1, '/a.mp3');
        if (p != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // clear
      container.read(clearProgressProvider)(
        connectionId: 1,
        filePath: '/a.mp3',
      );
      final deadline1 = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline1)) {
        final p = await dao.find(1, '/a.mp3');
        if (p == null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // 刷新后为 null（S6：clear 后 progressForFile 仍被 invalidate）
      final after = await container.read(
          progressForFileProvider((connectionId: 1, filePath: '/a.mp3'))
              .future);
      expect(after, isNull,
          reason: 'clear 后 progressForFileProvider 应刷新为 null');
    });

    test('REF-13-S6: latestPlayedProgressProvider 在 upsert 后刷新', () async {
      final db = await openTestDatabase(TestSchema.progress);
      addTearDown(() async => db.close());
      await seedConnection(db);
      final dao = ProgressDao();

      final container = ProviderContainer(overrides: [
        progressDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);

      final before = await container.read(latestPlayedProgressProvider.future);
      expect(before, isNull);

      container.read(upsertProgressProvider)(
        connectionId: 1,
        filePath: '/a.mp3',
        positionMs: 30000,
        durationMs: 120000,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        final p = await dao.find(1, '/a.mp3');
        if (p != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(Duration.zero);

      final after = await container.read(latestPlayedProgressProvider.future);
      expect(after, isNotNull,
          reason: 'latestPlayedProgressProvider 刷新面保留（启动恢复）');
      expect(after!.filePath, '/a.mp3');
    });

    test('REF-13-INV1: 全 lib 无 recentlyPlayedProvider 的 watch/read 消费', () {
      // 全 lib 扫描：recentlyPlayedProvider 只应出现在定义与 re-export，
      // 不得有任何 watch/read 消费
      final core = Directory('${Directory.current.path}/lib');
      final consumers = <String>[];
      core.listSync(recursive: true).whereType<File>().where((f) {
        return f.path.endsWith('.dart');
      }).forEach((f) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('watch(recentlyPlayedProvider') ||
              lines[i].contains('read(recentlyPlayedProvider')) {
            consumers.add('${f.path}:${i + 1}');
          }
        }
      });

      expect(consumers, isEmpty,
          reason: 'INV1: recentlyPlayedProvider 不得有 watch/read 消费方');
    });
  });
}
