# BUG-11 — WebDAV XML 解析不做实体反转义

> 来源：`docs/cr/cr-20260724-0110.md` NET2
> dev-plan 流程：Bug 修复模式

---

## §0 头部元数据

```yaml
id: BUG-11
name: WebDAV XML 解析不做实体反转义
priority: P1
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/core/network/webdav_client.dart
cross_module_impacts: [BRW]
parent_feature: null  # core/network，影响 Browser 文件列表显示
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md NET2：_extractXmlContent 直接返回 match.group(1) 无反转义。合规服务器必须将 & 写成 &amp;，导致文件名含 & 时显示乱码、href 中 & 被转义后导航 404。

### 1.1 这一功能干什么（一句话）

修复 WebDAV XML 响应中文件名含特殊字符（&、<、> 等）时显示乱码和导航失败的缺陷。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | NAS 上有文件 `Simon & Garfunkel - xxx.mp3` | 浏览器显示 `Simon & Garfunkel - xxx.mp3`（不是 `&amp;`） |
| U2 | NAS 上有目录 `Rock < Classics` | 浏览器显示 `Rock < Classics`，点击可正常进入 |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| Core Network | `lib/core/network/webdav_client.dart` | ~430 | WebDAV PROPFIND 客户端 |

---

## §3 行为规约

### 3.1 修复后行为

- **[BUG-11-S1]** XML 文本统一做五个预定义实体反转义 (`status: new`)
  ```
  Given _extractXmlContent 提取出 XML 文本内容
  When  返回给调用方前
  Then  统一替换 &amp; → &, &lt; → <, &gt; → >, &apos; → ', &quot; → "
  否定断言:
    - 不返回含 XML 实体的原始文本（当前 BUG 行为）
    - 不做额外解码（Uri.decodeFull 是 URL 解码，不负责 XML 实体）
    - 不影响 href 属性的 URL 编码处理（href 走 Uri.decodeFull，displayname 走 XML 反转义）
  ```
  Code evidence: `lib/core/network/webdav_client.dart:409-427`（_extractXmlContent 无反转义）

  #### 修改指令

  **修改点 1：新增 XML 实体反转义辅助函数**

  文件：`lib/core/network/webdav_client.dart`

  在 `_extractXmlContent` 方法之前（约 `:408` 位置），新增静态方法：

  ```dart
  static String _unescapeXmlEntities(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
  }
  ```

  变更说明：
  - 仅处理 XML 五个预定义实体（`&amp;` `&lt;` `&gt;` `&apos;` `&quot;`）。
  - `&amp;` 必须最后替换，避免二次解码（如 `&amp;lt;` → `&lt;` 而非 `<`）。
  - 不含实体的文本原样返回（所有 replaceAll 无匹配 → 零开销）。

  **修改点 2：在 _extractXmlContent 返回值前调用反转义**

  文件：`lib/core/network/webdav_client.dart:417`

  当前代码：
  ```dart
    if (match != null) return match.group(1)?.trim();
  ```

  改为：
  ```dart
    if (match != null) {
      final raw = match.group(1)?.trim();
      return raw != null ? _unescapeXmlEntities(raw) : null;
    }
  ```

  变更说明：提取文本后、返回前，统一做 XML 实体反转义。self-closing 分支（`:424` 返回 `''`）无需处理（空串无实体）。

  **边界裁决：**
  - 无实体文本 `hello` → `replaceAll` 全部无匹配 → 返回 `hello`，无变化。
  - 混合实体 `Simon &amp; Garfunkel &lt;Live&gt;` → `Simon & Garfunkel <Live>`。
  - 转义的 &amp; `&amp;lt;` → `&lt;`（字面量，非 `<`）——`&amp;` 最后替换保证正确。
  - 空串 `''` → 返回 `''`（self-closing 分支，不经过反转义）。
  - `null`（标签不存在）→ 返回 `null`（不经过反转义）。
  - href 字段也经过此函数 → href 中的 `&amp;` 变为 `&`，后续 `Uri.decodeFull` 处理 URL 编码，两者互不干扰（XML 实体解码 ≠ URL 解码）。

  **测试文件位置：** `test/features/browser/bug_11_test.dart`

---

## §4 不变量

- **[BUG-11-INV1]** displayname 经 XML 实体反转义后作为 NasFile.name
  证据：`webdav_client.dart:409-427`（提取）→ NasFile 构造

---

## §5 测试规约

### 5.2 测试 ID 派生清单

```
BUG-11-S1           # XML 实体反转义
BUG-11-INV1         # displayname 正确显示
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| BUG-11-S1 | BRW-T06 只覆盖百分号编码，零 XML 实体用例 | 补 &amp;/&lt;/&gt;/&apos;/&quot; 各一条 |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| BUG-11-S1 | `test/features/browser/bug_11_test.dart` |
| BUG-11-INV1 | `test/features/browser/bug_11_test.dart` |

---

## §7 跨模块影响

| 其它 feature | 影响点 | 影响条件 | 需要补的回归断言 |
|---|---|---|---|
| BRW | NasFile.name 显示 | 文件名含 & < > 等特殊字符 | 显示正确，导航不 404 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 BUG-11 spec（基于 cr-20260724-0110.md NET2）
