// test/features/connection/bug_bug17_repro_test.dart
// BUG-17: save() 原子性只覆盖步骤 2 —— 步骤 4/5 失败留下共享临时 key 的孤儿行
// （spec: docs/features/BUG-17.md §5.4，来源 cr-20260816-0804 F4）
//
// 缺陷：connection_service.dart:38-65 save()：
//   const tempKey = 'connection_password_temp';          // :42 共享常量
//   final id = await _dao.insert(config, passwordKey: tempKey);   // 步骤1
//   try { await safeStorageWrite(_storage, key: permanentKey, value: password); }
//   catch (_) { await _dao.delete(id); rethrow; }        // :49-55 只包步骤2
//   await _dao.update(savedConfig, passwordKey: permanentKey);   // 步骤4 :57-59
//   await _dao.setActive(id);                             // 步骤5 :62
// 步骤 4/5 失败无回滚：DB 行已存在且 password 列引用共享常量
// 'connection_password_temp'，密码却已写入该 id 的永久 key → 半保存状态
// （storage 已写但 DB 引用悬空；多条孤儿行共享 temp key，删任一行会连带
// 失效其它孤儿行的密码引用——safeStorageDelete :121）。对比 update()
// （BUG-24-S2）为此专门做了 storage 回滚（:85-101）。
//
// 门禁（修复前必须 FAIL）：
//   BUG-17-S1: 步骤 4（dao.update）失败 → save 抛错后不得残留孤儿行与
//              永久 key —— 当前代码行残留 → FAIL
//   BUG-17-S2: 步骤 5（dao.setActive）失败 → 同上 —— 当前 FAIL

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/database/dao/connection_dao.dart';
import 'package:nas_audio_player/features/connection/domain/connection_service.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_factories.dart';

/// 注入"第 N 类 DAO 调用抛错"的包装 DAO —— 步骤 4（update）/ 步骤 5
/// （setActive）失败注入。
class _ThrowingDao extends ConnectionDao {
  bool throwOnUpdate = false;
  bool throwOnSetActive = false;

  @override
  Future<int> update(ConnectionConfig config,
      {required String passwordKey}) async {
    if (throwOnUpdate) throw Exception('模拟 DAO update 失败');
    return super.update(config, passwordKey: passwordKey);
  }

  @override
  Future<void> setActive(int id) async {
    if (throwOnSetActive) throw Exception('模拟 DAO setActive 失败');
    return super.setActive(id);
  }
}

void main() {
  setUpAll(() {
    initSqfliteFfi();
  });

  Future<({Database db, _ThrowingDao dao, FakeSecureStorage storage})>
      _setup() async {
    final db = await openTestDatabase(TestSchema.connections);
    final dao = _ThrowingDao();
    // 预置一条连接（同 REF-22-T02 理由：回滚 delete 不触发
    // LastConnectionException）。
    await dao.insert(
        testConfig(name: 'Pre-existing', url: 'http://pre.local:5005'),
        passwordKey: 'key_pre');
    final storage = FakeSecureStorage();
    return (db: db, dao: dao, storage: storage);
  }

  test('BUG-17-S1: 步骤 4（update）失败 → 无孤儿行、无永久 key 残留', () async {
    final ctx = await _setup();
    addTearDown(() => ctx.db.close());

    ctx.dao.throwOnUpdate = true;
    final service = ConnectionService(ctx.dao, ctx.storage);

    // When: 保存新连接，步骤 4（_dao.update :59）抛错。
    await expectLater(
      service.save(
          config: testConfig(name: 'New NAS', url: 'http://new.local:5005'),
          password: 'secret'),
      throwsException,
      reason: '前置：save 必须把 DAO 异常上抛给调用方',
    );

    // Then: DB 不得残留孤儿行（password='connection_password_temp'），
    // 永久 key 也不得残留。
    final all = await ctx.dao.findAll();
    expect(all.length, equals(1), reason: '步骤 4 失败后必须全量回滚（只留预置行）');
    expect(all.first.name, equals('Pre-existing'));
    expect(ctx.storage.peek('connection_password_2'), isNull,
        reason: 'BUG-17（cr-20260816-0804 F4）：save 回滚只包步骤 2'
            '（connection_service.dart:49-55）——步骤 4/5 失败时 DB 行残留且'
            'password 列引用共享常量 connection_password_temp（:42），密码却'
            '已写入永久 key connection_password_2（:48-50）→ 半保存孤儿行，'
            '列表可见、删除任一孤儿行会连带失效其它孤儿行的密码引用。'
            '必须对齐 update 的 BUG-24-S2 模式全量回滚（删行 + 删永久 key）。');
  });

  test('BUG-17-S2: 步骤 5（setActive）失败 → 无孤儿行、无永久 key 残留', () async {
    final ctx = await _setup();
    addTearDown(() => ctx.db.close());

    ctx.dao.throwOnSetActive = true;
    final service = ConnectionService(ctx.dao, ctx.storage);

    await expectLater(
      service.save(
          config: testConfig(name: 'New NAS', url: 'http://new.local:5005'),
          password: 'secret'),
      throwsException,
      reason: '前置：save 必须把 DAO 异常上抛给调用方',
    );

    final all = await ctx.dao.findAll();
    expect(all.length, equals(1), reason: '步骤 5 失败后必须全量回滚（只留预置行）');
    expect(ctx.storage.peek('connection_password_2'), isNull,
        reason: 'BUG-17：步骤 5（_dao.setActive :62）失败无回滚 —— 同 S1'
            '的孤儿行问题，且 is_active 未置位。');
  });
}
