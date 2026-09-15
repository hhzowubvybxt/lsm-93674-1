/// 收青聚合根：一票运输批（兼作收青单）。
///
/// 不变量：
/// * 多茶园混装 → [lots] 多条，分别保留区块/采法/采摘区间/容器/组成/损伤；
/// * 一篓多次称量 → [weighings] 多条，净重相加，禁止用大批均值覆盖；
/// * 红变、闷热、异味登记在每份 [Sample] 上，逐条保留；
/// * 本聚合没有等级、没有价格：核对只给提示，由收青员逐条人工确认([acks])后
///   才能 [finalize]。
library;

import '../receiving_errors.dart';
import 'enums.dart';
import 'entities.dart';

/// 收青员对一条核对提示的人工处置记录。
class ManualAck {
  ManualAck({
    required this.issueCode,
    required this.by,
    required this.at,
    required this.accepted,
    String? note,
  }) : note = note ?? '';

  final String issueCode;
  final String by;
  final DateTime at;

  /// true=知悉并接受现状收青；false=按提示做了纠正（纠正后可重新核对）。
  final bool accepted;
  final String note;

  Map<String, dynamic> toJson() => {
        'issueCode': issueCode,
        'by': by,
        'at': at.toIso8601String(),
        'accepted': accepted,
        'note': note,
      };

  factory ManualAck.fromJson(Map<String, dynamic> j) => ManualAck(
        issueCode: j['issueCode'] as String,
        by: j['by'] as String,
        at: DateTime.parse(j['at'] as String),
        accepted: j['accepted'] as bool,
        note: (j['note'] as String?) ?? '',
      );
}

class ReceivingBatch {
  ReceivingBatch({
    required this.id,
    required this.code,
    required this.pointId,
    required this.arrivedAt,
    this.registeredAt,
    this.spreadStartedAt,
    this.status = ReceiptStatus.draft,
    this.labelDamaged = false,
    this.damagedBasketCode,
    this.relabelNote = '',
    this.finalizedAt,
    this.finalizedBy,
    this.decisionNote = '',
    List<LeafLot>? lots,
    List<Weighing>? weighings,
    List<Sample>? samples,
    List<LotPhoto>? photos,
    List<String>? basketCodes,
    List<ManualAck>? acks,
  })  : lots = lots ?? [],
        weighings = weighings ?? [],
        samples = samples ?? [],
        photos = photos ?? [],
        basketCodes = basketCodes ?? [],
        acks = acks ?? [];

  final String id;
  final String code;
  final String pointId;

  /// 到场时刻（运输批到达收青点）。
  final DateTime arrivedAt;

  /// 登记时刻（可能晚于到场：鲜叶先摊开再登记）。
  DateTime? registeredAt;

  /// 到场后先摊开的时刻（若先摊后登记）。
  DateTime? spreadStartedAt;

  ReceiptStatus status;

  /// 标签受雨损坏。
  bool labelDamaged;
  String? damagedBasketCode;
  String relabelNote;

  final List<LeafLot> lots;
  final List<Weighing> weighings;
  final List<Sample> samples;
  final List<LotPhoto> photos;

  /// 已绑定到本批的竹篓二维码。
  final List<String> basketCodes;

  final List<ManualAck> acks;

  DateTime? finalizedAt;
  String? finalizedBy;

  /// 人工处置结论（纯文本事实记录，不允许出现系统等级/价格）。
  String decisionNote;

  // ---- 派生事实（不回写覆盖局部登记） ----

  bool get isMixedGardens => lots.length > 1;

  double get totalGrossKg =>
      double.parse(weighings.fold<double>(0, (a, w) => a + w.grossKg)
          .toStringAsFixed(3));

  double get totalTareKg =>
      double.parse(weighings.fold<double>(0, (a, w) => a + w.tareKg)
          .toStringAsFixed(3));

  /// 净重合计：逐次称量净重相加。一篓分称时同样是相加，不做平均。
  double get totalNetKg =>
      double.parse(weighings.fold<double>(0, (a, w) => a + w.netKg)
          .toStringAsFixed(3));

  /// 单篓净重映射：同一竹篓分多次称量时在此相加。
  Map<String, double> get netByBasket {
    final m = <String, double>{};
    for (final w in weighings) {
      m[w.basketCode] =
          double.parse(((m[w.basketCode] ?? 0) + w.netKg).toStringAsFixed(3));
    }
    return m;
  }

  /// 本批最早与最晚采后时长（小时），由各 lot 的采摘区间汇总。
  ({double minHours, double maxHours})? postHarvestRange() {
    if (lots.isEmpty) return null;
    double? lo;
    double? hi;
    for (final lot in lots) {
      final r = lot.pickedAt.postHarvestHours(arrivedAt);
      lo = lo == null ? r.minHours : (r.minHours < lo ? r.minHours : lo);
      hi = hi == null ? r.maxHours : (r.maxHours > hi ? r.maxHours : hi);
    }
    return (minHours: lo!, maxHours: hi!);
  }

  // ---- 状态变更 ----

  void _ensureNotFinalized() {
    if (status == ReceiptStatus.finalized) {
      throw ReceivingStateError('收青单 $code 已收青，不可再修改');
    }
  }

  /// 到场即摊开（鲜叶到场后先摊开再登记也允许，登记时间可以更晚）。
  void markSpread(DateTime at) {
    _ensureNotFinalized();
    spreadStartedAt = at;
  }

  /// 正式登记（补登记时 [at] 晚于 arrivedAt 也合法）。
  void register(DateTime at) {
    _ensureNotFinalized();
    registeredAt = at;
  }

  void addLot(LeafLot lot) {
    _ensureNotFinalized();
    if (lots.any((l) => l.id == lot.id)) {
      throw ReceivingStateError('鲜叶票 ${lot.id} 已存在');
    }
    lots.add(lot);
  }

