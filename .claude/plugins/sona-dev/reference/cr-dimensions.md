# cr 走查维度与锚定法 — cr skill 执行细则单源

> `skills/cr/SKILL.md` 引用本文件，不在 SKILL.md 内重复清单。
> 报告格式另见 `SCHEMA.md` §3.7（格式单源）。

---

## §0 五条硬约束（出自 CLAUDE.md "架构分层" + "数据库"）

1. **分层**：UI → Provider → Domain → Contract → Data。Domain 层零 Flutter 依赖，可独立单元测试。
2. **Feature 隔离**：跨 feature 依赖必须经 `shared/di/providers.dart` 桥接，禁止 feature 间直接 import。
3. **契约层不可绕过**：数据源访问必须经 `core/contracts/` 六大接口（IAudioPlayer / IAudioHandler / IConnectionDao / IProgressDao / IPlaylistDao / ISecureStorage），Domain/Provider 不得直接用 just_audio / audio_service / sqflite / flutter_secure_storage。
   **组合根装配点豁免（REF-17-S1，2026-08-23）**：audioPlayerProvider（player_provider.dart，构造 just_audio AudioPlayer 实例的唯一合法点）与 FlutterSecureStorageAdapter（connection_provider.dart，包装 flutter_secure_storage 的唯一合法点）。两处之外的 Domain/Provider 层类型引用一律经 core/contracts/。由 cross-imports.sh `provider-platform` 检查强制（基线白名单登记这两处）。
4. **密码安全**：明文密码只能存 flutter_secure_storage，key 格式 `connection_password_{id}`；严禁进 SQLite、日志、print/debugPrint。
5. **Basic Auth**：URL 构建时凭证编码不得落日志。

---

## §1 Layer 1 机械层（读脚本输出即可，不重判）

| 脚本 | 检查项 | 非零退出 → 计入问题 |
|---|---|---|
| `cross-imports.sh all` | Domain 零 Flutter / Feature 隔离 / 敏感日志 / 层间反向依赖（基线外） | 秘密日志 → Critical；Domain 引入 Flutter/平台插件 → Critical；Feature 间直接 import → Major；其余 → Major |
| `cov-gate.sh --skip-test` | flutter analyze（0 warning）+ dart format | warning → Minor（应为 0）；未格式化 → Info |
| `coverage-check.sh check-check` | 覆盖率基线漂移 + 欠测 critical 文件 | 漂移本身归 dev-check 管，cr 不列；**欠测 critical 文件清单转交 Layer 3 测试锚定作候选区** |

`arch-baseline.txt` 已登记的存量债不计新账，但只减不增——走查中发现"在旧违规上再加新违规"仍要列。

---

## §2 Layer 2 模式层 checklist

### 2.1 正确性与健壮性

- 空值 / 边界：空列表、null、单元素、越界 index
- 异常路径：try/catch 静默吞错？向用户暴露原始异常栈？
- 资源释放：StreamSubscription / Timer / TextEditingController / AnimationController / ScrollController 在 dispose() 中 cancel / close？
- 数值边界：Duration / position 经 clampSeek 等约束？速度限 6 档？
- 值对象 == / hashCode / copyWith / fromJson 四处同步（与 P12 交叉核对）

### 2.2 并发与时序

- SerializedRequestGate：orchestrator 的 load / skip / remove 都走门？绕门直达 AudioPlayer → Critical（P14）
- await 之后的 setState 必查 mounted；异步回调读 widget 字段同理（P9）
- completed 事件必有一次性守卫并处理完复位（P1）；play() 一律 fire-and-forget + 超时兜底（P4）
- autoDispose Provider 持长生命周期对象用 ref.onDispose 清理

### 2.3 可测性

- 纯逻辑抽到 Domain（widget 内混业务判断 → 难测）
- Widget / Provider 不直调 MethodChannel（应经 background_service 抽象层）
- 测试经 helper（mock_audio_player / test_database / fake_webdav_client），不绕用真实 AudioPlayer / sqflite
- 空壳测试：只构造不调方法 / `expect(true, isTrue)` / isNotNull 占位 → 列 TEST-GAP

### 2.4 性能

- 列表项缺 const / 缺 Key → 不必要 rebuild（列表项一律 ValueKey(业务 ID)，P13）
- 长列表用 ListView.builder 而非 Column + map
- cache_policy TTL/LRU 在 directory_service 中正确引用，目录缓存过期才 fetch
- build 方法里做重活（IO / JSON parse / 排序）→ memoize 或挪 Provider

---

## §3 Layer 3 功能层：四种锚定法

功能缺陷 = 实现 ≠ 意图。**没有锚定意图就只能猜**——按锚定可靠度依次使用：

### 锚定 1：踩坑核对（platform-pitfalls.md，可靠度最高——真机 bug 换来的）

走查范围触及哪类场景就核对哪些条款，判据照踩坑库每条的"规避"字段。常用映射：

