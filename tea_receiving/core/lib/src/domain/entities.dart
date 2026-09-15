/// 收青核心实体。
///
/// 设计原则：
/// 1. 从采摘到收青，每一票鲜叶的关键事实逐项保留（区块、采法、采摘时间区间、
///    运输容器、芽叶组成、红变损伤），称重后的大批平均值不回写覆盖这些局部事实；
/// 2. 多个茶园的鲜叶混装时，按"鲜叶票(lot)"分别登记，保留各自事实；
/// 3. 雨损标签走人工核对，照片留证、重贴新签；所有核对结果由人决定，
///    模型里没有等级字段、没有价格字段。
library;

import '../receiving_errors.dart';
import 'enums.dart';
import 'value_objects.dart';

/// 茶园区块（如"四号山 A-12 坡"）。
class GardenBlock {
  const GardenBlock({
    required this.id,
    required this.name,
    required this.farmerName,
    this.areaMu,
    this.note = '',
  });

  final String id;
  final String name;
  final String farmerName;
  final double? areaMu;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'farmerName': farmerName,
        'areaMu': areaMu,
        'note': note,
      };

  factory GardenBlock.fromJson(Map<String, dynamic> j) => GardenBlock(
        id: j['id'] as String,
        name: j['name'] as String,
        farmerName: j['farmerName'] as String,
        areaMu: (j['areaMu'] as num?)?.toDouble(),
        note: (j['note'] as String?) ?? '',
      );
}

/// 一票鲜叶：某区块、某采法、某采摘时间段产出的鲜叶。
///
/// 一个运输批可含多个 [LeafLot]（多茶园混装）。
/// [reportedComposition] 是茶农自述/采摘组记录的芽叶组成，
/// 收青抽样实测的芽叶级配登记在 [Sample] 上，二者互不覆盖。
class LeafLot {
  LeafLot({
    required this.id,
    required this.blockId,
    required this.picking,
    required this.pickedAt,
    this.harvestTeam,
    List<GradeShare>? reportedComposition,
    String? remark,
  })  : reportedComposition = reportedComposition ?? const [],
        remark = remark ?? '';

  final String id;
  final String blockId;
  final PickingMethod picking;
  final TimeInterval pickedAt;
  final String? harvestTeam;
  final List<GradeShare> reportedComposition;
  final String remark;

  Map<String, dynamic> toJson() => {
        'id': id,
        'blockId': blockId,
        'picking': picking.name,
        'pickedAt': pickedAt.toJson(),
        'harvestTeam': harvestTeam,
        'reportedComposition':
            reportedComposition.map((e) => e.toJson()).toList(),
        'remark': remark,
      };

  factory LeafLot.fromJson(Map<String, dynamic> j) => LeafLot(
        id: j['id'] as String,
        blockId: j['blockId'] as String,
        picking: PickingMethod.values.byName(j['picking'] as String),
        pickedAt:
            TimeInterval.fromJson(j['pickedAt'] as Map<String, dynamic>),
        harvestTeam: j['harvestTeam'] as String?,
        reportedComposition: (j['reportedComposition'] as List? ?? [])
            .map((e) => GradeShare.fromJson(e as Map<String, dynamic>))
            .toList(),
        remark: (j['remark'] as String?) ?? '',
      );
}

/// 竹篓/运输容器：二维码绑定的实体。
///
/// [code] 即二维码内容（形如 `TEA-BASKET/1/BK00123`）。
/// 标签受雨损坏时不重用旧码：[active] 置 false 并发新码、物理重贴，
/// 旧码的全部业务记录仍保留可追溯。
class Basket {
  Basket({
    required this.code,
    required this.container,
    this.tareKg = 0,
    this.active = true,
    this.issuedAt,
    this.note = '',
  });

  final String code;
  final ContainerType container;
  final double tareKg;
  final bool active;
  final DateTime? issuedAt;
  final String note;

  Basket copyWith({double? tareKg, bool? active, String? note}) => Basket(
        code: code,
        container: container,
        tareKg: tareKg ?? this.tareKg,
        active: active ?? this.active,
        issuedAt: issuedAt,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'container': container.name,
        'tareKg': tareKg,
        'active': active,
        'issuedAt': issuedAt?.toIso8601String(),
        'note': note,
      };

  factory Basket.fromJson(Map<String, dynamic> j) => Basket(
        code: j['code'] as String,
        container: ContainerType.values.byName(j['container'] as String),
        tareKg: (j['tareKg'] as num?)?.toDouble() ?? 0,
        active: (j['active'] as bool?) ?? true,
        issuedAt: j['issuedAt'] == null
            ? null
            : DateTime.parse(j['issuedAt'] as String),
        note: (j['note'] as String?) ?? '',
      );
}

/// 单次称量记录。
///
/// 一只竹篓允许分两次（或多次）称量：每次过秤都生成独立 [Weighing]，
/// 净重按记录相加，不用"大批平均净重"反推单篓。
/// [splitPart] 由收青员勾选"本次为分称（第几次）"，区分重复过秤。
class Weighing {
  Weighing({
    required this.id,
    required this.batchId,
    required this.basketCode,
    required this.grossKg,
    required this.tareKg,
    required this.weighedAt,
    this.scaleId,
    this.splitPart = 1,
    String? note,
  }) : note = note ?? '' {
    if (grossKg <= 0) {
      throw ReceivingValidationError('毛重必须为正数');
    }
    if (tareKg < 0 || tareKg > grossKg) {
      throw ReceivingValidationError('皮重应在 0 与毛重之间');
    }
  }

