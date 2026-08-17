// test/features/player/ref_12_speed_gate_test.dart
// REF-12 门禁测试（spec docs/features/REF-12.md §5.4 指定文件）。
//
// 锚定删除 write-only 残留 currentSpeedProvider 后，运行时速真理源归
// player.speedStream / player.setSpeed，remember 门控在 speed_control.dart
// 单点直测：
//   - S5 删除后 grep 零命中（source 扫描）
//   - S6 remember off：调速只动 player，不碰默认/prefs
//   - S7 remember on：调速同步默认+持久化
//   - INV1 写 defaultSpeed/prefs 唯一入口是 setDefaultSpeedProvider
//   - INV2 运行时速唯一真理源为 player（provider 层无速度镜像）
//   - INV3 remember-speed 语义保留

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/features/player/widgets/speed_control.dart';
import 'package:nas_audio_player/features/settings/settings_provider.dart';
import 'package:nas_audio_player/shared/di/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/mock_audio_player.dart';

Widget _buildSpeedControl({
  required MockAudioPlayer player,
  required SharedPreferences prefs,
  required bool remember,
}) {
  return ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWithValue(player),
      sharedPreferencesProvider.overrideWith((ref) => prefs),
      rememberSpeedProvider.overrideWith((ref) => remember),
    ],
    child: MaterialApp(
      home: Scaffold(body: SpeedControl()),
    ),
  );
}

/// Opens the speed selector sheet and taps [label], scrolling into view.
Future<void> _openAndTapSpeed(WidgetTester tester, String label) async {
  await tester.tap(find.byType(OutlinedButton));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Renders the [SpeedControl] in a tall surface so the 6-option bottom sheet
/// fits without vertical overflow.
Future<void> _pumpSpeed(WidgetTester tester, Widget widget) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  test('REF-12-S5: lib 内 currentSpeedProvider 零命中（删除后）', () {
    final files = <String>[
      'lib/features/player/player_provider.dart',
      'lib/features/player/widgets/speed_control.dart',
      'lib/shared/di/providers.dart',
    ];
    for (final f in files) {
      final content = File('${Directory.current.path}/$f').readAsStringSync();
      expect(content, isNot(contains('currentSpeedProvider')),
          reason: '$f 不得再引用 currentSpeedProvider（S5）');
    }
  });

  test('REF-12-S5: test/ 内 currentSpeedProvider 零引用（排除本文件与注释）', () {
    final testDir = Directory('${Directory.current.path}/test');
    final selfPath =
        '${Directory.current.path}/test/features/player/ref_12_speed_gate_test.dart';
    final hits = <String>[];
    testDir.listSync(recursive: true).whereType<File>().where((f) {
      return f.path.endsWith('.dart') && f.path != selfPath;
    }).forEach((f) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 忽略纯注释行（含本 REF 说明文字）
        final stripped = line.trimLeft();
        if (stripped.startsWith('//') ||
            stripped.startsWith('/*') ||
            stripped.startsWith('*') ||
            stripped.startsWith('///')) {
          continue;
        }
        if (line.contains('currentSpeedProvider')) {
          hits.add('${f.path}:${i + 1}');
        }
      }
    });
    expect(hits, isEmpty, reason: 'test/ 内不得再引用 currentSpeedProvider（S8）');
  });

  testWidgets(
      'REF-12-S6 REF-12-INV2 REF-12-INV3: remember off → 调速只动 player，不碰默认/prefs',
      (tester) async {
    SharedPreferences.setMockInitialValues({'default_playback_speed': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final player = MockAudioPlayer();

    await _pumpSpeed(tester,
        _buildSpeedControl(player: player, prefs: prefs, remember: false));

    // 打开速度选择 sheet 并 tap 2.0x
    await _openAndTapSpeed(tester, '2.0x');

    // player.setSpeed(2.0) 被调
    verify(player.setSpeed(2.0)).called(1);

    // prefs 保持 1.0（未写入）
    expect(prefs.getDouble('default_playback_speed'), equals(1.0),
        reason: 'S6: remember off 不得写 prefs');
  });

  testWidgets('REF-12-S7 REF-12-INV3: remember on → 调速同步默认+持久化',
      (tester) async {
    SharedPreferences.setMockInitialValues({'default_playback_speed': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final player = MockAudioPlayer();

    await _pumpSpeed(tester,
        _buildSpeedControl(player: player, prefs: prefs, remember: true));

    await _openAndTapSpeed(tester, '2.0x');

    // player.setSpeed(2.0) 被调
    verify(player.setSpeed(2.0)).called(1);

    // prefs 更新为 2.0
    expect(prefs.getDouble('default_playback_speed'), equals(2.0),
        reason: 'S7: remember on 应持久化 2.0');
  });

  testWidgets(
      'REF-12-S7 否定 REF-12-INV1: remember on 只经 setDefaultSpeedProvider 一条写路径',
      (tester) async {
    SharedPreferences.setMockInitialValues({'default_playback_speed': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final player = MockAudioPlayer();

    await _pumpSpeed(tester,
        _buildSpeedControl(player: player, prefs: prefs, remember: true));

    // tap 多个档位，prefs 只随每次 setDefault 更新
    await _openAndTapSpeed(tester, '1.25x');
    await _openAndTapSpeed(tester, '1.5x');

    expect(prefs.getDouble('default_playback_speed'), equals(1.5),
        reason: 'INV1: remember on 的默认/prefs 更新应经 setDefaultSpeedProvider');
  });

  testWidgets('REF-12-S6 否定 REF-12-INV1: remember off 时不得写 prefs（调速不影响默认）',
      (tester) async {
    SharedPreferences.setMockInitialValues({'default_playback_speed': 1.0});
    final prefs = await SharedPreferences.getInstance();
    final player = MockAudioPlayer();

    await _pumpSpeed(tester,
        _buildSpeedControl(player: player, prefs: prefs, remember: false));

    await _openAndTapSpeed(tester, '1.25x');
    await _openAndTapSpeed(tester, '1.5x');

    expect(prefs.getDouble('default_playback_speed'), equals(1.0),
        reason: 'INV3: remember off 时 prefs 保持 1.0（运行时速与默认分离）');
    verify(player.setSpeed(1.25)).called(1);
    verify(player.setSpeed(1.5)).called(1);
  });
}