| P 条款 | 检查方法 |
|---|---|
| P1 completed 重复投递 | 任何处理 ProcessingState.completed 的代码必有一次性守卫标志，且处理完复位 |
| P2 Android completed 卡死 | nextIndex == null 分支显式 seek(0)+pause()；UI completed 态有"先 seek(0) 再 play"恢复路径；末曲结束显式 pause() |
| P3 playing 状态不传播 | 关键状态转换不依赖 stream 自然传播，显式调用触发动作后再断言 |
| P4 play() Future 挂起 | play() 一律 unawaited fire-and-forget；所有平台调用加超时兜底 |
| P5 AudioServiceConfig 参数互斥 | 改 AudioServiceConfig 前核对参数互斥；init 失败有可观测错误路径而非静默挂起 |
| P6 FlutterEngine 缓存 | 后台启动路径改动保留 MainActivity engine 缓存逻辑 |
| P7 本地代理拖慢大文件 | Android 保持 useProxyForRequestHeaders:false；音频加载路径改动需回归首曲加载耗时 |
| P8 监听器绑死页面 dispose | 播放生命周期监听器归编排层持有，严禁绑任何页面 dispose；"跳过加载"快路径必须重连监听器 |
| P9 setState after defunct 崩 | 所有 await 之后的 setState 检查 mounted |
| P10 多订阅漏 invalidate | 数据源写操作后枚举全部订阅方（cross-imports.sh impact），逐个 invalidate |
| P11 build 期间跨 provider 写 | 跨 provider 副作用放 post-frame callback 或用户事件回调 |
| P12 == / hashCode 漏字段 | 值对象新增字段：== / hashCode / copyWith / fromJson 四处同步 + "字段变更触发重建"正反两条测试 |
| P13 async gap 旧数据重建 | 列表项 ValueKey(业务 ID)；await 前后模式状态（selection 等）显式归位 |
| P14 加载并发乱状态机 | 新增加载触发点必须走 SerializedRequestGate；重点审计绕门路径 |
| P15 回调签名随版本变 | 平台回调参数做 null 防御 |
| P16 时间精度截断 | 时间计算全程毫秒；"当前时刻"经注入的 now provider，不直接 DateTime.now() |

踩坑库只增不删——dev-exe 回写的新条款下次走查自动纳入核对。

### 锚定 2：spec 符合性（已有 docs/features/{ID}.md 的模块）

借 dev-check 的对抗法（对象从 git diff 换成走查范围全量）：

- **给每条 INV 找一条可违反的代码路径**——找到 = BUG/FRAGILE 候选（测试全绿 ≠ INV 真被守护）
- Scenario 声明的状态变化 + 副作用在代码中真实发生了吗？声明了没落地 → BUG
- 代码做了 spec 没说的事（自由发挥）→ 记 DESIGN 交用户裁决（spec 由逆抽生成，漂移可能是合理演进，不预设代码有错）
- 注意：无 spec ≠ 无约束，转锚定 3/4；**不得**凭空想象一份"应有规格"挑刺

### 锚定 3：测试锚定（无 spec 的模块——测试即可执行规格）

对每个 domain 公开函数 / 公开状态转换问：

- 现有测试能否区分正确实现与一个貌似合理的错误实现？（mutation 思维：把某行逻辑改错，测试会红吗？）
- 有无绿但空壳的测试（只 setup 不 assert / isNotNull 占位）？→ TEST-GAP
- 欠断言分支 × coverage-check.sh 欠测 critical 行 → 缺陷候选区，优先逐行细审
- helper 漂移：test_database 内联 schema vs 生产 schema 是否一致；fake 实现与真实实现行为差异（cr-2026-06-28 先例：fake_secure_storage 不能模拟超时）

### 锚定 4：状态机穷举 + 内部一致性

- **状态机穷举**：timer_service / play_mode / navigation_stack / background_playback / 进度恢复对话框等 → 枚举 (状态 × 事件) 矩阵，每格代码都有处理？漏格或 fallback 语义不明 → BUG/FRAGILE 候选（cr-2026-06-28 的 F1 withIndex 漏更新 shufflePosition、F4 shuffle 末尾随机盲选、F5 shuffle previousIndex 随机均出自此法）
- **内部一致性**：语义不明 / 双重职责的函数（先例：upsertLatest 与 upsert 两种 "latest" 模式场景不清）、重复的策略实现、命名与实际行为矛盾 → 缺陷前兆，记 DESIGN 或要求补注释
- **用户域常识**：音频播放器域的用户预期（shuffle 播完应循环？进度记忆应可恢复？末曲结束按钮应回暂停态？）与实现不符 → FRAGILE/DESIGN，复现路径写用户操作序列

---

## §4 对抗自检执行细则（写报告前逐条过 BUG/FRAGILE）

1. **测试为何没抓到？** 合法答案仅三种：测试空壳 / 该分支零覆盖 / 测试假设本身就错。一种都答不上 → 降级 DESIGN 或删除。
2. **复现路径能写成具体序列吗？** 只能写"可能有问题" → 不列 BUG，降 FRAGILE（能写条件）或 DESIGN（只能写取舍）。
3. **是否重复上报？** 该处已有踩坑规避措施（如 P1 守卫标志、P9 mounted 检查）且确实生效 → 不列。
4. **是 bug 还是取舍？** "用户预期 X，实现 Y"但 Y 亦可自洽（如 shuffle previousIndex 返回随机）→ DESIGN 而非 BUG，交用户裁决。
