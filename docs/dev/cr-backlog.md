# cr-backlog — 走查分流台账（攒单制）

> **用途**：cr 复核后暂未进 dev-plan 的 FRAGILE 存放地 + DESIGN 关单裁决记录。cr 报告是一次性快照（处理完即删），本文件保证分流出去的问题不丢失。
> **规则**：
> - F 区条目在用户启动下一批 dev-plan Bug 流程时逐条消化（先失败复现测试 → 逆抽 BUG-{N}.md → status 条目，同 BUG-20/21/22 流程）；消化一条删一条。
> - D 区关单为最终裁决记录，只增不改。
> - T 区登记正文在 `docs/dev/coverage-debt.txt` TEST-GAP 区（2026-08-22 起），本文件仅留索引。
>
> 来源：docs/cr/cr-20260822-2051.md（已复核并删除，全部证据行经二次亲验）

---

## F 区 — 待批次二的 FRAGILE（用户 2026-08-22 裁决：F1+F2+F4 已第一批建 BUG-20/21/22，以下五条待批次二）

### F5. DatabaseHelper 单例惰性初始化 `??=` 跨 await 双开库竞态
- 类型 / 严重度：FRAGILE / Minor｜维度：并发时序
- 证据：`lib/core/database/database_helper.dart:16-19`
  ```dart
  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  ```
- 复现路径（条件化）：启动早期两处并发首访 DB → 各执行一次 `_openDatabase()` → 双实例。
- 自检答案：测试全走 overrideDatabase 注入，生产惰性路径零覆盖。
- 修复方向：缓存 `Future<Database>` 而非 `Database?`。

### F6. reorderTrack 读-改-写不在事务内
- 类型 / 严重度：FRAGILE / Minor｜维度：并发时序
- 证据：`lib/core/database/dao/playlist_dao.dart:178`（SELECT 事务外）、`:189-203`（内存重排 + batch）
- 复现路径（条件化）：重排进行中并发 addTracks 提交 added_at 落入 base+i 序列中间 → 下次读序错乱（不丢数据）。
- 自检答案：测试全串行，无并发注入——分支零覆盖。
- 修复方向：SELECT+重排+update 包进单事务。

### F7. 连接删除 last-one 守卫在事务外（TOCTOU）
- 类型 / 严重度：FRAGILE / Minor｜维度：并发时序
- 证据：`lib/core/database/dao/connection_dao.dart:119-122`（count 守卫）与 `:128`（事务起点分离）
- 复现路径（条件化）：两并发 delete 同过守卫（各见 remaining==2）→ 删至 0 行。UI 单线程低概率。
- 自检答案：无并发 delete 测试——分支零覆盖。
- 修复方向：守卫挪进事务。

### F8. listDirectory 的 decodeFull(basePath) 无保护，非法转义报误导性错误
- 类型 / 严重度：FRAGILE / Minor｜维度：健壮性
- 证据：`lib/core/network/webdav_client.dart:363`（裸 decodeFull）→ `:376-382` 泛 catch 转「无法连接到服务器」；对照组 nas_file.dart:96-100 有 try/降级
- 复现路径：basePath 含非法百分号转义（如 `/dav/100%.mp3/`）→ 浏览目录报"无法连接"而非"地址非法"。
- 自检答案：fake 绕过 URL 解析层；HTTP 层测试无该用例——分支零覆盖。
- 修复方向：包 try/catch 并区分错误文案。

### F9. PlaylistTrack 缺 copyWith，两处手工逐字段拷贝点是 P12 漂移雷区
- 类型 / 严重度：FRAGILE / Info｜维度：可维护性
- 证据：`lib/core/database/dao/playlist_dao.dart:126-135`、`lib/features/playlist/domain/playlist_service.dart:200-207`
- 复现路径（条件化）：未来加字段时手工拷贝点静默丢字段。
- 自检答案：风险本质不可测，靠结构性约定防御。
- 修复方向：补 copyWith，两处改用。

---

## D 区 — 关单裁决记录

### D3. 低风险观察项捆绑（cr-20260822-2051）
- **裁决**：登记关单，不建条目不改码（用户 2026-08-22）。
- 内容与理由：
  1. PROPFIND 解析取首个 propstat（webdav_client.dart:414-423/:492）——主流 NAS 单 propstat 响应，多块且失败块在前的服务器暴露面极小；
  2. progress_dao upsert 用 ConflictAlgorithm.replace 每次换行 id（progress_dao.dart:123-133）——当前无表引用 play_progress.id，无损；若未来新增引用方须回看此条；
  3. trackExists 循环逐文件查询 N+1（playlist_service.dart:84）——本地 SQLite 亚毫秒级，百文件目录约百毫秒，可接受；
  4. recentlyPlayedProvider（progress_provider.dart:52）/ exportPlaylistProvider（playlist_provider.dart:152）无写路径失效机制——当前零消费者；首个消费者接入前必须补 invalidate（REF-13 曾裁决保留作未来功能位）。

## T 区 — 索引

T4-T8 登记正文见 `docs/dev/coverage-debt.txt` TEST-GAP 区「cr-0822」块；T1/T2/T3 已补测完成（aud_05/int_g01/aud_01 三文件 241 测试全绿）；旧登记 cr-0806 T4/T5 已解决、T2 部分解决（见同区处理进展标注）。

## 批次一产物索引（2026-08-22）

| cr 条目 | 去向 |
|---|---|
| F1 | BUG-20（repro: test/features/player/bug_bug20_repro_test.dart，FAIL 已确认） |
| F2 | BUG-21（repro: test/features/player/bug_bug21_completed_seek_test.dart，FAIL 已确认） |
| F4 | BUG-22（repro: test/features/playlist/bug_bug22_repro_test.dart，FAIL 已确认） |
| D1 | REF-17 |
| D2 | REF-18 |
