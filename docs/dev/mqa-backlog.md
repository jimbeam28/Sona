# mqa-backlog — 待真机清单（攒单制）

> SCHEMA §3.3：MQA 不阻塞 impl_status=done。manual_qa_required 条目的验证项追加到此，用户下次装真机时一次性跑完勾选。

## BUG-27 播放器健壮性（PLY4+PLY5）（追加于 2026-08-05）
- □ 4G 弱网（或限速代理）下播放队列中唯一曲目，待加载明显变慢后快速移除该曲目使队列清空 — 期望：播放立即停止，无残余声音、被删曲目不再重新起播（ghost playback 不发生）
- □ 正常播放中多次连续快速移除最后一曲（重复制造空队列） — 期望：每一轮播放器都正确停止、队列清空，任一轮均不出现 ghost playback（覆盖 beginRequest 后 gate 任务已越过 isLatest 检查的极端竞态窗口）
