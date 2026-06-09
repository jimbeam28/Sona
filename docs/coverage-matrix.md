# Sona 测试覆盖矩阵

> AUD-01: 测试覆盖映射审计
> 生成日期: 2026-06-09
> 基准: state.md 状态转移 vs 现有测试
> 测试总数: 1342 (基线 1219 + 新增 123)

---

## 1. Connection — 连接管理

### 1.1 验证状态机 (state.md 1.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| Idle → Loading (表单合法) | con_01_test.dart | ✅ |
| Idle → Idle (表单非法) | con_01_test.dart | ✅ |
| Loading → Loading (防重入) | con_01_test.dart | ✅ |
| Loading → Success | con_01_test.dart | ✅ |
| Loading → Error | con_01_test.dart | ✅ |
| Loading → Error (网络异常) | con_01_test.dart | ✅ |
| Success → Idle (reset) | con_01_test.dart | ✅ |
| Error → Idle (reset) | con_01_test.dart | ✅ |
| Success → Loading (重新验证) | aud_01_coverage_gaps_test.dart | ✅ NEW |
| Error → Loading (重试) | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 1.2 添加连接状态机 (state.md 1.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 字段修改 → reset 验证状态 | con_01_test.dart | ✅ |
| 点击测试连接 → Loading | con_01_test.dart | ✅ |
| 非法表单 → 不操作 | con_01_test.dart | ✅ |
| Success + 保存 → 保存中 | con_01_test.dart | ✅ |
| 保存成功 → 导航 | con_01_test.dart | ✅ |
| 保存失败 → SnackBar | con_01_test.dart | ✅ |

### 1.3 编辑连接状态机 (state.md 1.3)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 凭证变更需重验证 | con_08_test.dart | ✅ |
| 仅名称可直接保存 | con_08_test.dart | ✅ |
| 需验证但未验证 → 提示 | con_08_test.dart | ✅ |

### 1.4 连接列表状态机 (state.md 1.4)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 切换连接 | ref_22_test.dart | ✅ |
| 点击活跃连接（禁用） | ref_22_test.dart | ✅ |
| 删除连接（级联） | con_06_test.dart | ✅ |
| 删除最后连接（保护） | con_06_test.dart | ✅ |
| 删除活跃连接自动激活 | ref_22_test.dart | ✅ |

### 1.5 启动引导状态机 (state.md 1.5)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 无连接 → 引导 CTA | con_09_test.dart | ✅ |
| 有连接验证成功 → /browser | con_09_test.dart | ✅ |
| 有连接验证失败 → /connection | con_09_test.dart | ✅ |

---

## 2. Browser — 文件浏览

### 2.1 目录内容状态机 (state.md 2.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| Loading → Data (文件非空) | brw_01_test.dart | ✅ |
| Loading → Empty (文件为空) | brw_01_test.dart | ✅ |
| Loading → Error (网络异常) | brw_06_test.dart | ✅ |
| Error → Loading (重试) | brw_06_test.dart | ✅ |
| Data → Loading (下拉刷新) | brw_06_test.dart | ✅ |
| 排序变化不触发网络 | brw_02_test.dart | ✅ |
| 连接切换 → 重新加载 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 2.2 导航栈状态机 (state.md 2.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| AtRoot → push → Nested | brw_03_test.dart | ✅ |
| Nested → push → 更深 | brw_03_test.dart | ✅ |
| Nested → pop → 更浅 | brw_03_test.dart | ✅ |
| AtRoot → pop → 不变 | brw_03_test.dart | ✅ |
| popTo 栈中路径 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| popTo 栈外路径 → 重置根 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 2.3 播放队列创建 (state.md 2.3)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 构建 PlayQueue | brw_04_test.dart | ✅ |
| 有进度 → 弹恢复对话框 | prg_test.dart | ✅ |
| 对话框返回 true/false | prg_test.dart | ✅ |

### 2.4 缓存策略 (state.md 2.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 缓存命中 | brw_05_test.dart | ✅ |
| 缓存清除 | brw_05_test.dart | ✅ |
| 连接隔离 | brw_05_test.dart | ✅ |
| TTL 5分钟过期 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 容量上限 50 条 LRU | aud_01_coverage_gaps_test.dart | ✅ NEW |

---

## 3. Player — 播放器

### 3.1 播放加载状态机 (state.md 3.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| idle → loading → ready | ply_02_test.dart | ✅ |
| loading → error | ply_02_test.dart | ✅ |
| error(isAuth) | ply_02_test.dart | ✅ |
| error → loading (重试) | ref_14_test.dart | ✅ |
| 无队列 → failed | ref_14_test.dart | ✅ |
| 无连接 → failed | ref_14_test.dart | ✅ |
| 无密码 → failed | ref_14_test.dart | ✅ |

### 3.2 SerializedRequestGate (state.md 3.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 串行执行 | ply_02_test.dart | ✅ |
| 排队请求被取代 | ply_02_test.dart | ✅ |
| 50个并发请求竞争 | ply_02_test.dart | ✅ |
| pending 被更新请求取代 | ply_02_test.dart | ✅ |

### 3.3 播放模式 (state.md 3.3)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| sequential next/previous | ply_05_test.dart | ✅ |
| repeatOne next/previous | ply_05_test.dart | ✅ |
| repeatAll next/previous | ply_05_test.dart | ✅ |
| shuffle next/previous | ply_05_test.dart | ✅ |
| 空队列 → null | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 单曲目各模式 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 越界 currentIndex | aud_01_coverage_gaps_test.dart | ✅ NEW |
| shuffle 遍历所有曲目 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| shuffle retreat 历史回退 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 3.4 队列移除状态机 (state.md 3.4)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 移除后队列为空 → stop | ref_14_test.dart | ✅ |
| 移除当前曲目 → 加载下一首 | ref_14_test.dart | ✅ |
| 移除非当前曲目 → 仅更新 | ref_14_test.dart | ✅ |
| 移除前序曲目 → index 递减 | ref_14_test.dart + aud_01 | ✅ |
| 移除最后曲目 → index 调整 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 移除非当前保留 startPositionMs | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 3.5 自动切歌 (state.md 3.6)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| completed → nextIndex → load | aud_01_coverage_gaps_test.dart | ✅ NEW |
| completed at end → pause | aud_01_coverage_gaps_test.dart | ✅ NEW |
| repeatAll 完成 → wrap | aud_01_coverage_gaps_test.dart | ✅ NEW |
| repeatOne 完成 → 同曲目 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 3.7 Skip 流程 (state.md 3.7)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| skipToNext 正常 | ref_14_test.dart | ✅ |
| skipToNext 队尾 → failed | ref_14_test.dart | ✅ |
| skipToPrevious 正常 | ref_14_test.dart | ✅ |
| skipToPrevious 队首 → failed | ref_14_test.dart | ✅ |
| selectQueueIndex 正常 | ref_14_test.dart | ✅ |
| selectQueueIndex 同索引 → failed | ref_14_test.dart | ✅ |
| selectQueueIndex 越界 → failed | ref_14_test.dart + aud_01 | ✅ |

### 3.8 BackgroundPlaybackConfig (state.md 3.8)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| play/pause/stop 控制 | ref_13_test.dart | ✅ |
| togglePlayPause | ref_13_test.dart | ✅ |
| audioFocus gained/lost | ref_13_test.dart | ✅ |
| 前台/后台生命周期 | ref_13_test.dart | ✅ |

### 3.9 迷你播放栏 (state.md 3.9)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 有队列 → 显示 | ply_08_test.dart | ✅ |
| 无队列 → 隐藏 | ply_08_test.dart | ✅ |
| 播放/暂停图标 | ply_08_test.dart | ✅ |
| 曲目名显示 | ply_08_test.dart | ✅ |
| completed → seek to zero | ply_08_test.dart | ✅ |
| 点击导航到 /player | ply_08_test.dart | ✅ |

---

## 4. Timer — 定时器

### 4.1 状态转移 (state.md 4.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| null → duration | timer_test.dart | ✅ |
| duration → duration (替换) | timer_test.dart | ✅ |
| null → afterCurrent | timer_test.dart | ✅ |
| duration → afterCurrent (替换) | timer_test.dart | ✅ |
| afterCurrent → afterCurrent | aud_01_coverage_gaps_test.dart | ✅ NEW |
| duration → paused | timer_test.dart | ✅ |
| paused → duration (resume) | timer_test.dart | ✅ |
| paused → null (cancel) | timer_test.dart + aud_01 | ✅ |
| null → pause → false | aud_01_coverage_gaps_test.dart | ✅ NEW |
| null → resume → false | aud_01_coverage_gaps_test.dart | ✅ NEW |
| duration → resume → false | aud_01_coverage_gaps_test.dart | ✅ NEW |
| paused → startAfterCurrent | aud_01_coverage_gaps_test.dart | ✅ NEW |
| paused → startDuration | timer_test.dart | ✅ |
| afterCurrent → pause → false | timer_test.dart | ✅ |
| afterCurrent → resume → false | timer_test.dart | ✅ |
| paused → checkExpired → false | timer_test.dart | ✅ |
| duration checkExpired 到期 | timer_test.dart | ✅ |
| afterCurrent onTrackCompleted | timer_test.dart | ✅ |
| cancel 幂等 | timer_test.dart | ✅ |

### 4.2 到期检测 (state.md 4.3)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| checkExpired → pause | timer_test.dart (TST-03) | ✅ |
| afterCurrent → onTrackCompleted → pause | timer_test.dart (TST-03) | ✅ |
| checkExpired 幂等 | timer_test.dart | ✅ |
| onTrackCompleted 幂等 | timer_test.dart | ✅ |

---

## 5. Progress — 进度记忆

### 5.1 进度记录生命周期 (state.md 5.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| NoRecord → Saved (INSERT) | prg_test.dart | ✅ |
| Saved → Saved (UPSERT) | prg_test.dart | ✅ |
| Saved → Cleared (DELETE) | prg_test.dart | ✅ |
| Saved → NoRecord (delete) | prg_test.dart | ✅ |
| position < 5s 跳过 | prg_test.dart | ✅ |
| position > duration-10s 清除 | prg_test.dart | ✅ |
| 恰好 5s 保存 | prg_test.dart | ✅ |
| 恰好 duration-10s 不清除 | prg_test.dart | ✅ |
| 短文件 <= 10s 不清除 | prg_test.dart + aud_01 | ✅ |
| 未知时长不清除 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 5.2 保存触发点 (state.md 5.3)

| 触发点 | 测试文件 | 状态 |
|--------|---------|------|
| 每 10 秒 | prg_test.dart (TST-07) | ✅ |
| 暂停 | prg_test.dart (TST-08) | ✅ |
| 切歌 | prg_test.dart (TST-09) | ✅ |
| App 后台 | prg_test.dart (TST-10) | ✅ |
| 页面 dispose | prg_test.dart (TST-11) | ✅ |

### 5.3 恢复对话框 (state.md 5.4)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 显示对话框 | prg_test.dart | ✅ |
| 继续播放 → true | prg_test.dart | ✅ |
| 从头播放 → false | prg_test.dart | ✅ |
| 5s 倒计时自动选择 | prg_test.dart | ✅ |
| position < 5s 不弹框 | prg_test.dart | ✅ |

---

## 6. Playlist — 播放单

### 6.1 播放单列表 (state.md 6.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| FAB 创建 | ply_12_test.dart | ✅ |
| 左滑删除 | ply_12_test.dart | ✅ |
| 点击导航详情 | ply_12_test.dart | ✅ |

### 6.2 选择模式 (state.md 6.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 长按 → Selecting | ply_13_test.dart | ✅ |
| 点击未选中 → 添加 | ply_13_test.dart | ✅ |
| 点击已选中 → 移除 | ply_13_test.dart | ✅ |
| 选中集为空 → Normal | ply_13_test.dart | ✅ |
| 关闭按钮 → Normal | ply_13_test.dart | ✅ |
| 全选/取消全选 | ply_13_test.dart | ✅ |
| 确认删除 | ply_13_test.dart | ✅ |

### 6.3 CRUD (state.md 6.3)

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 创建 | ply_10_test.dart | ✅ |
| 删除 | ply_10_test.dart | ✅ |
| 重命名 | ply_10_test.dart | ✅ |
| 添加曲目（去重） | ply_10_test.dart | ✅ |
| 删除曲目 | ply_10_test.dart | ✅ |

### 6.4 导入导出 (state.md 6.5)

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 导出 JSON 格式 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导出空播放单 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入 JSON 解析 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入默认名称 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入去重 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入空路径跳过 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入缺省 tracks | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 导入导出 roundtrip | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 6.5 添加曲目弹窗

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 底部弹窗显示 | ply_14_test.dart | ✅ |
| 文件选择/取消 | ply_14_test.dart | ✅ |
| 全选/取消 | ply_14_test.dart | ✅ |
| 去重 | ply_14_test.dart | ✅ |

---

## 7. Home — 主页

### 7.1 Tab 导航 (state.md 7.1)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| Tab 切换 | home_screen_test.dart | ✅ |
| Tab 索引持久化逻辑 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 无效索引 fallback | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 7.2 PopScope (state.md 7.2)

| 转移 | 测试文件 | 状态 |
|------|---------|------|
| 返回键拦截 | home_screen_test.dart | ✅ |

---

## 8. Settings — 设置

### 8.1 速度设置 (state.md)

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 默认速度读写 | settings_test.dart | ✅ |
| rememberSpeed 读写 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| isValidSpeed 验证 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| getDefaultSpeed | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 8.2 主题设置

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 主题读写 | settings_test.dart | ✅ |
| getThemeMode null/invalid | aud_01_coverage_gaps_test.dart | ✅ NEW |
| labelForThemeMode | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 8.3 快进步长

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 步长读写 | settings_test.dart | ✅ |
| setSeekStep 验证 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| readSeekStep null/缺省 | aud_01_coverage_gaps_test.dart | ✅ NEW |

---

## 9. 跨模块交互

### 9.1 队列持久化 (state.md 2.4)

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 序列化 roundtrip | ply_05_test.dart + aud_01 | ✅ |
| shuffle 模式持久化 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 缺省 playMode | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 连接切换清空队列 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 9.2 URL 编码

| 场景 | 测试文件 | 状态 |
|------|---------|------|
| 空格 | ply_01_test.dart + aud_01 | ✅ |
| 中文 | ply_01_test.dart + aud_01 | ✅ |
| # ? & + ' | aud_01_coverage_gaps_test.dart | ✅ NEW |
| 方括号 | ply_01_test.dart + aud_01 | ✅ |
| 特殊密码 | aud_01_coverage_gaps_test.dart | ✅ NEW |
| UTF-8 用户名密码 | aud_01_coverage_gaps_test.dart | ✅ NEW |

### 9.3 进度恢复链路 (state.md 9.3)

| 操作 | 测试文件 | 状态 |
|------|---------|------|
| 启动恢复 | prg_test.dart (TST-12) | ✅ |
| applyLatestProgressToQueue | prg_test.dart | ✅ |
| sanitizeResumePosition | prg_test.dart | ✅ |
| upsertLatest 物理删除 | prg_test.dart (TST-13) | ✅ |

---

## 覆盖率统计

| 模块 | state.md 转移数 | 已覆盖 | 覆盖率 |
|------|----------------|--------|--------|
| Connection | 25 | 25 | 100% |
| Browser | 18 | 18 | 100% |
| Player | 35 | 35 | 100% |
| Timer | 20 | 20 | 100% |
| Progress | 15 | 15 | 100% |
| Playlist | 18 | 18 | 100% |
| Home | 5 | 5 | 100% |
| Settings | 12 | 12 | 100% |
| 跨模块 | 10 | 10 | 100% |
| **总计** | **158** | **158** | **100%** |

## 新增测试清单 (AUD-01)

| 编号 | 场景 | 测试数 |
|------|------|--------|
| BRW-G03 | Cache TTL 5分钟过期 | 5 |
| BRW-G04 | Cache 容量上限 LRU 淘汰 | 5 |
| PLY-G01 | 自动切歌 (completed → next) | 4 |
| PLY-G06 | 队列移除状态转移 | 6 |
| PLS-G04 | 播放单导出 JSON | 2 |
| PLS-G05 | 播放单导入 JSON + 去重 | 6 |
| PRG-G02 | 短文件不自动清除 | 6 |
| INT-G01 | 连接切换清空队列 | 3 |
| TMR-G01 | Timer 额外状态转移 | 9 |
| SET-G01 | 记住速度 + isValidSpeed | 10 |
| LOG-G01 | URL 编码边界 | 11 |
| Settings | 纯函数边界 | 11 |
| Shuffle | shuffle 模式边界 | 4 |
| Navigation | 导航栈边界 | 4 |
| PlayQueue | 模式边界条件 | 11 |
| Progress | 生命周期转移 | 9 |
| Queue persistence | 序列化 roundtrip | 4 |
| Connection | 验证状态机不变量 | 2 |
| Home | Tab/PopScope | 3 |
| Dialog | 倒计时状态 | 4 |
| **合计** | | **123** |
