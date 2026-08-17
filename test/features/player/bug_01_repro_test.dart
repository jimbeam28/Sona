// test/features/player/bug_01_repro_test.dart
// BUG-01: 通知栏/耳机"下一首/上一首"每次必抛 TypeError（queueIndex 永为 null）
// （spec: docs/features/BUG-01.md §5.4，来源 cr-20260816-0801 B1）
//
// 缺陷：NasAudioHandler 混入 QueueHandler（audio_handler.dart:43-45），
// skipToNext/skipToPrevious（audio_handler.dart:312-322）触发 callback 后
// 调 super —— audio_service 0.18.18 QueueHandler._skip（pub 缓存
// lib/audio_service.dart:3374）`final index = playbackState.nvalue!.queueIndex!`
// 对 null 直接解包抛 TypeError。lib/ 全库无任何 queueIndex 写入点（grep 0
// 命中，updateQueue / skipToQueueItem 无调用），playbackState 仅经
// _onPlayerStateChanged 的 copyWith（audio_handler.dart:140-153）更新，
// queueIndex 从出生到永远都是 null。
//
// 既有测试 audio_handler_test.dart:284-289 显式 `copyWith(queueIndex: 0)`
// 播种绕开该异常（"测试假设本身错误"），本文件按生产常态（不播种
// queueIndex、不 updateQueue）驱动 skip，修复前必须 FAIL。
//
// 门禁测试：
//   BUG-01-S1: 生产常态 skipToNext() 正常完成不抛错，callback 触发
//   BUG-01-S2: 生产常态 skipToPrevious() 正常完成不抛错，callback 触发
//   BUG-01-INV1: skip 操作不得改变 playbackState.queueIndex（保持 null）

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mockito/mockito.dart';
import 'package:nas_audio_player/core/services/audio_handler.dart';

import '../../helpers/mock_audio_player.dart';

void main() {
  /// 与 audio_handler_test.dart makeHandler 相同的装配：MockAudioPlayer +
  /// 真实 NasAudioHandler，空流驱动（无状态事件）。
  NasAudioHandler makeHandler(MockAudioPlayer player) {
    when(player.playerStateStream)
        .thenAnswer((_) => const Stream<PlayerState>.empty());
    when(player.positionStream)
        .thenAnswer((_) => const Stream<Duration>.empty());
    when(player.durationStream)
        .thenAnswer((_) => const Stream<Duration?>.empty());
    when(player.position).thenReturn(Duration.zero);
    when(player.bufferedPosition).thenReturn(Duration.zero);
    when(player.speed).thenReturn(1.0);
    return NasAudioHandler(player);
  }

  /// 驱动一次 skip 调用，返回 {done, error, cb}。
  ({bool done, Object? error, int cb}) driveSkip(
      FakeAsync async, NasAudioHandler handler, bool next) {
    var cb = 0;
    handler.onSkipToNextRequested = () {
      cb++;
    };
    handler.onSkipToPreviousRequested = () {
      cb++;
    };
    var done = false;
    Object? error;
    final future = next ? handler.skipToNext() : handler.skipToPrevious();
    future.then((_) {
      done = true;
    }).catchError((Object e) {
      error = e;
      done = true;
    });
    async.elapse(const Duration(seconds: 7));
    return (done: done, error: error, cb: cb);
  }

  group('BUG-01-S1: 生产常态（queueIndex 未播种）skipToNext 不抛 TypeError', () {
    test('BUG-01-S1: skipToNext 正常完成、callback 触发、queueIndex 保持 null', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final handler = makeHandler(player);

        // 关键：不调 updateQueue、不播种 queueIndex —— 生产常态。
        final r = driveSkip(async, handler, true);

        expect(r.error, isNull,
            reason: '生产常态下 skipToNext 不得抛 TypeError（queueIndex 为 null '
                '时 QueueHandler._skip 解包即崩，cr-20260816-0801 B1）');
        expect(r.done, isTrue, reason: 'skipToNext 必须正常完成');
        expect(r.cb, 1, reason: 'skip 回调必须触发');
        expect(handler.playbackState.value.queueIndex, isNull,
            reason: '否定断言：skipToNext 不得假装推进 audio_service 队列'
                '（本应用自管队列，queueIndex 必须保持 null）');
        handler.dispose();
      });
    });
  });

  group('BUG-01-S2: 生产常态（queueIndex 未播种）skipToPrevious 不抛 TypeError', () {
    test('BUG-01-S2: skipToPrevious 正常完成、callback 触发、queueIndex 保持 null', () {
      FakeAsync().run((async) {
        final player = MockAudioPlayer();
        final handler = makeHandler(player);

        final r = driveSkip(async, handler, false);

        expect(r.error, isNull, reason: '生产常态下 skipToPrevious 不得抛 TypeError');
        expect(r.done, isTrue, reason: 'skipToPrevious 必须正常完成');
        expect(r.cb, 1, reason: 'skip 回调必须触发');
        expect(handler.playbackState.value.queueIndex, isNull,
            reason: '否定断言：skipToPrevious 不得假装推进 audio_service 队列'
                '（queueIndex 必须保持 null）');
        handler.dispose();
      });
    });
  });
}
