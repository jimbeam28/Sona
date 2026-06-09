// test/features/player/ply_14_test.dart
// TST-07: 全屏播放器 Widget 测试 (TST-T43 ~ TST-T54)
//
// Widget tests for the full-screen PlayerScreen:
//   - TST-T43: 播放器页面渲染
//   - TST-T44: 当前曲目名显示
//   - TST-T45: 播放/暂停图标切换
//   - TST-T46: 上一首/下一首按钮
//   - TST-T47: 快进/快退按钮步长标签
//   - TST-T48: 进度条 Slider value 与 position/duration 同步
//   - TST-T49: Slider onChangeEnd → player.seek()
//   - TST-T50: 速度按钮 → 底部弹窗 6 选项
//   - TST-T51: 选中速度后弹窗关闭标签更新
//   - TST-T52: 播放模式按钮循环切换 4 种图标
//   - TST-T53: 定时器按钮渲染
//   - TST-T54: 队列按钮 → 点击弹出 QueueSheet

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/features/browser/browser_provider.dart';
import 'package:nas_audio_player/features/player/player_screen.dart';
import 'package:nas_audio_player/features/player/player_provider.dart';
import 'package:nas_audio_player/shared/models/play_queue.dart';

import '../../helpers/test_factories.dart';
import 'ply_08_test.mocks.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// testAudio() is imported from test_factories.dart as testAudio().

/// Builds the test app with [PlayerScreen] wrapped in [ProviderScope].
Widget _buildTestApp({
  required MockAudioPlayer player,
  required PlayQueue queue,
  int seekStep = 15,
  List<Override>? extraOverrides,
}) {
  return ProviderScope(
    overrides: [
      audioPlayerProvider.overrideWith((ref) => player),
      audioHandlerProvider.overrideWith((ref) => null),
      currentPlayQueueProvider.overrideWith((ref) => queue),
      seekStepProvider.overrideWith((ref) => seekStep),
      loadAndPlayProvider.overrideWith(
        (ref) => () async => TrackLoadResult.loaded(player),
      ),
      ...?extraOverrides,
    ],
    child: const MaterialApp(home: PlayerScreen()),
  );
}

/// Pumps the widget and waits for the player screen to reach ready state.
///
/// Uses multiple pump cycles to ensure:
///   1. The post-frame callback fires and starts async load
///   2. The async continuation runs and sets state to ready
///   3. Stream data is delivered to StreamBuilders
/// Each pump with duration flushes microtasks, which is where stream data
/// and async continuations are delivered in the test environment.
Future<void> _pumpReadyScreen(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(); // Post-frame callback fires
  await tester
      .pump(const Duration(milliseconds: 100)); // Async continuation + rebuild
  await tester.pump(
      const Duration(milliseconds: 100)); // Stream data delivery + rebuild
  await tester.pump(const Duration(milliseconds: 100)); // Extra settling
}

