import 'package:tea_core/tea_core.dart';

/// 固定时钟，保证采后时长可断言。
class FixedClock {
  FixedClock(this.t);
  DateTime t;
  DateTime call() => t;
}

class SequencedRandom implements RandomProvider {
  SequencedRandom(this.values);
  final List<double> values;
  int _i = 0;
  @override
  double nextDouble() => values[_i++ % values.length];
}

GardenBlock block(String id, String name, [String farmer = '茶农']) =>
    GardenBlock(id: id, name: name, farmerName: farmer);

LeafLot lot(
  String id,
  String blockId, {
  required DateTime pickStart,
  DateTime? pickEnd,
  PickingMethod method = PickingMethod.handOneBudOneLeaf,
  List<GradeShare> reported = const [],
}) =>
    LeafLot(
      id: id,
      blockId: blockId,
      picking: method,
      pickedAt: TimeInterval(start: pickStart, end: pickEnd ?? pickStart),
      reportedComposition: reported,
    );

ReceivingBatch batch(
  String id, {
  required DateTime arrived,
  DateTime? registered,
  DateTime? spreadAt,
}) =>
    ReceivingBatch(
      id: id,
      code: 'RC-P01-0001',
      pointId: 'P01',
      arrivedAt: arrived,
      registeredAt: registered,
      spreadStartedAt: spreadAt,
    );

Weighing weigh(
  String id, {
  required String batchId,
  required String basket,
  required double gross,
  double tare = 0.4,
  required DateTime at,
  int splitPart = 1,
}) =>
    Weighing(
      id: id,
      batchId: batchId,
      basketCode: basket,
      grossKg: gross,
      tareKg: tare,
      weighedAt: at,
      splitPart: splitPart,
    );

List<GradeShare> shares(double a, double b, double c) => [
      GradeShare(name: '单芽', percent: a),
      GradeShare(name: '一芽一叶', percent: b),
      GradeShare(name: '单片', percent: c),
    ];

Sample sample(
  String id, {
  required String batchId,
  required String lotId,
  required SamplePosition pos,
  List<GradeShare>? grades,
  SurfaceWater water = SurfaceWater.none,
  List<OffOdorType> odors = const [OffOdorType.none],
  RedDamageLevel red = RedDamageLevel.none,
  bool hotSpot = false,
  DateTime? at,
}) =>
    Sample(
      id: id,
      batchId: batchId,
      lotId: lotId,
      position: pos,
      drawnAt: at ?? DateTime(2026, 9, 15, 12),
      gradeShares: grades ?? shares(60, 30, 10),
      water: water,
      offOdors: odors,
      red: red,
      hotSpot: hotSpot,
    );