  final String id;
  final String batchId;
  final String basketCode;
  final double grossKg;
  final double tareKg;
  final int splitPart;
  final String? scaleId;
  final DateTime weighedAt;
  final String note;

  double get netKg =>
      double.parse((grossKg - tareKg).toStringAsFixed(3));

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        'basketCode': basketCode,
        'grossKg': grossKg,
        'tareKg': tareKg,
        'splitPart': splitPart,
        'scaleId': scaleId,
        'weighedAt': weighedAt.toIso8601String(),
        'note': note,
      };

  factory Weighing.fromJson(Map<String, dynamic> j) => Weighing(
        id: j['id'] as String,
        batchId: j['batchId'] as String,
        basketCode: j['basketCode'] as String,
        grossKg: (j['grossKg'] as num).toDouble(),
        tareKg: (j['tareKg'] as num).toDouble(),
        splitPart: (j['splitPart'] as int?) ?? 1,
        scaleId: j['scaleId'] as String?,
        weighedAt: DateTime.parse(j['weighedAt'] as String),
        note: (j['note'] as String?) ?? '',
      );
}

/// 小样：收青员按随机位置抽取，每份小样分别登记。
///
/// 局部闷热在小样上表现为 [red] 红变和 [bruise] 机械伤；
/// [hotSpot] 是收青员现场判定的"这一位置局部闷热"事实标记，
/// 大批平均值不得覆盖它——每个 [Sample] 独立保存并逐条核对。
class Sample {
  Sample({
    required this.id,
    required this.batchId,
    required this.lotId,
    required this.position,
    required this.drawnAt,
    required this.gradeShares,
    required this.water,
    required this.offOdors,
    this.red = RedDamageLevel.none,
    this.bruise = BruiseLevel.none,
    this.hotSpot = false,
    this.randomX,
    this.randomY,
    this.weightG,
    String? note,
  }) : note = note ?? '';

  final String id;
  final String batchId;
  final String lotId;

  /// 实际抽到的位置（随机位置由抽样服务给出，见 SamplingPlan）。
  final SamplePosition position;
  final double? randomX;
  final double? randomY;
  final DateTime drawnAt;

  /// 该小样实测芽叶级配（事实记录，不映射收购等级）。
  final List<GradeShare> gradeShares;
  final SurfaceWater water;
  final List<OffOdorType> offOdors;
  final RedDamageLevel red;
  final BruiseLevel bruise;

  /// 现场标记的局部闷热点。
  final bool hotSpot;
  final double? weightG;
  final String note;

  bool get hasRealOffOdor =>
      offOdors.any((o) => o != OffOdorType.none);

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        'lotId': lotId,
        'position': position.name,
        'randomX': randomX,
        'randomY': randomY,
        'drawnAt': drawnAt.toIso8601String(),
        'gradeShares': gradeShares.map((e) => e.toJson()).toList(),
        'water': water.name,
        'offOdors': offOdors.map((e) => e.name).toList(),
        'red': red.name,
        'bruise': bruise.name,
        'hotSpot': hotSpot,
        'weightG': weightG,
        'note': note,
      };

  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
        id: j['id'] as String,
        batchId: j['batchId'] as String,
        lotId: j['lotId'] as String,
        position: SamplePosition.values.byName(j['position'] as String),
        randomX: (j['randomX'] as num?)?.toDouble(),
        randomY: (j['randomY'] as num?)?.toDouble(),
        drawnAt: DateTime.parse(j['drawnAt'] as String),
        gradeShares: (j['gradeShares'] as List)
            .map((e) => GradeShare.fromJson(e as Map<String, dynamic>))
            .toList(),
        water: SurfaceWater.values.byName(j['water'] as String),
        offOdors: (j['offOdors'] as List)
            .map((e) => OffOdorType.values.byName(e as String))
            .toList(),
        red: RedDamageLevel.values.byName((j['red'] as String?) ?? 'none'),
        bruise:
            BruiseLevel.values.byName((j['bruise'] as String?) ?? 'none'),
        hotSpot: (j['hotSpot'] as bool?) ?? false,
        weightG: (j['weightG'] as num?)?.toDouble(),
        note: (j['note'] as String?) ?? '',
      );
}

/// 摊样/标签/损伤照片的路径记录。
///
/// 设备上只存 [localPath]；同步时由 App 层上传后回填 [remoteUrl]。
class LotPhoto {
  const LotPhoto({
    required this.id,
    required this.batchId,
    required this.tag,
    required this.localPath,
    required this.takenAt,
    this.lotId,
    this.basketCode,
    this.remoteUrl,
  });

  final String id;
  final String batchId;
  final String? lotId;
  final String? basketCode;
  final PhotoTag tag;
  final String localPath;
  final String? remoteUrl;
  final DateTime takenAt;

  LotPhoto withRemote(String url) => LotPhoto(
        id: id,
        batchId: batchId,
        lotId: lotId,
        basketCode: basketCode,
        tag: tag,
        localPath: localPath,
        remoteUrl: url,
        takenAt: takenAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        'lotId': lotId,
        'basketCode': basketCode,
        'tag': tag.name,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'takenAt': takenAt.toIso8601String(),
      };

  factory LotPhoto.fromJson(Map<String, dynamic> j) => LotPhoto(
        id: j['id'] as String,
        batchId: j['batchId'] as String,
        lotId: j['lotId'] as String?,
        basketCode: j['basketCode'] as String?,
        tag: PhotoTag.values.byName(j['tag'] as String),
        localPath: j['localPath'] as String,
        remoteUrl: j['remoteUrl'] as String?,
        takenAt: DateTime.parse(j['takenAt'] as String),
      );
}
