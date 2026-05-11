# Connection 模块功能设计

## 1. 模块概述

Connection 模块负责管理 NAS 的 WebDAV 连接配置，包括服务器信息的录入、连接验证、配置持久化，以及多账号管理的扩展支持。

---

## 2. 功能列表

| 功能编号 | 功能名称 | 优先级 |
|----------|----------|--------|
| CON-01 | 添加 WebDAV 连接 | P0 |
| CON-02 | 连接验证 | P0 |
| CON-03 | 连接配置持久化 | P0 |
| CON-04 | 切换当前连接 | P1 |
| CON-05 | 编辑连接配置 | P1 |
| CON-06 | 删除连接配置 | P1 |

---

## 3. 功能详细设计

### CON-01 添加 WebDAV 连接

**入口：** 首次启动引导页 / 设置页 → 添加连接

**输入字段：**
- 服务器地址（必填）：如 `http://192.168.1.100:5005` 或 `https://nas.example.com`
- 用户名（必填）
- 密码（必填）
- 显示名称（选填，默认取主机名）
- 基础路径（选填，默认 `/`，用于指定音乐根目录）

**交互流程：**
```
用户填写表单 → 点击"测试连接" → 显示连接中状态
    → 成功：显示绿色提示，激活"保存"按钮
    → 失败：显示错误原因（网络不通 / 认证失败 / 路径不存在）
用户点击"保存" → 写入数据库 → 跳转文件浏览页
```

**实现要点：**
- 地址自动补全协议前缀（用户输入 IP 时自动加 `http://`）
- 密码字段默认隐藏，可切换显示
- 保存前必须通过连接验证

---

### CON-02 连接验证

**触发时机：** 用户点击"测试连接"按钮，或应用启动时自动验证已保存连接

**验证步骤：**
1. 检查地址格式合法性（正则校验）
2. 发起 WebDAV `PROPFIND` 请求到基础路径
3. 解析响应状态码：
   - `207 Multi-Status`：连接成功
   - `401 Unauthorized`：认证失败
   - `404 Not Found`：路径不存在
   - 连接超时（5秒）：网络不通

**错误提示文案：**
- 认证失败：「用户名或密码错误」
- 路径不存在：「基础路径不存在，请检查路径设置」
- 网络不通：「无法连接到服务器，请检查地址和网络」

---

### CON-03 连接配置持久化

**存储方案：** SQLite `connections` 表

```sql
CREATE TABLE connections (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    password    TEXT NOT NULL,  -- 加密存储（AES）
    base_path   TEXT NOT NULL DEFAULT '/',
    is_active   INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);
```

**密码安全：** 使用 `flutter_secure_storage` 存储密码，数据库只存引用 key，不存明文。

---

### CON-04 切换当前连接

**场景：** 用户配置了多个 NAS 账号，需要切换

**交互：** 设置页 → 连接列表 → 点击某连接 → 设为当前活跃连接

**实现：** 更新 `connections.is_active` 字段，同时清空文件浏览缓存，触发重新加载

---

### CON-05 编辑连接配置

**入口：** 连接列表 → 长按或右滑 → 编辑

**可编辑字段：** 所有字段均可修改

**保存逻辑：** 修改后需重新验证连接，验证通过才能保存

---

### CON-06 删除连接配置

**入口：** 连接列表 → 长按或右滑 → 删除

**保护逻辑：** 若只剩一个连接，不允许删除（提示「至少保留一个连接」）

**级联删除：** 删除连接时，同时删除该连接下的所有播放进度记录

---

## 4. 数据模型

```dart
class ConnectionConfig {
  final int? id;
  final String name;
  final String url;
  final String username;
  final String basePath;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

---

## 5. Provider 设计

```dart
// 当前活跃连接
@riverpod
Future<ConnectionConfig?> activeConnection(ActiveConnectionRef ref);

// 所有连接列表
@riverpod
Future<List<ConnectionConfig>> connectionList(ConnectionListRef ref);

// 连接验证状态
@riverpod
class ConnectionValidator extends _$ConnectionValidator {
  // state: idle / loading / success / error(message)
}
```

---

## 6. 关键文件

| 文件 | 职责 |
|------|------|
| `lib/features/connection/connection_screen.dart` | 连接配置 UI |
| `lib/features/connection/connection_provider.dart` | 连接状态管理 |
| `lib/core/database/dao/connection_dao.dart` | 数据库操作 |
| `lib/core/network/webdav_client.dart` | WebDAV 连接验证 |
| `lib/shared/models/connection_config.dart` | 数据模型 |
