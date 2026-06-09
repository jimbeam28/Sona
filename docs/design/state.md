# Sona 状态机规格书

> 本文档是 Sona 全部功能的行为规格书。每个状态转移都是一个可测试的行为契约。
> 重构时以此文档为准：代码必须实现这里描述的所有转移，测试必须覆盖每一个转移。
>
> 更新日期: 2026-06-09

---

## 目录

1. [Connection — 连接管理](#1-connection--连接管理)
2. [Browser — 文件浏览](#2-browser--文件浏览)
3. [Player — 播放器](#3-player--播放器)
4. [Timer — 定时器](#4-timer--定时器)
5. [Progress — 进度记忆](#5-progress--进度记忆)
6. [Playlist — 播放单](#6-playlist--播放单)
7. [Home — 主页](#7-home--主页)
8. [路由状态机](#8-路由状态机)
9. [跨模块交互](#9-跨模块交互)

---

## 1. Connection — 连接管理

### 1.1 验证状态机

**职责**：验证 WebDAV 连接是否可用。

**状态枚举**：

| 状态 | 含义 |
|------|------|
| `ValidationIdle` | 未验证或已重置 |
| `ValidationLoading` | PROPFIND 请求进行中 |
| `ValidationSuccess` | 验证成功 |
| `ValidationError` | 验证失败，携带错误消息 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Idle` | `validate()` | 表单合法 | 发送 PROPFIND 请求 | `Loading` | — |
| `Idle` | `validate()` | 表单非法 | 不发送请求，保持原状态 | `Idle` | 表单显示字段错误 |
| `Loading` | `validate()` | — | 静默忽略（防重入） | `Loading` | — |
| `Loading` | 服务端返回成功 | `result.isSuccess == true` | 记录结果 | `Success` | — |
| `Loading` | 服务端返回失败 | `result.isSuccess == false` | 记录错误消息 | `Error` | — |
| `Loading` | 网络异常/超时 | — | 转为错误结果 | `Error` | — |
| `Success` | `reset()` | — | 清空状态 | `Idle` | — |
| `Error` | `reset()` | — | 清空状态 | `Idle` | — |
| `Success` | `validate()` | 表单合法 | 重新验证 | `Loading` | — |
| `Error` | `validate()` | 表单合法 | 重新验证 | `Loading` | — |

**不变量**：
- 同一时刻最多一个 `validate()` 请求在飞
- `reset()` 从任何状态都安全，总是回到 `Idle`

### 1.2 添加连接状态机

**职责**：用户填写表单 → 验证 → 保存新连接。

**复合状态** = 验证状态 × 保存状态

| 验证状态 | 保存中 | "测试连接"按钮 | "保存"按钮 | 提示条 |
|----------|--------|--------------|-----------|--------|
| `Idle` | 否 | 可用 | 禁用 | 无 |
| `Loading` | 否 | 禁用(转圈) | 禁用 | 无 |
| `Success` | 否 | 可用 | **可用** | 绿色成功 |
| `Error` | 否 | 可用 | 禁用 | 红色错误 |
| `Success` | 是 | 禁用 | 禁用(转圈) | 绿色成功 |
| `Error` | 是 | 禁用 | 禁用(转圈) | 红色错误 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| 任意验证状态 | 用户修改字段 | — | `reset()` 验证状态 | `Idle, 未保存` | 防止旧验证结果启用保存 |
| 非 Loading 非保存中 | 点击"测试连接" | 表单合法 | 发起验证 | `Loading` | — |
| `Idle` | 点击"测试连接" | 表单非法 | 不操作 | `Idle` | 显示字段错误 |
| `Success, 未保存` | 点击"保存" | 表单合法 | 写入 DB + SecureStorage | `Success, 保存中` | — |
| `Success, 保存中` | 保存成功 | — | 刷新 provider，导航到 /browser | 页面销毁 | — |
| `Success, 保存中` | 保存失败 | — | 显示错误 SnackBar | `Success, 未保存` | — |

**保存流程**（原子性）：
1. INSERT 连接行（密码列存临时引用 key）
2. 写入密码到 SecureStorage（key: `connection_password_{id}`）
3. 若 SecureStorage 失败 → 回滚 DB 行（DELETE）→ 抛出异常
4. 更新行引用永久 key
5. 调用 `setActive(id)` 设为活跃连接

**不变量**：
- 保存按钮仅在 `ValidationSuccess` 且未保存中时可用
- 字段变更立即重置验证状态，防止旧结果误启用保存

### 1.3 编辑连接状态机

**职责**：修改已有连接配置。

**验证门控逻辑**：

```
需要重新验证 = true 当且仅当以下任一成立：
  - url 与原始值不同
  - username 与原始值不同
  - basePath 与原始值不同
  - 密码字段非空（用户输入了新密码）

可以保存 =
  如果需要重新验证 → 验证状态为 Success
  否则 → true（仅修改名称，无需重验证）
```

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| 任意 | 用户修改字段 | — | `reset()` 验证状态 | `Idle` | 保存按钮可能禁用 |
| `Idle` | 点击"测试连接" | 表单合法 | 发起验证 | `Loading` | — |
| `Success, 未保存` | 点击"保存" | 需要验证 | 更新 DB + 可选更新密码 | `Success, 保存中` | — |
| 任意, 未保存` | 点击"保存" | 不需要验证（仅名称） | 更新 DB | `保存中` | — |
| 任意, 未保存` | 点击"保存" | 需要验证但未验证 | 显示 SnackBar "请先测试连接" | 不变 | — |
| `保存中` | 保存成功 | — | SnackBar + pop 回列表 | 页面销毁 | 刷新 provider |
| `保存中` | 保存失败 | — | SnackBar 错误 | `未保存` | — |

**不变量**：
- 修改凭证字段时，必须重新验证才能保存
- 仅修改名称时，可直接保存
- 空密码字段保留原密码不变

### 1.4 连接列表状态机

**列表状态**：

| 状态 | 含义 |
|------|------|
| `ListLoading` | 数据库查询中 |
| `ListError` | 查询失败 |
| `ListEmpty` | 0 个连接 |
| `ListData` | N ≥ 1 个连接 |

**活跃连接状态**：

| 状态 | 含义 |
|------|------|
| `ActiveLoading` | 查询中 |
| `ActiveNone` | 无活跃连接 |
| `ActiveSome` | 有活跃连接，ID 已知 |

**切换连接转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `ListData, ActiveSome` | 点击非活跃连接 | `conn.id != activeId` | `dao.setActive(id)` | 列表刷新 | 清除浏览器缓存 + 导航栈；SnackBar |
| `ListData, ActiveSome` | 点击活跃连接 | `conn.id == activeId` | 无操作（禁用） | 不变 | — |
| 切换成功 | — | — | — | — | SnackBar "已切换到「name」" |
| 切换失败 | — | — | — | — | SnackBar 错误 |

**删除连接转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `ListData` | 用户发起删除 | 连接数 ≤ 1 | 显示"无法删除"警告 | 不变 | — |
| `ListData` | 用户发起删除 | 连接数 > 1 | 显示确认弹窗 | 等待确认 | — |
| 等待确认 | 用户取消 | — | 关闭弹窗 | 不变 | — |
| 等待确认 | 用户确认 | — | 执行删除 | 删除中 | DB + SecureStorage 删除 |
| 删除中 | 删除成功 | — | 刷新列表 | 列表更新 | SnackBar |
| 删除中 | 删除失败 | — | SnackBar 错误 | 不变 | — |

**DAO 层保证**：
- `setActive()` 用事务保证唯一活跃连接
- `delete()` 阻止删除最后一个连接（抛出 `LastConnectionException`）
- 删除活跃连接时自动激活另一个

### 1.5 启动引导状态机

**状态枚举**：

| 状态 | 含义 |
|------|------|
| `Checking` | 读取连接列表中 |
| `DBError` | 数据库读取失败 |
| `Empty` | 无连接，显示引导 CTA |
| `Validating` | 有连接，正在验证活跃连接 |
| `Healthy` | 验证成功或无活跃连接 |
| `Unhealthy` | 验证失败 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| App 启动 | — | — | 路由到 /onboarding | `Checking` | 开始加载连接列表 |
| `Checking` | 连接列表加载完成 | 有连接 | 开始验证活跃连接 | `Validating` | — |
| `Checking` | 连接列表加载完成 | 无连接 | 显示引导 CTA | `Empty` | — |
| `Checking` | 连接列表加载失败 | — | 显示错误 + 重试 | `DBError` | — |
| `DBError` | 用户点击重试 | — | 重新加载 | `Checking` | — |
| `Empty` | 用户点击"添加连接" | — | 导航到 /connection | — | — |
| `Validating` | 验证成功 | — | 导航到 /browser | — | 恢复队列 + 进度 |
| `Validating` | 验证失败 | — | 导航到 /connection | — | 显示橙色修复提示 |
| `Validating` | 无活跃连接 | — | 导航到 /browser | — | — |

**不变量**：
- App 不会到达 /browser 除非验证成功或无活跃连接
- 导航在 `postFrameCallback` 中执行，避免 Riverpod 构建期修改

---

## 2. Browser — 文件浏览

### 2.1 目录内容状态机

**状态枚举**：

| 状态 | 含义 |
|------|------|
| `Loading` | PROPFIND 请求中，显示骨架屏 |
| `Error` | 请求失败，显示错误信息 + 重试按钮 |
| `Empty` | 目录为空 |
| `Data` | 有文件，显示列表 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| 任意 | 导航栈变化（push/pop/popTo） | — | 重新加载新路径内容 | `Loading` | 进度注册表失效 |
| `Loading` | 网络成功 + 文件非空 | 有活跃连接 + 有密码 | 缓存结果，排序 | `Data` | 加载目录内文件进度 |
| `Loading` | 网络成功 + 文件为空 | 同上 | 缓存结果 | `Empty` | 同上 |
| `Loading` | 网络异常 | — | 传播错误 | `Error` | — |
| `Loading` | 无活跃连接 | — | 抛出异常 | `Error` | — |
| `Loading` | 密码缺失 | — | 抛出异常 | `Error` | — |
| `Error` | 用户点击重试 | — | 清除缓存，重新请求 | `Loading` | — |
| `Data` | 用户下拉刷新 | — | 清除缓存，重新请求 | `Loading` | — |
| `Data` | 排序选项变化 | — | 缓存命中，重新排序 | `Data` | 无网络请求 |
| 任意 | 活跃连接变化 | — | 缓存 key 不同，重新加载 | `Loading` | 旧连接缓存不会被命中 |

**缓存策略**：
- Key: `connectionId:path`（切换连接不泄漏旧数据）
- TTL: 5 分钟
- 容量: 最多 50 条目，LRU 淘汰
- 排序变化不触发网络请求（缓存命中 + 重新排序）

### 2.2 导航栈状态机

**状态**：
- `AtRoot`：栈只有 `['/']`，系统返回键退出浏览器
- `Nested`：栈深度 > 1，系统返回键弹出栈顶

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `AtRoot` | `push(path)` | — | 追加路径 | `Nested` | 加载新目录 |
| `Nested` | `push(path)` | — | 追加路径 | `Nested`（更深） | 同上 |
| `Nested` | `pop()` | 栈深度 > 1 | 移除栈顶 | `Nested` 或 `AtRoot` | 加载上级目录 |
| `AtRoot` | `pop()` | 栈深度 = 1 | 无操作 | `AtRoot` | — |
| 任意 | `popTo(path)` | path 在栈中 | 截断到 path | `Nested` 或 `AtRoot` | 加载对应目录 |
| 任意 | `popTo(path)` | path 不在栈中 | 重置为 `['/']` | `AtRoot` | 加载根目录 |

**不变量**：导航栈始终至少有一个条目（根 `/`）。

### 2.3 播放队列创建

用户点击音频文件时的流程：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Data` | 点击音频文件 | 无保存进度 | 构建 PlayQueue，导航到 /player | — | 设置 currentPlayQueueProvider |
| `Data` | 点击音频文件 | 有进度且 positionMs ≥ 5000 | 弹出恢复对话框 | 等待对话框 | — |
| 等待对话框 | 对话框返回 true | — | startPositionMs = 进度位置 | — | 设置队列 + 导航 |
| 等待对话框 | 对话框返回 false | — | startPositionMs = null | — | 设置队列 + 导航 |
| `Data` | 长按音频文件 | 有进度 | 显示清除进度选项 | 底部弹窗 | — |
| 底部弹窗 | 点击"清除进度" | — | 删除进度记录 | 返回 `Data` | DB 删除 + SnackBar |

### 2.4 队列持久化

| 触发 | 前置条件 | 动作 | 副作用 |
|------|---------|------|--------|
| currentPlayQueueProvider 变为非 null | SharedPreferences 可用 | 序列化队列为 JSON 保存 | — |
| currentPlayQueueProvider 变为 null | SharedPreferences 可用 | 从 prefs 删除 | — |
| App 启动恢复 | 有保存数据 + 连接匹配 | 反序列化 + 预加载音频源 | 播放器源已设置 |
| App 启动恢复 | 有保存数据 + 连接不匹配 | 反序列化但跳过预加载 | — |

### 2.5 连接切换清空队列

| 触发 | 前置条件 | 动作 | 副作用 |
|------|---------|------|--------|
| activeConnectionProvider 变化 | 新 ID ≠ 队列记录的连接 ID | 清空队列 + 清空 lastQueueConnectionId | MiniPlayerBar 消失 |

---

## 3. Player — 播放器

### 3.1 播放加载状态机

**状态枚举**：

| 状态 | 含义 |
|------|------|
| `idle` | 初始状态 |
| `loading` | 音频源加载中 |
| `ready` | 加载成功，正在播放 |
| `error` | 加载失败，携带错误消息和 isAuthError 标记 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `idle` | PlayerScreen 初始化 | 队列非 null + 源不匹配 | 调用 loadAndPlay | `loading` | — |
| `idle` | PlayerScreen 初始化 | 队列非 null + 源匹配 + 播放中/就绪 | 重连监听器 | `ready` | 重新注册监听器 |
| `idle` | PlayerScreen 初始化 | 队列为 null | 不操作 | `idle` | — |
| `loading` | loadAndPlay 成功 | 页面未销毁 + token 匹配 | — | `ready` | 注册监听器、启动自动保存、应用速度、更新通知 |
| `loading` | loadAndPlay 失败 + 无连接 | — | 设置错误消息 | `error(isAuth)` | — |
| `loading` | loadAndPlay 失败 + 无密码 | — | 设置错误消息 | `error(isAuth)` | — |
| `loading` | loadAndPlay 失败 + 其他 | — | 设置错误消息 | `error` | — |
| `loading` | 请求被取代 | token 匹配 | — | `error` | — |
| `loading` | 超时 (15s) | token 匹配 | — | `error` | — |
| `loading` | 其他异常 | — | — | `error` | — |
| `loading` | 结果到达但 token 不匹配 | — | 丢弃结果 | `loading` | — |
| `error` | 用户点击重试 | — | 重新加载 | `loading` | 新 token |
| `ready` | 队列变为空/null | — | 弹出页面 | — | — |

**不变量**：
- `error` 状态必定携带 `errorMessage`
- `isAuthError == true` 必定伴随 `error` 状态
- 同一页面实例同一时刻只有一个加载请求在飞

### 3.2 SerializedRequestGate — 请求序列化门

**职责**：防止共享 AudioPlayer 上出现重叠的 stop → setAudioSource → play 链。

**行为**：
- `schedule()` 递增 requestId，创建请求
- 若无正在执行的请求：立即执行
- 若有正在执行的请求：新请求排队，旧排队请求被取代（返回 `superseded`）
- 执行完成后检查是否为最新请求：是 → 返回结果；否 → 返回 `superseded`
- `finally` 块：标记空闲，执行排队请求

**TrackLoadResult 状态**：

| 状态 | 含义 |
|------|------|
| `loaded` | 加载成功且是最新请求 |
| `failed` | 加载失败 |
| `superseded` | 被更新的请求取代 |

### 3.3 播放模式

**模式枚举**：

| 模式 | nextIndex 行为 | previousIndex 行为 | 队列结束时 |
|------|---------------|-------------------|-----------|
| `sequential` | current + 1 | current - 1 | 返回 null，保持结束位置 |
| `repeatOne` | 返回 current | 返回 current | 永不返回 null |
| `repeatAll` | (current + 1) % length | (current - 1 + length) % length | 循环，永不返回 null |
| `shuffle` | 随机非当前索引 | 随机非当前索引 | length ≤ 1 时返回 null |

**模式切换**：`sequential → repeatOne → repeatAll → shuffle → sequential`，仅影响下一次导航。

**边界条件**：
- 空队列：next/previous 都返回 null
- 单曲目：sequential 返回 null；repeatOne 返回 same；repeatAll 返回 0；shuffle 返回 null
- 越界 currentIndex：返回 null

### 3.4 队列移除状态机

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| 有队列 | 移除曲目 | 移除后队列为空 | player.stop()，队列设 null，清除通知 | 无队列 | MiniPlayerBar 消失，取消自动保存 |
| 有队列 | 移除曲目 | 移除的是当前曲目 | 保存进度，加载下一条 | 新当前曲目 | — |
| 有队列 | 移除曲目 | 移除的不是当前曲目 | 仅更新队列 | 队列更新 | — |

### 3.5 播放生命周期

```
用户点击文件 → 构建 PlayQueue → 设置 currentPlayQueueProvider → 导航到 /player
  → PlayerScreen.initState()
    → 源匹配? → 重连监听器（复用已加载源）
    → 不匹配? → loadAndPlay()
      → SerializedRequestGate.schedule()
        1. 验证队列非空
        2. 验证活跃连接
        3. 读取 SecureStorage 密码
        4. 构建 AudioSource（Basic Auth + URL 编码）
        5. 注册 processingStateStream 监听器
        6. player.setAudioSource()
        7. player.seek(startPositionMs) [如有]
        8. handler.setMediaItem() [更新通知栏]
        9. 应用默认速度
       10. player.play() [unawaited, 12s poll timeout]
       11. 启动自动保存定时器 (10s)
       12. 启动暂停保存监听器
```

### 3.6 曲目完成自动切歌

当 `processingStateStream` 发出 `ProcessingState.completed`：

1. 检查防重入标记 → 若已设，忽略
2. 设防重入标记
3. 检查 afterCurrent 定时器 → 若触发，pause，停止
4. 计算下一曲：
   - shuffle 模式：`queue.advanceShuffle()`（确定性排列）
   - 其他模式：`PlayQueue.nextIndex()` → `queue.withIndex()`
5. 若无下一曲：pause，保持结束位置，停止
6. 保存进度
7. 更新 currentPlayQueueProvider
8. 调用 loadAndPlayProvider()

### 3.7 Skip 流程

**skipToNext**：
1. 读取队列和模式
2. 队列 null → 返回 failed
3. shuffle：`queue.advanceShuffle()`；其他：`PlayQueue.nextIndex()`
4. 无下一曲 → 返回 failed
5. 保存进度 → 更新队列 → loadAndPlay

**skipToPrevious**：同上，方向相反。

**selectQueueIndex**：
1. 验证索引范围
2. 索引 = 当前 → 返回 failed
3. 保存进度 → 更新队列 → loadAndPlay

### 3.8 BackgroundPlaybackConfig 状态机

**状态**：
- `playing` / `paused` / `stopped`

**媒体控制转移**：

| 从 | 动作 | 到 |
|----|------|----|
| 任意 | `play` | `playing` |
| 任意 | `pause` | `paused` |
| 任意 | `stop` | `stopped` |
| `playing` | `togglePlayPause` | `paused` |
| `paused` | `togglePlayPause` | `playing` |
| `stopped` | `togglePlayPause` | `playing` |

**音频焦点转移**：

| 焦点变化 | 新焦点 | 播放状态变化 |
|---------|--------|------------|
| `gained` | `gained` | 不变（若 isAudioActive 则恢复播放） |
| `lost` | `lost` | → `paused` |
| `transient` | `transient` | 不变（平台处理衰减） |

### 3.9 迷你播放栏

**可见性**：`currentPlayQueueProvider != null && queue.length > 0` 时显示，否则 `SizedBox.shrink()`。

**播放/暂停按钮状态**：

| 播放器状态 | 按钮图标 | 点击动作 |
|-----------|---------|---------|
| `playing == true` | 暂停图标 | `player.pause()` |
| `paused`（未完成） | 播放图标 | `player.play()` |
| `completed` | 播放图标 | `player.seek(Duration.zero)` + `player.play()` |
| 无音频源 | 播放图标 | 导航到 /player |

---

## 4. Timer — 定时器

### 4.1 状态枚举

| 状态 | 含义 |
|------|------|
| `null`（inactive） | 无定时器 |
| `duration` | 固定时长倒计时中 |
| `paused` | 已暂停，保留剩余时间 |
| `afterCurrent` | 当前曲目播完即停 |

### 4.2 转移表

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `null` | `startDuration(min)` | min ≥ 0 | 创建 endTime = now + min | `duration` | 保存自定义时长到 prefs |
| `duration` | `startDuration(min)` | min ≥ 0 | 替换为新 endTime | `duration` | 旧定时器被替换 |
| `afterCurrent` | `startDuration(min)` | min ≥ 0 | 替换状态 | `duration` | — |
| `paused` | `startDuration(min)` | min ≥ 0 | 替换状态 | `duration` | 丢失剩余时间 |
| `null` | `startAfterCurrent()` | — | 创建 afterCurrent 状态 | `afterCurrent` | — |
| `duration` | `startAfterCurrent()` | — | 替换状态 | `afterCurrent` | — |
| `afterCurrent` | `startAfterCurrent()` | — | 替换状态 | `afterCurrent` | — |
| `paused` | `startAfterCurrent()` | — | 替换状态 | `afterCurrent` | — |
| `duration` | `pause()` | — | 保存 remainingMs | `paused` | — |
| `null` | `pause()` | — | 无操作，返回 false | `null` | — |
| `afterCurrent` | `pause()` | — | 无操作，返回 false | `afterCurrent` | — |
| `paused` | `pause()` | — | 无操作，返回 false | `paused` | — |
| `paused` | `resume()` | — | 从 remainingMs 计算新 endTime | `duration` | 向上取整到分钟 |
| `null` | `resume()` | — | 无操作，返回 false | `null` | — |
| `duration` | `resume()` | — | 无操作，返回 false | `duration` | — |
| `afterCurrent` | `resume()` | — | 无操作，返回 false | `afterCurrent` | — |
| `duration` | `checkExpired()` | endTime ≤ now | 清空状态 | `null` | 返回 true，调用方 pause |
| `duration` | `checkExpired()` | endTime > now | 无操作 | `duration` | 返回 false |
| `afterCurrent` | `checkExpired()` | — | 无操作 | `afterCurrent` | 返回 false |
| `afterCurrent` | `onTrackCompleted()` | — | 清空状态 | `null` | 返回 true，调用方 pause |
| `duration` | `onTrackCompleted()` | — | 无操作 | `duration` | 返回 false |
| 任意 | `cancel()` | — | 清空状态 | `null` | 幂等，返回是否有活跃定时器 |

### 4.3 到期检测链路

**时长定时器**：
```
HomeScreen/PlayerScreen Timer.periodic (每1秒)
  → checkTimerExpiryProvider()
    → timerService.checkExpired()
      → 到期 → player.pause()
```

App 从后台恢复时立即检查一次，避免后台期间到期延迟。

**播完当前**：
```
processingStateStream 发出 completed
  → onTrackCompletedProvider()
    → timerService.onTrackCompleted()
      → afterCurrent 模式 → player.pause()
```

### 4.4 不变量

- 同一时刻最多一个定时器活跃
- 新定时器总是替换旧定时器（替换语义）
- `cancel()` 幂等
- `afterCurrent` 模式不能暂停
- `resume()` 向上取整到分钟（有精度损失）

---

## 5. Progress — 进度记忆

### 5.1 进度记录生命周期

**每文件状态**：

| 状态 | 含义 |
|------|------|
| `NoRecord` | 无记录 |
| `Saved` | 有记录，positionMs ≥ 5000 且未接近结尾 |
| `Skipped` | positionMs < 5000，不保存（不持久化） |
| `Cleared` | positionMs > durationMs - 10000，记录已删除 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `NoRecord` | `upsert()` | positionMs < 5000 | 跳过 | `NoRecord` | — |
| `NoRecord` | `upsert()` | positionMs ≥ 5000 且未接近结尾 | INSERT | `Saved` | 刷新相关 provider |
| `NoRecord` | `upsert()` | positionMs ≥ 5000 且接近结尾 | 无操作 | `NoRecord` | — |
| `Saved` | `upsert()` | positionMs < 5000 | 跳过 | `Saved` | — |
| `Saved` | `upsert()` | positionMs ≥ 5000 且未接近结尾 | UPSERT | `Saved` | 刷新相关 provider |
| `Saved` | `upsert()` | positionMs > durationMs - 10000 | DELETE | `Cleared` | 刷新相关 provider |
| `Saved` | `delete()` | — | DELETE | `NoRecord` | 刷新相关 provider |

### 5.2 智能过滤规则

| 规则 | 条件 | 行为 |
|------|------|------|
| 跳过短位置 | positionMs < 5000 | 不保存 |
| 清理已听完 | positionMs > durationMs - 10000 | 删除记录 |
| 保护短文件 | durationMs ≤ 10000 | 永不自动清理 |
| 未知时长 | durationMs == null | 永不自动清理 |

### 5.3 五个保存触发点

| # | 触发点 | 机制 |
|---|--------|------|
| 1 | 每 10 秒 | Timer.periodic → saveProgress |
| 2 | 暂停 | playerStateStream 监听 playing→paused |
| 3 | 切歌 | skipToNext/Previous/selectIndex 前保存 |
| 4 | App 后台 | didChangeAppLifecycleState(paused) |
| 5 | 页面 dispose | dispose() 中保存 |

### 5.4 恢复对话框状态机

**状态**：

| 状态 | 含义 |
|------|------|
| `Hidden` | 无对话框 |
| `Showing` | 倒计时中，countdownSeconds ∈ [1, 5] |
| `Expired` | 倒计时归零，自动选择 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Hidden` | `showProgressResumeDialog()` | — | 启动 1s 倒计时 | `Showing` | — |
| `Showing` | 1 秒 tick | countdown > 1 | 递减 | `Showing` | — |
| `Showing` | 1 秒 tick | countdown == 1 | 设为 0，取消定时器 | `Expired` | — |
| `Expired` | Widget rebuild | — | Navigator.pop(true) | `Hidden` | 自动选择"继续播放" |
| `Showing` | 用户点击"继续播放" | — | Navigator.pop(true) | `Hidden` | — |
| `Showing` | 用户点击"从头播放" | — | Navigator.pop(false) | `Hidden` | — |
| `Showing` | 状态被外部清空 | — | Navigator.pop(null) | `Hidden` | — |

**不变量**：
- 对话框不可通过 barrier 关闭
- 倒计时始终为 5 秒
- ProgressResumeNotifier 在 dispose 时取消定时器

---

## 6. Playlist — 播放单

### 6.1 播放单列表状态机

**状态**：

| 状态 | 含义 |
|------|------|
| `Loading` | 数据加载中，骨架屏 |
| `Error` | 加载失败 |
| `Empty` | 无播放单 |
| `Data` | 有播放单列表 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Data` | FAB 创建 | 名称非空 | INSERT 播放单 | 刷新列表 | — |
| `Data` | 左滑删除 | 用户确认 | DELETE (CASCADE) | 刷新列表 | — |
| `Data` | 点击播放单 | — | 导航到详情页 | — | — |

### 6.2 播放单详情状态机

**选择模式**：

| 状态 | 含义 |
|------|------|
| `Normal` | 普通模式，可点击播放、长按选择 |
| `Selecting` | 选择模式，有选中项 |
| `SelectingEmpty` | 选择模式但无选中项 → 自动退出 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Normal` | 长按曲目 | — | 设 selectionMode=true，添加到选中集 | `Selecting` | AppBar 切换 |
| `Selecting` | 点击未选中曲目 | — | 添加到选中集 | `Selecting` | — |
| `Selecting` | 点击已选中曲目 | 选中集 > 1 | 从选中集移除 | `Selecting` | — |
| `Selecting` | 点击已选中曲目 | 选中集变为 0 | 退出选择模式 | `Normal` | AppBar 恢复 |
| `Selecting` | 点击关闭按钮 | — | 退出选择模式 | `Normal` | — |
| `Selecting` | 点击"全选" | — | 添加所有 ID | `Selecting` | — |
| `Selecting` | 点击"取消全选" | — | 清空选中集 → 退出 | `Normal` | — |
| `Selecting` | 确认删除 | — | 删除选中曲目 | `Normal` | DB 删除 |

### 6.3 播放单 CRUD

| 操作 | 前置条件 | 动作 | 副作用 |
|------|---------|------|--------|
| 创建 | 名称非空 | INSERT | 刷新列表 |
| 删除 | 用户确认 | DELETE (CASCADE) | 刷新列表 |
| 重命名 | 新名称 ≠ 旧名称 | UPDATE | 刷新列表 |
| 添加曲目 | — | INSERT（按 filePath 去重） | 刷新详情 + 列表 |
| 删除曲目 | 用户确认 | DELETE by IDs | 刷新详情 + 列表 |
| 排序曲目 | 排序方式 = addedAsc | 批量重写 added_at 时间戳 | 刷新详情 |

### 6.4 从播放单播放

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `Normal` | 点击曲目 | 无保存进度 | 构建 PlayQueue，导航到 /player | — | 设置 currentPlayQueueProvider |
| `Normal` | 点击曲目 | 有进度且 ≥ 5s | 弹出恢复对话框 | 等待对话框 | — |
| 等待对话框 | 返回 true | — | startPositionMs = 进度位置 | — | 设置队列 + 导航 |
| 等待对话框 | 返回 false | — | startPositionMs = null | — | 设置队列 + 导航 |

### 6.5 导入导出

| 操作 | 前置条件 | 动作 | 副作用 |
|------|---------|------|--------|
| 导出 | 播放单存在 | 序列化为 JSON 字符串 | — |
| 导入 | JSON 合法 | 创建播放单 + 去重插入曲目 | 刷新列表 |

**不变量**：
- 播放单名称不要求唯一
- 添加曲目按 filePath 去重
- 排序仅在 addedAsc 模式下可用
- 排序重写所有 added_at 时间戳

---

## 7. Home — 主页

### 7.1 Tab 导航

**状态**：

| 状态 | 含义 |
|------|------|
| `PlaylistsTab` | Tab 0，显示播放单列表 |
| `BrowserTab` | Tab 1，显示文件浏览器 |

**转移表**：

| 从 | 触发 | 前置条件 | 动作 | 到 | 副作用 |
|----|------|---------|------|----|--------|
| `PlaylistsTab` | 用户切换 Tab | — | 切换到 Tab 1 | `BrowserTab` | 保存 Tab 索引到 prefs |
| `BrowserTab` | 用户切换 Tab | — | 切换到 Tab 0 | `PlaylistsTab` | 保存 Tab 索引到 prefs |
| App 启动 | — | prefs 有保存的索引 | 恢复 Tab | 对应 Tab | — |

### 7.2 PopScope 行为

系统返回键拦截：`moveTaskToBack()`（App 移到后台，不退出）。

### 7.3 定时器到期轮询

| 触发 | 前置条件 | 动作 | 副作用 |
|------|---------|------|--------|
| 1 秒定时 tick | checkExpired 返回 true | player.pause() | 播放停止 |
| App 恢复前台 | checkExpired 返回 true | player.pause() | 捕获后台期间到期 |

### 7.4 排序菜单

| Tab | 排序 Provider | 选项 |
|-----|--------------|------|
| Tab 0 | playlistSortProvider | createdAsc/Desc, nameAsc/Desc |
| Tab 1 | sortOptionProvider | nameAsc/Desc, modifiedDesc |

---

## 8. 路由状态机

### 8.1 路由表

| 路径 | 页面 | 导航方式 |
|------|------|----------|
| `/onboarding` | 启动引导 | `context.go()` (初始路由) |
| `/connection` | 添加连接 | `context.push()` |
| `/connections` | 连接列表 | `context.push()` |
| `/connections/edit/:id` | 编辑连接 | `context.push()` |
| `/browser` | 主页 | `context.go()` |
| `/player` | 全屏播放器 | `context.push()` |
| `/settings` | 设置 | `context.push()` |
| `/about` | 关于 | `context.push()` |
| `/logs` (debug) | 日志查看 | `context.push()` |

### 8.2 路由状态转移图

```
APP START
  │
  ▼
/onboarding ──(无连接)──▶ /connection ──(保存成功)──▶ /browser
  │                          ▲
  ├──(有连接+验证失败)─────────┘
  │
  └──(有连接+验证成功)──▶ /browser
                            │
                            ├── 点播放栏/歌曲 ──▶ /player
                            ├── 设置齿轮 ──▶ /connections ──▶ /connections/edit/:id
                            └── 设置齿轮 ──▶ /settings ──▶ /about
                                                         └── /logs (debug)
```

### 8.3 导航语义

- `context.go()` — 替换整个路由栈（无法 back 回上一页）
- `context.push()` — 压入路由栈（可 back 返回）
- `context.pop()` — 弹出当前页面

---

## 9. 跨模块交互

### 9.1 全局状态桥接

```
              ┌──────────────────┐
              │ currentPlayQueue │ ←── 全局单例 StateProvider
              │ Provider         │
              └──────┬───────────┘
                     │
        ┌────────────┼────────────────┐
        │            │                │
  Browser.onFileTap  Playlist.onTrackTap  Startup.restore
        │            │                │
        └────────────┼────────────────┘
                     │
                     ▼
              PlayerScreen
              (读取 queue → 构建 AudioSource → 播放)
                     │
              ┌──────┴───────┐
              │              │
        MiniPlayerBar   通知栏控件
```

### 9.2 Timer → Player 触发链路

```
时长定时器：
  HomeScreen/PlayerScreen (每1秒) → checkExpired() → 到期 → player.pause()

播完当前：
  processingStateStream (completed) → onTrackCompleted() → afterCurrent → player.pause()
```

### 9.3 Progress → Player 恢复链路

```
App 启动
  → restoreStartupProgressProvider
    → dao.findLatest()
      → 有进度 → 构建 PlayQueue(startPositionMs: progress.positionMs)
        → currentPlayQueueProvider = queue
          → PlayerScreen 读取 .startPositionMs → player.seek()
```

### 9.4 Connection 切换影响面

```
setActiveConnection(newId)
  → invalidate: activeConnectionProvider, connectionListProvider
  → clearDirectoryCache (cache key 含 connectionId)
  → 导航栈回到 /browser

如果 queue.lastQueueConnectionId != newActiveConnection.id:
  → 清空 currentPlayQueueProvider
  → MiniPlayerBar 隐藏
```

### 9.5 关键共享 Provider

| Provider | 写入方 | 读取方 |
|----------|--------|--------|
| currentPlayQueueProvider | Browser, Playlist Detail | Player, MiniPlayerBar, Browser (持久化) |
| lastQueueConnectionIdProvider | Browser, Playlist Detail | Browser (连接切换检查, 持久化) |
| activeConnectionProvider | Connection 模块 | Browser, Playlist, Player |
| sharedPreferencesProvider | main.dart 覆盖 | Browser (排序, 队列), Timer, Home |
| audioPlayerProvider | Player 模块 | Home (定时暂停), Browser (启动预加载) |

---

## 附录：测试覆盖对照表

每个转移都应有对应测试。格式：`模块-编号: 转移描述 → 测试文件`

（此表在 Phase 7 测试覆盖审计时逐条填写）
