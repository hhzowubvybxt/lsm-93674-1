import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('未摊开的计划覆盖篓面/中层/篓底/边缘/中心', () {
    final planner = SamplingPlanner(
      minSamples: 5,
      random: SequencedRandom(List.filled(40, 0.42)),
    );
    final plan = planner.plan(
      batchId: 'b1',
      lotIds: ['L1'],
      sampleCount: 5,
      alreadySpread: false,
    );
    final positions = plan.points.map((p) => p.position).toSet();
    expect(positions, containsAll([
      SamplePosition.top,
      SamplePosition.middle,
      SamplePosition.bottom,
      SamplePosition.edge,
      SamplePosition.center,
    ]));
    for (final p in plan.points) {
      expect(p.x, inInclusiveRange(0, 1));
      expect(p.y, inInclusiveRange(0, 1));
    }
  });

  test('混装时多张鲜叶票轮转抽样，每票至少一次', () {
    final planner = SamplingPlanner(
      random: SequencedRandom(List.filled(40, 0.1)),
    );
    final plan = planner.plan(
      batchId: 'b1',
      lotIds: ['LA', 'LB', 'LC'],
      sampleCount: 6,
      alreadySpread: true,
    );
    final lots = plan.points.map((p) => p.lotId).toSet();
    expect(lots, {'LA', 'LB', 'LC'});
    expect(
      plan.points.every((p) =>
          p.position == SamplePosition.spreadTray ||
          p.position == SamplePosition.edge ||
          p.position == SamplePosition.center),
      isTrue,
    );
  });

  test('点数被夹在 min/max 之间', () {
    const planner = SamplingPlanner(minSamples: 5, maxSamples: 8);
    final p1 = planner.plan(
        batchId: 'b', lotIds: ['L'], sampleCount: 2, alreadySpread: false);
    final p2 = planner.plan(
        batchId: 'b', lotIds: ['L'], sampleCount: 99, alreadySpread: false);
    expect(p1.points, hasLength(5));
    expect(p2.points, hasLength(8));
  });
}