  void bindBasket(String code) {
    _ensureNotFinalized();
    if (!basketCodes.contains(code)) basketCodes.add(code);
  }

  /// 记录标签受雨损坏：保留受损事实，后续由人工核对重贴。
  void reportLabelDamage(String basketCode, String note) {
    _ensureNotFinalized();
    labelDamaged = true;
    damagedBasketCode = basketCode;
    relabelNote = note;
    if (!basketCodes.contains(basketCode)) basketCodes.add(basketCode);
  }

  /// 人工重贴新签后登记新码（旧码记录保留，可追溯）。
  void relabel({required String oldCode, required String newCode}) {
    _ensureNotFinalized();
    if (!basketCodes.contains(oldCode)) {
      throw ReceivingStateError('旧篓号 $oldCode 不在本批绑定中');
    }
    final i = basketCodes.indexOf(oldCode);
    basketCodes[i] = newCode;
    // 历史称量保留旧码、不回写覆盖，保证"哪个篓何时称过"可追溯。
    relabelNote = '$relabelNote\n重贴：$oldCode → $newCode'.trim();
  }

  void addWeighing(Weighing w) {
    _ensureNotFinalized();
    if (w.batchId != id) {
      throw ReceivingStateError('称量记录不属于批 $code');
    }
    if (!basketCodes.contains(w.basketCode)) {
      throw ReceivingStateError('竹篓 ${w.basketCode} 未绑定本批，'
          '请先扫码绑定');
    }
    if (weighings.any((x) => x.id == w.id)) {
      throw ReceivingStateError('称量记录 ${w.id} 重复提交');
    }
    weighings.add(w);
  }

  void addSample(Sample s) {
    _ensureNotFinalized();
    if (s.batchId != id) {
      throw ReceivingStateError('小样不属于批 $code');
    }
    if (!lots.any((l) => l.id == s.lotId)) {
      throw ReceivingStateError('小样对应的鲜叶票 ${s.lotId} 未登记');
    }
    samples.add(s);
  }

  void addPhoto(LotPhoto p) {
    _ensureNotFinalized();
    if (p.batchId != id) {
      throw ReceivingStateError('照片不属于批 $code');
    }
    photos.add(p);
  }

  void addAck(ManualAck ack) {
    _ensureNotFinalized();
    acks.removeWhere((a) => a.issueCode == ack.issueCode);
    acks.add(ack);
  }

  /// 由 ReceivingService 在确认全部 block 已人工处置后调用。
  void finalize({required String by, required String note}) {
    _ensureNotFinalized();
    if (lots.isEmpty) {
      throw ReceivingStateError('未登记鲜叶票，不能收青');
    }
    if (weighings.isEmpty) {
      throw ReceivingStateError('无称量记录，不能收青');
    }
    if (totalNetKg <= 0) {
      throw ReceivingStateError('净重合计为 0，不能收青');
    }
    finalizedAt = DateTime.now();
    finalizedBy = by;
    decisionNote = note;
    status = ReceiptStatus.finalized;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'pointId': pointId,
        'arrivedAt': arrivedAt.toIso8601String(),
        'registeredAt': registeredAt?.toIso8601String(),
        'spreadStartedAt': spreadStartedAt?.toIso8601String(),
        'status': status.name,
        'labelDamaged': labelDamaged,
        'damagedBasketCode': damagedBasketCode,
        'relabelNote': relabelNote,
        'finalizedAt': finalizedAt?.toIso8601String(),
        'finalizedBy': finalizedBy,
        'decisionNote': decisionNote,
        'lots': lots.map((e) => e.toJson()).toList(),
        'weighings': weighings.map((e) => e.toJson()).toList(),
        'samples': samples.map((e) => e.toJson()).toList(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'basketCodes': basketCodes,
        'acks': acks.map((e) => e.toJson()).toList(),
      };

  factory ReceivingBatch.fromJson(Map<String, dynamic> j) => ReceivingBatch(
        id: j['id'] as String,
        code: j['code'] as String,
        pointId: j['pointId'] as String,
        arrivedAt: DateTime.parse(j['arrivedAt'] as String),
        registeredAt: j['registeredAt'] == null
            ? null
            : DateTime.parse(j['registeredAt'] as String),
        spreadStartedAt: j['spreadStartedAt'] == null
            ? null
            : DateTime.parse(j['spreadStartedAt'] as String),
        status: ReceiptStatus.values.byName(
            (j['status'] as String?) ?? 'draft'),
        labelDamaged: (j['labelDamaged'] as bool?) ?? false,
        damagedBasketCode: j['damagedBasketCode'] as String?,
        relabelNote: (j['relabelNote'] as String?) ?? '',
        finalizedAt: j['finalizedAt'] == null
            ? null
            : DateTime.parse(j['finalizedAt'] as String),
        finalizedBy: j['finalizedBy'] as String?,
        decisionNote: (j['decisionNote'] as String?) ?? '',
        lots: (j['lots'] as List? ?? [])
            .map((e) => LeafLot.fromJson(e as Map<String, dynamic>))
            .toList(),
        weighings: (j['weighings'] as List? ?? [])
            .map((e) => Weighing.fromJson(e as Map<String, dynamic>))
            .toList(),
        samples: (j['samples'] as List? ?? [])
            .map((e) => Sample.fromJson(e as Map<String, dynamic>))
            .toList(),
        photos: (j['photos'] as List? ?? [])
            .map((e) => LotPhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
        basketCodes:
            (j['basketCodes'] as List? ?? []).map((e) => e as String).toList(),
        acks: (j['acks'] as List? ?? [])
            .map((e) => ManualAck.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
