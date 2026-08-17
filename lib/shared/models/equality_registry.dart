// lib/shared/models/equality_registry.dart
// REF-02 值对象相等性统一规则与集中登记（cr-20260816-0801 D2 裁决落地）。
//
// 统一规则:
//   1. 默认入等: 值对象新增任何字段必须同时进入 == 与 hashCode，
//      并与 copyWith / fromMap·toMap 同步（四同步不变量）。
//   2. 例外资格仅限两类字段: 自增 DB 主键 (id)；审计时间戳
//      (createdAt / updatedAt / lastPlayedAt / addedAt)。
//      内容时间戳（如 NasFile.modifiedAt）永远入等。
//   3. 例外裁决: 相等性 = 业务身份字段集；选择"除外"必须同时满足
//      (a) 登记进本文件 entries 表；(b) 有否定断言测试锚定
//      （"该字段不同仍相等"）。
//   4. 本表是唯一登记点: dev-plan / dev-check / cr 以此核对各模型 == 实现。

/// 单条登记：模型名 / 入等字段（逗号分隔）/ 除外字段 + 理由。
class EqualityRule {
  final String model;
  final String equalityFields;
  final String exclusions;

  const EqualityRule(this.model, this.equalityFields, this.exclusions);
}

/// 共享值对象相等性集中登记表（与各模型 == 实现逐条一致，REF-02-INV2）。
class EqualityRegistry {
  const EqualityRegistry._();

  static const List<EqualityRule> entries = [
    EqualityRule(
        'ConnectionConfig',
        'id,name,url,username,basePath,isActive,createdAt,updatedAt',
        '无（全 8 字段入等，REF-07 锚定）'),
    EqualityRule('PlayProgress', 'connectionId,filePath,positionMs,durationMs',
        'id（DB 自增主键）; lastPlayedAt（审计时间戳）'),
    EqualityRule(
        'Playlist', 'id,name,trackCount', 'createdAt,updatedAt（审计时间戳）'),
    EqualityRule(
        'PlaylistTrack', 'id,playlistId,filePath,fileName', 'addedAt（审计时间戳）'),
    EqualityRule('NasFile', 'name,path,isDirectory,size,modifiedAt,audioType',
        '无（modifiedAt 为内容时间戳，必入等）'),
    EqualityRule(
        'PlayQueue',
        'files,currentIndex,startPositionMs,playMode,_shuffleOrder,_shufflePosition',
        '无（全字段入等）'),
  ];
}
