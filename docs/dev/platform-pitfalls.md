# platform-pitfalls — 真机踩坑库

> **用途**：本机无法真机测试，这是用真机 bug 换来的经验库。
> - **dev-plan**：写 §3/§8 前逐条核对本次需求是否触及同类场景，触及即在 spec 中显式处置
> - **dev-exe**：修完新的真机 bug，**必须回写一条**到这里（格式见末尾）
> - 规则：只增不删；每条附来源 commit，可追溯

---

## A. just_audio / audio_service 平台行为

### P1. ProcessingState.completed 事件会重复投递
- 现象：歌曲结束时跳过两曲
- 根因：曲目自然结束可能连续收到多个 completed 事件，nextIndex 逻辑被执行两次
- 来源：ba686c9
- 规避：任何 completed 处理必须带一次性守卫标志（如 `_completingProvider`），处理完复位

### P2. 无下一首时停在 completed 状态，播放器卡死（Android）
- 现象：最后一首播完或单曲队列播完，拖动进度条/点播放都无反应
- 根因：Android just_audio 在 ProcessingState.completed 下不响应 seek/play
- 来源：91dd118, 8b914ff, 571b634
- 规避：nextIndex == null 分支必须显式 seek(0) + pause()；UI 的 completed 态要有"先 seek(0) 再 play"的恢复路径；末曲结束显式 pause() 保证 playing=false 传播

### P3. playing 状态在 Android 某些场景不传播
- 现象：末曲播完播放按钮停留在暂停图标
- 根因：just_audio 的 playing 状态未正确传播到 playerStateStream
- 来源：571b634
- 规避：关键状态转换不依赖 stream 自然传播，显式调用触发动作（pause/play）后再断言 UI

### P4. await player.play() 的 Future 可能永不完成
- 现象：播放页卡 8 秒才出现 / "正在加载"卡死
- 根因：platform-channel 与 audio_service 竞争，play() 的 Future 挂起，但音频实际已在播
- 来源：e050c03, eb32fe6
- 规避：play() 一律 fire-and-forget（unawaited）+ 短间隔轮询 player.playing；所有平台调用加超时兜底

### P5. AudioServiceConfig 参数互斥导致 init 断言失败
- 现象："正在加载音频"永久挂起
- 根因：androidStopForegroundOnPause:false 与 androidNotificationOngoing:true 矛盾，AudioService.init 断言失败，音频会话损坏
- 来源：94697c3
- 规避：改 AudioServiceConfig 前查 audio_service 文档的参数互斥表；init 失败要有可观测错误路径而非静默挂起

### P6. AudioService.init 需要缓存的 FlutterEngine
- 现象：AudioService 初始化失败
- 根因：Android 端 engine 未缓存，后台启动时拿不到 engine
- 来源：eb32fe6（MainActivity.kt）
- 规避：涉及后台启动路径的改动必须保留 MainActivity 的 engine 缓存逻辑

### P7. just_audio 本地 HTTP 代理拖垮远程大文件加载
- 现象：setAudioSource 远程 FLAC 耗时 12 秒
- 根因：带 headers 的请求默认走本地代理，代理每请求新建 HttpClient 无连接复用，ExoPlayer 探测 FLAC 需 4-5 次 range 请求各重新 TCP+TLS 握手
- 来源：ae2cc8d
- 规避：Android 上保持 useProxyForRequestHeaders:false（Authorization 经 ExoPlayer setDefaultRequestProperties 直发）；改音频加载路径时回归首曲加载耗时

## B. 监听器 / 生命周期

### P8. 播放监听器不能随页面 dispose 取消
- 现象：退出播放页后 mini 栏不响应曲目结束、不自动切歌
- 根因：processingStateStream 监听器注册在 _loadAndPlay() 内，被 PlayerScreen dispose 取消；重开播放页时 source 匹配跳过加载 → 监听器永不重建
- 来源：d6a28fe, 02e857d
- 规避：播放生命周期监听器归播放编排层持有（随加载新曲替换），严禁绑定任何页面的 dispose；"跳过加载"的快路径必须同时重连监听器

### P9. setState 在元素 defunct 后调用会崩
- 现象：超时/错误提示无法显示，UI 卡死在 loading
- 根因：异步回调返回时 widget 已销毁
- 来源：94697c3（_safeSetState）
- 规避：所有 await 之后的 setState 必须检查 mounted；异步回调读 widget 字段同理

## C. Provider / 状态刷新

### P10. 多处订阅的数据源，写一个漏一个
- 现象：播放单增删曲目后列表页 trackCount 不刷新（详情页正常）
- 根因：只 invalidate 了 playlistTracksProvider，漏了 playlistListProvider
- 来源：590c305
- 规避：dev-plan §7 必须用 `cross-imports.sh impact` 列出数据源的全部订阅方，写入回归清单

### P11. Riverpod build 期间禁止修改其它 provider
- 现象：断言错误 / 进度恢复时机错乱
- 根因：在 provider build 中触发另一个 provider 的写入
- 来源：eb32fe6, 450dc89
- 规避：跨 provider 的副作用放 post-frame callback 或用户事件回调，不放 build

### P12. 值对象 == / hashCode 漏字段，UI 静默不更新
- 现象：shuffle 顺序变了但依赖方不重建
- 根因：PlayQueue == / hashCode 未纳入 shuffle 字段，StateProvider 视为相等
- 来源：91a9ed6（BUG-01）
- 规避：新增值对象字段时，== / hashCode / copyWith / fromJson 四处同步改，且必须写"字段变更触发重建"的正反两条测试（dev-plan 铁律 4 否定断言即为此设）

## D. 异步时序 / 竞态

### P13. async gap 中 UI 状态被旧数据重建
- 现象：播放单删曲目时乱切歌
- 根因：await 删除期间 ReorderableListView 以选中态+旧 ID 重建；列表项缺 Key 按位置匹配错乱
- 来源：1db8dd7
- 规避：列表项一律 ValueKey(业务 ID)；await 前后模式状态（selection 等）显式归位；手势冲突（拖拽 vs 长按）用禁用而非共存解决

### P14. 加载请求并发 → 状态机错乱
- 现象："正在加载音频"卡死、加载状态互相覆盖
- 根因：多个加载入口并发写同一状态
- 来源：35d309d（A-1 串行化）
- 规避：播放加载唯一入口 + SerializedRequestGate 串行化；新增加载触发点必须走门，dev-check 重点审计绕门路径

## E. 框架版本 / 精度类

### P15. Flutter 升级改变回调签名
- 现象：onReorder 在 Flutter 3.44 变为 nullable，测试/代码编译失败
- 来源：bf40f7d
- 规避：升级 Flutter 后全量 analyze + 全量 widget test；平台回调参数做 null 防御

### P16. 时间运算的精度截断
- 现象：定时器暂停恢复后时长偏差
- 根因：resume() 用 ceil() 把毫秒截到分钟精度
- 来源：e5858a9（BUG-03）
- 规避：时间计算全程毫秒；需要"当前时刻"的逻辑注入 now provider（可测），不直接 DateTime.now()

---

## 回写格式（dev-exe 修完新真机 bug 时追加）

```
### P{n}. {一句话教训}
- 现象：{用户看到什么}
- 根因：{为什么会这样}
- 来源：{commit sha 或 BUG-ID}
- 规避：{设计期怎么避免再犯}
```
