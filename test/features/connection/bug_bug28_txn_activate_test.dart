// test/features/connection/bug_bug28_txn_activate_test.dart
// BUG-28 门禁测试（来源 cr-20260823-1421.md D2，用户裁决"修"，复核分流
// 2026-08-23）。
//
// 缺陷：ConnectionDao.delete（connection_dao.dart:139-144）的 CON-T34
// 自动激活发生在删除事务之外（事务提交后另行 findAll + setActive）。
// 进程在两步间被杀 → 全库零活跃连接。原子性本身无法在单测内注入崩溃，
// 按 BUG-18-INV1 先例以源码结构断言为门禁 + 行为回归锚定终态语义。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  group('BUG-28-S1: delete() 的自动激活必须在事务闭包内完成', () {
    test('结构断言：is_active 处理位于 delete() 的事务块内', () {
      final src =
          File('lib/core/database/dao/connection_dao.dart').readAsStringSync();

      // 截取 delete() 方法体（到 deleteWithoutGuard 声明为止）。
      final start = src.indexOf('Future<bool> delete(int id) async {');
      expect(start, greaterThanOrEqualTo(0), reason: '定位 delete() 方法');
      final end = src.indexOf('Future<bool> deleteWithoutGuard(', start);
      expect(end, greaterThan(start), reason: '定位方法体边界');
      final body = src.substring(start, end);

      final txnStart = body.indexOf('await db.transaction((txn) async {');
      expect(txnStart, greaterThanOrEqualTo(0), reason: 'delete() 必须持有删除事务');
      final txnEnd = body.indexOf('\n    });', txnStart);
      expect(txnEnd, greaterThan(txnStart));
      final txnBlock = body.substring(txnStart, txnEnd);

      // 核心断言（修复前 FAIL）：激活/清零逻辑在事务闭包内。
      expect(txnBlock.contains("'is_active'"), isTrue,
          reason: 'CON-T34 自动激活必须与删行同事务，'
              '否则两步间进程被杀会留下零活跃连接');

      // 否定断言：事务外不得再出现 findAll/setActive 补丁式收尾。
      final afterTxn = body.substring(txnEnd + '\n    });'.length);
      expect(afterTxn.contains('await findAll()'), isFalse,
          reason: '自动激活不得留在事务外');
      expect(afterTxn.contains('await setActive('), isFalse,
          reason: 'setActive 自带独立事务，嵌套使用会脱离删除事务');
    });
  });

  group('BUG-28-S2: deleteWithoutGuard 同构修复（补偿回滚路径零活跃窗口）', () {
    test('结构断言：is_active 处理位于 deleteWithoutGuard() 的事务块内', () {
      final src =
          File('lib/core/database/dao/connection_dao.dart').readAsStringSync();

      final start = src.indexOf('Future<bool> deleteWithoutGuard(');
      expect(start, greaterThanOrEqualTo(0), reason: '定位 deleteWithoutGuard()');
      final end = src.indexOf('Future<int> count(', start);
      final body = src.substring(start, end > start ? end : src.length);

      final txnStart = body.indexOf('await db.transaction((txn) async {');
      expect(txnStart, greaterThanOrEqualTo(0),
          reason: 'deleteWithoutGuard() 必须持有删除事务');
      final txnEnd = body.indexOf('\n    });', txnStart);
      expect(txnEnd, greaterThan(txnStart));
      final txnBlock = body.substring(txnStart, txnEnd);

      // 核心断言：激活逻辑在事务闭包内（与 delete 同款）。
      expect(txnBlock.contains("'is_active'"), isTrue,
          reason: '补偿回滚路径同样不得留下零活跃中间态');

      // 否定断言：事务外不得再出现 findAll/setActive 补丁式收尾。
      final afterTxn = body.substring(txnEnd + '\n    });'.length);
      expect(afterTxn.contains('await findAll()'), isFalse);
      expect(afterTxn.contains('await setActive('), isFalse);

      // 否定断言：BUG-17 赋予它的"无 CON-T32 守卫"语义不得改变。
      final guardPart = body.substring(0, txnStart);
      expect(guardPart.contains('count()'), isFalse,
          reason: 'deleteWithoutGuard 必须保持无 CON-T32 计数守卫（BUG-17-S4）');
    });
  });

  group('BUG-28 行为回归：删除活跃连接后恰好一个活跃（既有语义保持）', () {
    late Database db;
    setUpAll(() {
      initSqfliteFfi();
    });
    setUp(() async {
      db = await openTestDatabase(TestSchema.connections);
    });
    tearDown(() async {
      await db.close();
    });

    test('删除活跃连接 → 其余连接中恰有一个 is_active=1', () async {
      final dao = ConnectionDao();
      final now = DateTime.now();
      ConnectionConfig conn(int id, String name) => ConnectionConfig(
            id: id,
            name: name,
            url: 'http://nas$id.local:5005',
            username: 'u',
            basePath: '/',
            isActive: false,
            createdAt: now,
            updatedAt: now,
          );
      await dao.insert(conn(1, 'a'), passwordKey: 'k1');
      await dao.insert(conn(2, 'b'), passwordKey: 'k2');
      await dao.setActive(1);

      final wasActive = await dao.delete(1);

      expect(wasActive, isTrue);
      final all = await dao.findAll();
      expect(all.length, 1);
      expect(all.single.id, 2);
      expect(all.single.isActive, isTrue, reason: 'CON-T34：删除活跃连接后必须自动激活另一连接');
    });
  });
}
