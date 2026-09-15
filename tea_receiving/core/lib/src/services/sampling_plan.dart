/// 随机抽样计划。
///
/// 收青员按系统给出的随机位置抽取小样；抽完后把实际位置/时间回填，
/// ReceivingService 据此核对"抽样覆盖"。系统不挑选好位置，也不跳过篓底。
library;

import 'dart:math' as math;

import '../domain/enums.dart';

class SamplePoint {
  const SamplePoint({
    required this.lotId,
    required this.position,
    required this.x,
    required this.y,
  });

  final String lotId;
  final SamplePosition position;

  /// 0..1 的平面坐标：摊放匾/车厢平面上的随机点。
  final double x;
  final double y;

  @override
  String toString() =>
      '${position.label}(${x.toStringAsFixed(2)},${y.toStringAsFixed(2)})';
}

class SamplingPlan {
  SamplingPlan({
    required this.batchId,
    required this.points,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String batchId;
  final List<SamplePoint> points;
  final DateTime createdAt;
}

/// 随机源抽象（测试注入固定序列）。
abstract class RandomProvider {
  double nextDouble();
}

class DefaultRandom implements RandomProvider {
  DefaultRandom([int? seed]) : _r = math.Random(seed);
  final math.Random _r;
  @override
  double nextDouble() => _r.nextDouble();
}

/// 默认覆盖：篓面、中层、篓底、边缘、中心。
/// 先摊后登记时，"篓底/中层"可能已不存在，改为摊放匾(spreadTray)上的不同
/// 随机点，但点数不少于配置要求。
class SamplingPlanner {
  const SamplingPlanner({
    this.minSamples = 5,
    this.maxSamples = 12,
    RandomProvider? random,
  }) : _random = random;

  final int minSamples;
  final int maxSamples;
  final RandomProvider? _random;

  SamplingPlan plan({
    required String batchId,
    required List<String> lotIds,
    required int sampleCount,
    required bool alreadySpread,
    DateTime? now,
  }) {
    if (lotIds.isEmpty) {
      throw ArgumentError('至少需要一个鲜叶票才能制定抽样计划');
    }
    final n = sampleCount.clamp(minSamples, maxSamples);
    final rnd = _random ?? DefaultRandom();
    final points = <SamplePoint>[];

    final cover = <SamplePosition>[];
    if (alreadySpread) {
      cover.addAll(const [
        SamplePosition.spreadTray,
        SamplePosition.edge,
        SamplePosition.center,
        SamplePosition.spreadTray,
        SamplePosition.edge,
      ]);
    } else {
      cover.addAll(const [
        SamplePosition.top,
        SamplePosition.middle,
        SamplePosition.bottom,
        SamplePosition.edge,
        SamplePosition.center,
      ]);
    }
    while (cover.length < maxSamples) {
      cover.add(alreadySpread
          ? SamplePosition.spreadTray
          : SamplePosition.bottom);
    }

    // 多 lot 轮转：混装时每个茶园都必须被抽到。
    for (var i = 0; i < n; i++) {
      points.add(SamplePoint(
        lotId: lotIds[i % lotIds.length],
        position: cover[i % cover.length],
        x: double.parse(rnd.nextDouble().toStringAsFixed(2)),
        y: double.parse(rnd.nextDouble().toStringAsFixed(2)),
      ));
    }
    return SamplingPlan(batchId: batchId, points: points, createdAt: now);
  }
}
