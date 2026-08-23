const Duration kTimerFadeWindow = Duration(seconds: 10);

/// duration 模式剩余时间 → 目标音量。
/// 返回 1.0 表示窗口外（不需要写）；[0,1) 表示淡出中应写入的音量。
double fadeVolumeForRemaining(Duration? remaining) {
  if (remaining == null) return 1.0;
  if (remaining <= Duration.zero) return 0.0;
  final windowMs = kTimerFadeWindow.inMilliseconds;
  final ms = remaining.inMilliseconds;
  if (ms >= windowMs) return 1.0;
  return ms / windowMs;
}