// ═════════════════════════════════════════════════════════════════════════════
// Widget tests — TST-T43 ~ TST-T54
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  late MockAudioPlayer player;
  late StreamController<double> speedStreamController;

  // Default test queue: 2 tracks, current index 0
  final defaultQueue = PlayQueue(
    files: [
      testAudio('Test Song.mp3', '/music/Test Song.mp3'),
      testAudio('Song 2.flac', '/music/Song 2.flac'),
    ],
    currentIndex: 0,
  );

  // 3-track queue with currentIndex=1 so both prev and next are valid
  final threeTrackQueue = PlayQueue(
    files: [
      testAudio('A.mp3', '/music/A.mp3'),
      testAudio('B.mp3', '/music/B.mp3'),
      testAudio('C.mp3', '/music/C.mp3'),
    ],
    currentIndex: 1,
  );

  setUp(() {
    player = MockAudioPlayer();

    speedStreamController = StreamController<double>.broadcast();

    // Streams: use thenAnswer so each StreamBuilder gets a fresh stream.
    // position/duration use Stream.value (static, immediate data).
    when(player.positionStream).thenAnswer(
      (_) => Stream.value(const Duration(minutes: 1, seconds: 30)),
    );
    when(player.durationStream).thenAnswer(
      (_) => Stream.value(const Duration(minutes: 4)),
    );
    // playerState: use Stream.value for immediate data (playing=true).
    // Tests that need dynamic control (TST-T45) re-stub this.
    when(player.playerStateStream).thenAnswer(
      (_) => Stream.value(PlayerState(true, ProcessingState.ready)),
    );
    // speedStream: use broadcast controller so TST-T51 can emit updates.
    when(player.speedStream).thenAnswer(
      (_) => speedStreamController.stream,
    );
    when(player.processingStateStream).thenAnswer(
      (_) => const Stream<ProcessingState>.empty(),
    );

    // Property getters
    when(player.playing).thenReturn(true);
    when(player.processingState).thenReturn(ProcessingState.ready);
    when(player.position).thenReturn(
      const Duration(minutes: 1, seconds: 30),
    );
    when(player.duration).thenReturn(const Duration(minutes: 4));
    when(player.sequenceState).thenReturn(null);

    // Seed speed to 1.0
    speedStreamController.add(1.0);
  });

  tearDown(() {
    speedStreamController.close();
  });

  // ── TST-T43: 播放器页面渲染 ─────────────────────────────────────────────

  group('TST-T43 播放器页面渲染', () {
    testWidgets('AppBar + 封面 + 进度条 + 控制按钮全部可见', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // AppBar (back button present when pushed via router; not in this
      // test's direct MaterialApp.home setup where there is no prior route).
      expect(find.byType(AppBar), findsOneWidget);

      // 封面区域: large music note icon
      expect(find.byIcon(Icons.music_note), findsOneWidget);

      // Current track name (both AppBar title and body)
      expect(find.text('Test Song.mp3'), findsWidgets);

      // Queue position
      expect(find.text('1 / 2'), findsOneWidget);

      // Speed button (icon + label)
      expect(find.byIcon(Icons.speed), findsOneWidget);

      // Timer button
      expect(find.byIcon(Icons.timer), findsOneWidget);

      // Play mode button (sequential → playlist_play icon)
      expect(find.byIcon(Icons.playlist_play), findsOneWidget);

      // Queue button
      expect(find.byIcon(Icons.queue_music), findsOneWidget);

      // Progress slider
      expect(find.byType(Slider), findsOneWidget);

      // Play/Pause button: the large filled IconButton with size 64.
      // Uses iconSize to identify it regardless of play/pause state.
      final playPauseButton = find.byWidgetPredicate(
        (w) => w is IconButton && w.iconSize == 64,
      );
      expect(playPauseButton, findsOneWidget);

      // Skip previous button
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);

      // Skip next button
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      // Seek buttons (Icons.replay — one forward via Transform, one backward)
      expect(find.byIcon(Icons.replay), findsWidgets);

      // Time labels
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('04:00'), findsOneWidget);
    });
  });

  // ── TST-T44: 当前曲目名显示 ─────────────────────────────────────────────

  group('TST-T44 当前曲目名显示', () {
    testWidgets('从 queue.current.name 读取并显示', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // queue.current.name = 'Test Song.mp3'
      expect(find.text('Test Song.mp3'), findsAtLeast(1));
    });
  });

  // ── TST-T45: 播放/暂停图标切换 ──────────────────────────────────────────

  group('TST-T45 播放中按钮显示 pause 图标', () {
    testWidgets('playing=true → pause, playing=false → play_arrow',
        (WidgetTester tester) async {
      // Override playerStateStream with a broadcast controller for
      // dynamic control (overrides the setUp stubbing).
      final stateCtrl = StreamController<PlayerState>.broadcast();
      // Re-stub to return the controllable stream
      when(player.playerStateStream).thenAnswer((_) => stateCtrl.stream);

      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // No event emitted yet → snapshot.data is null → playing=false
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);

      // Emit playing=true
      stateCtrl.add(PlayerState(true, ProcessingState.ready));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);

      // Emit playing=false
      stateCtrl.add(PlayerState(false, ProcessingState.ready));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsNothing);

      // Emit playing=true again
      stateCtrl.add(PlayerState(true, ProcessingState.ready));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await stateCtrl.close();
    });
  });

  // ── TST-T46: 上一首/下一首按钮渲染并可点击 ──────────────────────────────

  group('TST-T46 上一首/下一首按钮', () {
    testWidgets('按钮渲染且启用时可点击', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: threeTrackQueue),
      );

      // Both icons exist
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      // Previous button: tooltip '上一首'
      expect(find.byTooltip('上一首'), findsOneWidget);

      // Next button: tooltip '下一首'
      expect(find.byTooltip('下一首'), findsOneWidget);

      // Both buttons should have non-null onPressed (enabled).
      // find.byIcon locates the Icon child; use ancestor to get the IconButton.
      final prevButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_previous),
          matching: find.byType(IconButton),
        ),
      );
      final nextButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_next),
          matching: find.byType(IconButton),
        ),
      );
      expect(prevButton.onPressed, isNotNull, reason: '上一首按钮应可用');
      expect(nextButton.onPressed, isNotNull, reason: '下一首按钮应可用');
    });

    testWidgets('队列开头时上一首按钮禁用', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      // Previous button should be disabled (onPressed is null)
      final prevButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_previous),
          matching: find.byType(IconButton),
        ),
      );
      expect(prevButton.onPressed, isNull, reason: '队列开头时上一首按钮应禁用');

      // Next button should be enabled
      final nextButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.skip_next),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNotNull, reason: '下一首按钮应可用');
    });
  });

  // ── TST-T47: 快进/快退按钮显示当前步长标签 ──────────────────────────────

  group('TST-T47 快进/快退按钮步长标签', () {
    testWidgets('显示默认 15s 步长', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue, seekStep: 15),
      );

      expect(find.text('15s'), findsNWidgets(2));
    });

    testWidgets('显示自定义 30s 步长', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue, seekStep: 30),
      );

      expect(find.text('30s'), findsNWidgets(2));
    });

    testWidgets('按钮有 replay 图标', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue, seekStep: 15),
      );

      expect(find.byIcon(Icons.replay), findsAtLeast(2));
    });
  });

  // ── TST-T48: 进度条 Slider value 与 position/duration 同步 ──────────────

  group('TST-T48 Slider value 同步', () {
    testWidgets('Slider 的 value 和 max 与 position/duration 一致',
        (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);

      // Position = 1:30 = 90000 ms, Duration = 4:00 = 240000 ms
      final expectedValueMs =
          const Duration(minutes: 1, seconds: 30).inMilliseconds.toDouble();
      final expectedMaxMs =
          const Duration(minutes: 4).inMilliseconds.toDouble();

      expect(slider.value, equals(expectedValueMs));
      expect(slider.max, equals(expectedMaxMs));
      expect(slider.min, equals(0.0));
    });
  });

  // ── TST-T49: Slider onChangeEnd → player.seek() ─────────────────────────

  group('TST-T49 Slider onChangeEnd 触发 seek', () {
    testWidgets('拖动滑块松开后调用 player.seek 到正确位置', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);

      // Drag to 30 seconds (30000 ms)
      const targetMs = 30000.0;

      // Simulate onChanged (sets _isDragging = true)
      slider.onChanged?.call(targetMs);
      await tester.pump();

      // Simulate onChangeEnd (sets _isDragging = false and calls seek)
      slider.onChangeEnd?.call(targetMs);
      await tester.pump();

      // Verify player.seek() was called with the correct position
      verify(player.seek(
        argThat(equals(const Duration(milliseconds: 30000))),
      )).called(1);
    });

    testWidgets('seek 值四舍五入', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));

      // Drag to 30499.4 ms → v.round() = 30499
      slider.onChanged?.call(30499.4);
      await tester.pump();
      slider.onChangeEnd?.call(30499.4);
      await tester.pump();

      verify(player.seek(
        argThat(equals(const Duration(milliseconds: 30499))),
      )).called(1);
    });
  });

  // ── TST-T50: 速度按钮点击 → 底部弹窗 6 选项 ────────────────────────────

  group('TST-T50 速度按钮底部弹窗', () {
    testWidgets('点击速度按钮弹出 6 个速度选项', (WidgetTester tester) async {
      // Increase surface height to avoid bottom-sheet overflow
      tester.view.physicalSize = const Size(2400, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // Tap the speed button
      final speedButton = find.widgetWithText(OutlinedButton, '1.0x');
      await tester.tap(speedButton);
      await tester.pumpAndSettle();

      // Bottom sheet should appear with title "播放速度"
      expect(find.text('播放速度'), findsOneWidget);

      // 6 speed options: note '1.0x' appears twice (button + sheet option)
      expect(find.text('0.5x'), findsOneWidget);
      expect(find.text('0.75x'), findsOneWidget);
      expect(find.text('1.0x'), findsAtLeast(1));
      expect(find.text('1.25x'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);

      // Current speed (1.0x) should have check icon and '当前' label
      expect(find.text('当前'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  // ── TST-T51: 选中速度后弹窗关闭标签更新 ─────────────────────────────────

  group('TST-T51 选中速度更新', () {
    testWidgets('选中 1.5x 后弹窗关闭，按钮标签更新', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // Tap speed button to open sheet
      await tester.tap(find.widgetWithText(OutlinedButton, '1.0x'));
      await tester.pumpAndSettle();
      expect(find.text('播放速度'), findsOneWidget);

      // Tap 1.5x option → sheet closes, setSpeed called
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      // Sheet should be closed
      expect(find.text('播放速度'), findsNothing);

      // Emit new speed on the stream to simulate AudioPlayer update
      speedStreamController.add(1.5);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify player.setSpeed was called
      verify(player.setSpeed(1.5)).called(1);

      // Speed button label should now show '1.5x'
      expect(find.text('1.5x'), findsOneWidget);
    });

    testWidgets('选中 0.5x 更新按钮标签', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '1.0x'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('0.5x'));
      await tester.pumpAndSettle();

      speedStreamController.add(0.5);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      verify(player.setSpeed(0.5)).called(1);
      expect(find.text('0.5x'), findsOneWidget);
    });
  });

  // ── TST-T52: 播放模式按钮循环切换 4 种图标 ──────────────────────────────

  group('TST-T52 播放模式按钮循环切换', () {
    testWidgets('点击 4 次循环所有模式', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // Mode 0: sequential → playlist_play icon, tooltip '顺序播放'
      expect(find.byIcon(Icons.playlist_play), findsOneWidget);
      expect(find.byTooltip('顺序播放'), findsOneWidget);

      // Tap → Mode 1: repeatOne → repeat_one icon
      await tester.tap(find.byTooltip('顺序播放'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.repeat_one), findsOneWidget);
      expect(find.byTooltip('单曲循环'), findsOneWidget);

      // Tap → Mode 2: repeatAll → repeat icon
      await tester.tap(find.byTooltip('单曲循环'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byTooltip('列表循环'), findsOneWidget);

      // Tap → Mode 3: shuffle → shuffle icon
      await tester.tap(find.byTooltip('列表循环'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.shuffle), findsOneWidget);
      expect(find.byTooltip('随机播放'), findsOneWidget);

      // Tap → wraps back to Mode 0: sequential
      await tester.tap(find.byTooltip('随机播放'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.playlist_play), findsOneWidget);
      expect(find.byTooltip('顺序播放'), findsOneWidget);
    });
  });

  // ── TST-T53: 定时器按钮渲染 ─────────────────────────────────────────────

  group('TST-T53 定时器按钮渲染', () {
    testWidgets('定时器按钮显示 timer 图标和 tooltip', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // Timer button: Icons.timer with tooltip '定时停止'
      expect(find.byIcon(Icons.timer), findsOneWidget);
      expect(find.byTooltip('定时停止'), findsOneWidget);
    });
  });

  // ── TST-T54: 队列按钮 → 点击弹出 QueueSheet ─────────────────────────────

  group('TST-T54 队列按钮弹出 QueueSheet', () {
    testWidgets('点击队列按钮弹出播放队列弹窗', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      // Tap queue button
      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pumpAndSettle();

      // QueueSheet should appear with title showing queue length
      expect(find.text('播放队列 (2)'), findsOneWidget);

      // Should show track names
      expect(find.text('Test Song.mp3'), findsWidgets);
      expect(find.text('Song 2.flac'), findsOneWidget);

      // The '当前' label appears on the current track
      expect(find.text('当前'), findsOneWidget);
    });

    testWidgets('QueueSheet 每个曲目有移除按钮', (WidgetTester tester) async {
      await _pumpReadyScreen(
        tester,
        _buildTestApp(player: player, queue: defaultQueue),
      );

      await tester.tap(find.byIcon(Icons.queue_music));
      await tester.pumpAndSettle();

      // Each track should have a close/remove button
      expect(find.byIcon(Icons.close), findsWidgets);
    });
  });
}
