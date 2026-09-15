/// 值对象：采摘时间区间、芽叶级配、重量。
library;

import '../receiving_errors.dart';

/// 采摘时间只有区间时（茶农无法给出精确时刻）使用 [start]/[end] 表达；
/// 若知道精确时刻，令 start == end。
class TimeInterval {
  const TimeInterval({required this.start, required this.end});

  factory TimeInterval.point(DateTime t) => TimeInterval(start: t, end: t);

  final DateTime start;
  final DateTime end;

  /// 区间中最早时刻。采后时长用它做"最乐观"估计。
  DateTime get earliest => start.isBefore(end) ? start : end;

  /// 区间中最晚时刻。采后时长用它做"最保守"估计。
  DateTime get latest => start.isBefore(end) ? end : start;

  bool get isPoint => start == end;

  /// 从到达时刻算的采后时长区间（小时，保留两位小数）。
  ({double minHours, double maxHours}) postHarvestHours(DateTime arrivedAt) {
    final ms = arrivedAt.difference(latest).inMinutes;
    final me = arrivedAt.difference(earliest).inMinutes;
    return (
      minHours: double.parse((ms / 60).toStringAsFixed(2)),
      maxHours: double.parse((me / 60).toStringAsFixed(2)),
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  factory TimeInterval.fromJson(Map<String, dynamic> j) => TimeInterval(
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
      );
}

/// 芽叶级配中的一个组分（如 单芽 62%）。
///
/// [name] 允许使用各茶园自定义称呼；份额是抽样实测的组成事实，
/// 不映射到任何收购等级，系统不据此定级。
class GradeShare {
  const GradeShare({required this.name, required this.percent});

  final String name;

  /// 百分比，0..100。
  final double percent;

  Map<String, dynamic> toJson() => {'name': name, 'percent': percent};

  factory GradeShare.fromJson(Map<String, dynamic> j) => GradeShare(
        name: j['name'] as String,
        percent: (j['percent'] as num).toDouble(),
      );
}

/// 校验级配合计是否为 100%（允许 [tolerance] 误差）。
void validateGradeShares(List<GradeShare> shares, {double tolerance = 2.0}) {
  if (shares.isEmpty) {
    throw ReceivingValidationError('芽叶级配不能为空');
  }
  final sum = shares.fold<double>(0, (a, s) => a + s.percent);
  if (sum < 100 - tolerance || sum > 100 + tolerance) {
    throw ReceivingValidationError(
      '芽叶级配合计 ${sum.toStringAsFixed(1)}%，'
      '应在 ${100 - tolerance}%~${100 + tolerance}% 之间',
    );
  }
}
