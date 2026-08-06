// test/shared/model_equality_test.dart
// 共享模型值相等性测试（REF-07 ConnectionConfig ==/hashCode；
// TEST-10 各模型 ==/hashCode 缺口也落此文件）。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/shared/models/connection_config.dart';

ConnectionConfig _base({
  int? id = 1,
  String name = 'NAS',
  String url = 'http://nas.local:5005',
  String username = 'admin',
  String basePath = '/dav',
  bool isActive = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return ConnectionConfig(
    id: id,
    name: name,
    url: url,
    username: username,
    basePath: basePath,
    isActive: isActive,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  group('REF-07: ConnectionConfig ==/hashCode', () {
    test('REF-07-S1: 所有字段相同 → 相等且 hashCode 一致', () {
      final a = _base();
      final b = _base();
      expect(a == b, isTrue);
      expect(a.hashCode, equals(b.hashCode));
      expect(identical(a, b), isFalse, reason: '非同一实例但值相等');
    });

    test('REF-07-S1: 与自身比较相等（identical 短路）', () {
      final a = _base();
      expect(a == a, isTrue);
    });

    test('REF-07-S1: 与非 ConnectionConfig 比较不等', () {
      final a = _base();
      expect(a == 'string', isFalse);
      expect(a == null, isFalse);
    });

    test('REF-07-S2: id 不同 → 不等', () {
      expect(_base(id: 1) == _base(id: 2), isFalse);
    });

    test('REF-07-S2: id null 与 非null 不等，双 null 相等', () {
      expect(_base(id: null) == _base(id: 1), isFalse);
      expect(_base(id: null) == _base(id: null), isTrue);
    });

    test('REF-07-S2: name 不同 → 不等', () {
      expect(_base(name: 'A') == _base(name: 'B'), isFalse);
    });

    test('REF-07-S2: url 不同 → 不等', () {
      expect(_base(url: 'http://a.local') == _base(url: 'http://b.local'),
          isFalse);
    });

    test('REF-07-S2: username 不同 → 不等', () {
      expect(_base(username: 'u1') == _base(username: 'u2'), isFalse);
    });

    test('REF-07-S2: basePath 不同 → 不等', () {
      expect(_base(basePath: '/dav') == _base(basePath: '/'), isFalse);
    });

    test('REF-07-S2: isActive 不同 → 不等', () {
      expect(_base(isActive: false) == _base(isActive: true), isFalse);
    });

    test('REF-07-S2: createdAt 不同 → 不等', () {
      expect(
          _base(createdAt: DateTime(2026, 1, 1)) ==
              _base(createdAt: DateTime(2026, 1, 2)),
          isFalse);
    });

    test('REF-07-S2: updatedAt 不同 → 不等', () {
      expect(
          _base(updatedAt: DateTime(2026, 1, 1)) ==
              _base(updatedAt: DateTime(2026, 1, 2)),
          isFalse);
    });

    test('REF-07-INV2: 相等对象 hashCode 一致，不等对象 hash 一致性自洽', () {
      final a = _base();
      final b = _base();
      final c = _base(name: 'Other');
      expect(a.hashCode, equals(b.hashCode));
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });
}
