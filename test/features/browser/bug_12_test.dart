// test/features/browser/bug_12_test.dart
// BUG-12 门禁测试（来源：docs/cr/cr-20260724-0110.md NET3；spec：docs/features/BUG-12.md，
// 测试文件位置为 spec §5.4 指定）
//
// 缺陷：normaliseWebDavUrl 调 Uri.parse 无 try/catch，非法端口输入
// （192.168.1.100:50o5，0/o 键相邻极易误触）在表单 validator 回调中直接抛
// FormatException——Debug 红屏；Release 异常被框架吞掉，保存/测试按钮死寂。
//
// 修复：normaliseWebDavUrl 内 try/catch 包住 Uri.parse/replace，异常时返回
// 原串（已补 scheme），交后续 isValidWebDavUrl 出友好错误——与同文件
// isValidWebDavUrl 的既有防御策略对齐。
//
// 添加页（connection_screen）与编辑页（connection_edit_screen）共用同一
// ConnectionForm 部件，URL 字段的 validator 统一为 validateUrl
// （connection_form.dart），本门禁锚定该端到端路径。
// 修复前 FAIL（直接抛 FormatException），修复后 PASS。

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_audio_player/core/network/webdav_client.dart';
import 'package:nas_audio_player/features/connection/domain/connection_validator.dart';

void main() {
  group('BUG-12-S1: 非法端口不抛异常，转友好校验错误', () {
    test('normaliseWebDavUrl 非法端口返回原串不抛异常（spec 边界裁决）', () {
      String? result;
      expect(() => result = normaliseWebDavUrl('http://x:abc'), returnsNormally,
          reason: '修复前 Uri.parse 在此抛 FormatException（NET3 缺陷行为）；'
              '修复后内部捕获，交后续校验出友好错误');
      expect(result, equals('http://x:abc'),
          reason: '异常时返回原串（已含 scheme 的输入原样返回）');
    });

    test('spec U1：192.168.1.100:50o5（0/o 误触）→ 友好错误而非崩溃', () {
      final error = validateUrl('192.168.1.100:50o5');

      expect(error, isNotNull, reason: '必须走校验错误路径；修复前此调用抛 FormatException');
      expect(error, contains('请输入有效的服务器地址'),
          reason: '两个表单页共用 ConnectionForm，URL validator 即 validateUrl，'
              '非法端口必须落到友好文案而非异常');
    });

    test('http://x:abc 端到端同样被校验拒绝', () {
      expect(validateUrl('http://x:abc'), isNotNull);
    });

    test('否定断言：合法 URL 的归一化结果不变', () {
      expect(normaliseWebDavUrl('http://192.168.1.100:5005'),
          equals('http://192.168.1.100:5005'),
          reason: '带端口合法 URL 原样返回，try/catch 不得改变合法路径行为');
      expect(normaliseWebDavUrl('192.168.1.100'),
          equals('http://192.168.1.100:5005'),
          reason: '裸 IP 仍正常补 scheme + 默认端口');
      expect(validateUrl('http://192.168.1.100:5005'), isNull,
          reason: '合法 URL 不得被误拒');
    });
  });

  group('BUG-12-INV1: normaliseWebDavUrl 对任何输入不抛异常', () {
    test('畸形/恶意输入电池 → 全部正常返回', () {
      const inputs = [
        'http://x:abc', // 非法端口字符（NET3 原文）
        '192.168.1.100:50o5', // 0/o 键误触（spec U1）
        'http://:::invalid:::', // 完全非法（spec 边界裁决）
        'http://[::1', // 未闭合 IPv6
        'http://host:端口/', // 非数字端口
        ':::invalid:::', // 无 scheme 完全非法
        '', // 空串（spec 边界裁决：补成 http:// 交后续拒绝）
        '   ', // 纯空白
      ];

      for (final input in inputs) {
        expect(() => normaliseWebDavUrl(input), returnsNormally,
            reason: 'INV1：任何输入不得抛异常——"$input"');
      }
    });

    test('畸形输入经下游校验被拒（错误文案，不是异常）', () {
      const invalid = [
        'http://x:abc',
        'http://:::invalid:::',
        'http://[::1',
        '   ',
      ];

      for (final input in invalid) {
        expect(validateUrl(input), isNotNull,
            reason: '"$input" 必须得到校验错误（表单显示友好提示）');
      }
    });
  });
}
