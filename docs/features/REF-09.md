# REF-09 — _SectionHeader 共享组件提取（SET4）

> 来源：`docs/cr/cr-20260724-0110.md` SET4
> dev-plan 流程：Refactoring 模式

---

## §0 头部元数据

```yaml
id: REF-09
name: _SectionHeader 共享组件提取（SET4）
priority: P2
status: draft
created_at: 2026-07-27
last_updated: 2026-07-27
spec_anchored_files:
  - lib/features/settings/settings_screen.dart
  - lib/features/settings/about_screen.dart
cross_module_impacts: []
parent_feature: Settings
manual_qa_required: false
```

---

## §1 用户视角

### 1.0 原始需求

> cr-20260724-0110.md SET4：`settings_screen.dart:87-106` and `about_screen.dart:103-122` have identical private `_SectionHeader` widget.

### 1.1 这一功能干什么（一句话）

将两处重复的 `_SectionHeader` 私有组件提取为共享 widget，消除代码重复。

### 1.2 用户期望的场景

| ID | 你看到的样子 | 期望行为 |
|----|----|----|
| U1 | 设置页各分区标题 | 外观不变（字号/颜色/间距与当前一致） |
| U2 | 关于页分区标题 | 外观不变（与设置页共用同一组件） |

---

## §2 已实现的功能骨架

### 2.1 文件与分层

| 层 | 文件 | 行数 | 角色 |
|---|---|---|---|
| UI | `lib/features/settings/settings_screen.dart` | 280 | 设置页（含私有 _SectionHeader） |
| UI | `lib/features/settings/about_screen.dart` | 153 | 关于页（含私有 _SectionHeader） |
| UI (新增) | `lib/features/settings/widgets/section_header.dart` | — | 共享 SectionHeader widget |

### 2.2 关键代码段

| 区域 | 行号 | 说明 |
|---|---|---|
| settings_screen _SectionHeader | `settings_screen.dart:87-106` | 私有 widget，20 行 |
| about_screen _SectionHeader | `about_screen.dart:103-122` | 完全相同的私有 widget，20 行 |
| settings_screen 使用点 | `settings_screen.dart:31,39,45,57,63` | 5 处 `_SectionHeader` |
| about_screen 使用点 | `about_screen.dart:61` | 1 处 `_SectionHeader` |

---

## §3 行为规约

### 3.1 提取共享组件

- **[REF-09-S1]** 提取 SectionHeader 为公共 widget (`status: new`)
  ```
  Given settings_screen.dart:87-106 和 about_screen.dart:103-122 代码完全相同
  When  提取到 widgets/section_header.dart
  Then  新文件包含 public SectionHeader widget（无下划线前缀）
  And   settings_screen.dart 删除私有 _SectionHeader 并 import 新文件
  And   about_screen.dart 删除私有 _SectionHeader 并 import 新文件
  否定断言:
    - 不改变 SectionHeader 的视觉效果（padding / fontSize / fontWeight / color 保持原值）
    - 不改变 settings_screen.dart 的 5 处使用点（仅替换类名）
    - 不改变 about_screen.dart 的 1 处使用点（仅替换类名）
    - 不引入其它文件对 SectionHeader 的依赖（当前仅这两个页面使用）
  ```
  Code evidence: `lib/features/settings/settings_screen.dart:87-106`；`lib/features/settings/about_screen.dart:103-122`（两段代码逐行相同）

  **修改指令 — 新建 `lib/features/settings/widgets/section_header.dart`**

  ```dart
  import 'package:flutter/material.dart';

  class SectionHeader extends StatelessWidget {
    final String title;

    const SectionHeader({super.key, required this.title});

    @override
    Widget build(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
  }
  ```

  **修改指令 — `lib/features/settings/settings_screen.dart`**

  位置：`:10-16`（import 区）— 添加：
  ```dart
  import 'widgets/section_header.dart';
  ```

  位置：`:87-106` — 删除整个 `_SectionHeader` 类定义。

  位置：`:31,39,45,57,63` — 将所有 `_SectionHeader` 替换为 `SectionHeader`。

  **修改指令 — `lib/features/settings/about_screen.dart`**

  位置：`:6`（import 区）— 添加：
  ```dart
  import 'widgets/section_header.dart';
  ```

  位置：`:103-122` — 删除整个 `_SectionHeader` 类定义。

  位置：`:61` — 将 `_SectionHeader` 替换为 `SectionHeader`。

---

## §4 不变量

- **[REF-09-INV1]** SectionHeader 仅定义一次
  证据：`widgets/section_header.dart` 为唯一定义；`settings_screen.dart` 和 `about_screen.dart` 不再有私有 _SectionHeader

- **[REF-09-INV2]** SectionHeader 视觉效果与重构前完全一致
  证据：padding(16,16,16,4) / fontSize:13 / fontWeight:w600 / color:primary 保持原值

---

## §5 测试规约

### 5.1 现有测试清单

| 测试文件 | 覆盖 | 备注 |
|---|---|---|
| `test/features/settings/` | Settings 相关测试 | 需检查是否有依赖 _SectionHeader 私有类的测试 |

### 5.2 测试 ID 派生清单

```
REF-09-S1           # 提取共享 SectionHeader
REF-09-INV1         # 唯一定义
REF-09-INV2         # 视觉一致
```

### 5.3 测试覆盖盲点

| 未覆盖 ID | 现状 | 应补偿方式 |
|---|---|---|
| REF-09-S1 | widget 提取为纯 UI 重构 | 可选：widget test 验证 SectionHeader 渲染正确（Text + Padding + 样式） |

### 5.4 测试文件位置

| 测试 ID | 文件路径 |
|---|---|
| REF-09-S1 | `test/features/settings/settings_test.dart`（设置页现有 widget 测试兜底视觉一致） |
| REF-09-S1 | `test/features/settings/settings_test.dart`（可选新增 SectionHeader 渲染断言） |

---

## §6 算法样例

不适用——纯 UI 组件提取，无算法。

---

## §7 跨模块影响

| 其它 feature | 影响点 | 需要补的回归断言 |
|---|---|---|
| 无 | — | 仅影响 Settings 模块内部 |

---

## §8 平台特性与手动 QA

本功能不涉及平台原生特性，全部可在 `flutter test` 中验证。

---

## §9 dev-status.json 条目对照

见统一更新：`docs/dev/dev-status.json`。

---

## §10 changelog

- 2026-07-27: 创建 REF-09 spec（基于 cr-20260724-0110.md SET4）
- 2026-08-06: dev-plan 修订——补 §5.4「测试文件位置」门禁节（spec-scan --gate 硬门禁前置，af084af 引入）；门禁文件 = settings_test.dart（现有设置页 widget 测试兜底）
