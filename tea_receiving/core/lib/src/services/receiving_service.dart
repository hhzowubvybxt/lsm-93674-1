/// 收青核对服务。
///
/// 只做三件事：登记事实、核对事实、记录收青员的人工处置。
/// 明确 *不做* 的事：不自动决定等级、不自动决定价格、不根据平均值
/// 覆盖局部红变/闷热/表面水/异味。
library;

import '../domain/aggregate.dart';
import '../domain/entities.dart';
import '../domain/enums.dart';
import 'check_issue.dart';

class ReceivingConfig {
  const ReceivingConfig({
    this.maxPostHarvestHours = 8.0,
    this.maxPickIntervalHours = 6.0,
    this.minSamples = 5,
    this.requiredPositions = const [
      SamplePosition.bottom,
      SamplePosition.middle,
    ],
    this.netWeightToleranceRatio = 0.05,
    this.duplicateWeighingWindow = const Duration(minutes: 10),
    this.hotSpotRedLevel = RedDamageLevel.local,
    this.compositionSpreadPctPoints = 25.0,
    this.registerDelayWarnMinutes = 30,
  });

  final double maxPostHarvestHours;
  final double maxPickIntervalHours;
  final int minSamples;

  /// 未摊开时抽样必须覆盖的位置（篓底/中层最易藏闷热）。
  final List<SamplePosition> requiredPositions;
  final double netWeightToleranceRatio;
  final Duration duplicateWeighingWindow;
  final RedDamageLevel hotSpotRedLevel;
  final double compositionSpreadPctPoints;
  final int registerDelayWarnMinutes;
}

class ReceivingService {
  ReceivingService({ReceivingConfig? config, DateTime Function()? clock})
      : config = config ?? const ReceivingConfig(),
        _clock = clock ?? DateTime.now;

  final ReceivingConfig config;
  final DateTime Function() _clock;

  /// 执行全部核对规则，返回提示清单（不修改批次）。
  /// [baskets] 为本批已绑竹篓档案（容器透气性、标签状态）；
  /// [declaredNetByBasket] 为茶农/运输联单自报净重，用于净重核对，可为空。
  CheckReport check(
    ReceivingBatch b, {
    Map<String, Basket> baskets = const {},
    Map<String, double> declaredNetByBasket = const {},
  }) {
    final issues = <CheckIssue>[];
    issues.addAll(_checkPostHarvest(b));
    issues.addAll(_checkContainer(b, baskets));
    issues.addAll(_checkLabel(b));
    issues.addAll(_checkWeighing(b, declaredNetByBasket));
    issues.addAll(_checkSampling(b));
    issues.addAll(_checkLeafCondition(b));
    issues.addAll(_checkTimeline(b));
    return CheckReport(issues, checkedAt: _clock());
  }

  // ---- 规则 1：采后时长 ----
  Iterable<CheckIssue> _checkPostHarvest(ReceivingBatch b) {
    final out = <CheckIssue>[];
    for (final lot in b.lots) {
      final r = lot.pickedAt.postHarvestHours(b.arrivedAt);
      final intervalHours = double.parse(
          (lot.pickedAt.latest.difference(lot.pickedAt.earliest).inMinutes /
                  60)
              .toStringAsFixed(2));
      if (intervalHours > config.maxPickIntervalHours) {
        out.add(CheckIssue(
          code: IssueCode.postHarvestUnknownInterval,
          severity: Severity.warning,
          message: '鲜叶票 ${lot.id} 采摘时间只有 ${intervalHours}h 的宽区间，'
              '采后时长 ${r.minHours}~${r.maxHours}h，无法确认是否超时',
          facts: {
            'lotId': lot.id,
            'intervalHours': intervalHours,
            'minHours': r.minHours,
            'maxHours': r.maxHours,
          },
        ));
      }
      // 只在"最保守也已超时"时升级为 block；区间内不确定时仅警告。
      if (r.minHours > config.maxPostHarvestHours) {
        out.add(CheckIssue(
          code: IssueCode.postHarvestLong,
          severity: Severity.block,
          message: '鲜叶票 ${lot.id} 采后至少 ${r.minHours}h，'
              '超过 ${config.maxPostHarvestHours}h，需人工处置',
          facts: {
            'lotId': lot.id,
            'minHours': r.minHours,
            'maxHours': r.maxHours,
            'limitHours': config.maxPostHarvestHours,
          },
        ));
      } else if (r.maxHours > config.maxPostHarvestHours) {
        out.add(CheckIssue(
          code: IssueCode.postHarvestLong,
          severity: Severity.warning,
          message: '鲜叶票 ${lot.id} 采后 ${r.minHours}~${r.maxHours}h，'
              '可能超过 ${config.maxPostHarvestHours}h',
          facts: {
            'lotId': lot.id,
            'minHours': r.minHours,
            'maxHours': r.maxHours,
          },
        ));
      }
    }
    return out;
  }

  // ---- 规则 2：容器透气（闷热参考事实） ----
  Iterable<CheckIssue> _checkContainer(
      ReceivingBatch b, Map<String, Basket> baskets) {
    final out = <CheckIssue>[];
    for (final code in b.basketCodes) {
      final basket = baskets[code] ?? baskets[_oldCode(b, code)];
      if (basket == null) {
        // 未登记容器档案（雨损重贴等场景），交给标签规则提示。
        continue;
      }
      if (!basket.container.breathable) {
        out.add(CheckIssue(
          code: IssueCode.nonBreathableContainer,
          severity: Severity.warning,
          message: '$code 使用${basket.container.label}，不透气，'
              '重点查看篓中小样是否闷热红变',
          facts: {'basketCode': code, 'container': basket.container.name},
        ));
      }
    }
    return out;
  }

  /// 雨损重贴后，历史称量仍是旧码；容器核对时顺旧码找档案。
  String? _oldCode(ReceivingBatch b, String current) {
    if (!b.relabelNote.contains(current)) return null;
    final m = RegExp('([A-Z0-9-]+) → $current').firstMatch(b.relabelNote);
    return m?.group(1);
  }

  // ---- 规则 3：标签受雨损坏 ----
  Iterable<CheckIssue> _checkLabel(ReceivingBatch b) {
    if (!b.labelDamaged) return const [];
    final relabeled = b.relabelNote.contains('重贴');
    return [
      CheckIssue(
        code: IssueCode.labelDamaged,
        severity: relabeled ? Severity.info : Severity.block,
        message: relabeled
            ? '${b.damagedBasketCode} 标签受雨损坏，已人工核对身份并重贴新签'
            : '${b.damagedBasketCode} 标签受雨损坏，需人工核对篓批绑定、'
                '拍照留证并补打重贴',
        facts: {
          'basketCode': b.damagedBasketCode,
          'relabeled': relabeled,
          'note': b.relabelNote,
        },
      ),
    ];
  }

  // ---- 规则 4：称量（一篓多称相加、重复过秤、净重核对） ----
  Iterable<CheckIssue> _checkWeighing(
      ReceivingBatch b, Map<String, double> declared) {
    final out = <CheckIssue>[];
    if (b.weighings.isEmpty) {
      out.add(const CheckIssue(
        code: IssueCode.netWeightZero,
        severity: Severity.block,
        message: '尚无称量记录，净重缺失',
        facts: {},
      ));
      return out;
    }
    if (b.totalNetKg <= 0) {
      out.add(CheckIssue(
        code: IssueCode.netWeightZero,
        severity: Severity.block,
        message: '净重合计 ${b.totalNetKg}kg ≤ 0，核对皮重/毛重',
        facts: {'netKg': b.totalNetKg},
      ));
    }

    // 同一竹篓、重量相同、时间接近 → 疑似重复过秤；
    // 已显式声明分称(splitPart>1)的视为一篓多次称量的正常情况。
    final ws = [...b.weighings]
      ..sort((a, c) => a.weighedAt.compareTo(c.weighedAt));
    for (var i = 0; i < ws.length; i++) {
      for (var j = i + 1; j < ws.length; j++) {
        final a = ws[i];
        final c = ws[j];
        if (a.basketCode != c.basketCode) continue;
        final declaredSplit = a.splitPart > 1 || c.splitPart > 1;
        final closeInTime = c.weighedAt.difference(a.weighedAt).abs() <=
            config.duplicateWeighingWindow;
        final sameWeight = (a.grossKg - c.grossKg).abs() < 0.005;
        if (closeInTime && sameWeight && !declaredSplit) {
          out.add(CheckIssue(
            code: IssueCode.duplicateWeighing,
            severity: Severity.block,
            message: '${a.basketCode} 在 '
                '${config.duplicateWeighingWindow.inMinutes} 分钟内两次毛重均为 '
                '${a.grossKg}kg，疑似重复过秤；若确为分称请勾选分称',
            facts: {
              'basketCode': a.basketCode,
              'at1': a.weighedAt.toIso8601String(),
              'at2': c.weighedAt.toIso8601String(),
              'grossKg': a.grossKg,
            },
          ));
        }
      }
    }

    // 净重核对：逐篓相加后的净重与自报净重比对（不用大批均值反推）。
    declared.forEach((code, declaredNet) {
      final actual = b.netByBasket[code];
      if (actual == null) return;
      final diff = actual - declaredNet;
      final ratio = declaredNet == 0 ? 0 : diff.abs() / declaredNet;
      if (ratio > config.netWeightToleranceRatio) {
        out.add(CheckIssue(
          code: IssueCode.netWeightMismatch,
          severity: Severity.warning,
          message: '$code 逐次称量净重合计 ${actual}kg，'
              '自报 ${declaredNet}kg，差 ${diff.toStringAsFixed(2)}kg '
              '(${(ratio * 100).toStringAsFixed(1)}%)，请人工复核',
          facts: {
            'basketCode': code,
            'actualNetKg': actual,
            'declaredNetKg': declaredNet,
            'diffKg': double.parse(diff.toStringAsFixed(3)),
          },
        ));
      }
    });
    return out;
  }

  // ---- 规则 5：抽样覆盖 ----
  Iterable<CheckIssue> _checkSampling(ReceivingBatch b) {
    final out = <CheckIssue>[];
    if (b.samples.isEmpty) {
      out.add(const CheckIssue(
        code: IssueCode.sampleCoverageThin,
        severity: Severity.block,
        message: '尚未抽取小样',
        facts: {},
      ));
      return out;
    }
    final alreadySpread = b.spreadStartedAt != null;
    if (b.samples.length < config.minSamples) {
      out.add(CheckIssue(
        code: IssueCode.sampleCoverageThin,
        severity: Severity.block,
        message: '小样 ${b.samples.length} 份，少于最少 ${config.minSamples} 份',
        facts: {'actual': b.samples.length, 'min': config.minSamples},
      ));
    }

    // 位置覆盖：未摊开时必须有篓底+中层；已摊开则必须抽到摊放匾。
    final positions = b.samples.map((s) => s.position).toSet();
    if (alreadySpread) {
      if (!positions.contains(SamplePosition.spreadTray)) {
        out.add(const CheckIssue(
          code: IssueCode.sampleMissingPosition,
          severity: Severity.block,
          message: '已先摊开，但没有在摊放匾上抽样',
          facts: {},
        ));
      }
    } else {
      final missing = config.requiredPositions
          .where((p) => !positions.contains(p))
          .toList();
      if (missing.isNotEmpty) {
        out.add(CheckIssue(
          code: IssueCode.sampleMissingPosition,
          severity: Severity.block,
          message: '抽样未覆盖：${missing.map((p) => p.label).join('、')}'
              '（闷热常藏在这些位置，不能只抽篓面）',
          facts: {'missing': missing.map((p) => p.name).toList()},
        ));
      }
    }

    // 多茶园混装：每个 lot 都必须被抽到。
    final sampledLots = b.samples.map((s) => s.lotId).toSet();
    final unsampled = b.lots
        .where((l) => !sampledLots.contains(l.id))
        .map((l) => l.id)
        .toList();
    if (unsampled.isNotEmpty) {
      out.add(CheckIssue(
        code: IssueCode.sampleCoverageThin,
        severity: Severity.block,
        message: '混装批中以下鲜叶票未抽到小样：${unsampled.join('、')}',
        facts: {'unsampledLotIds': unsampled},
      ));
    }

    // 各小样芽叶级配差异（供人工参考；差异大不自动判级，只提示别用平均组成掩盖）。
    out.addAll(_checkCompositionSpread(b));
    return out;
  }

  Iterable<CheckIssue> _checkCompositionSpread(ReceivingBatch b) {
    if (b.samples.length < 2) return const [];
    final byName = <String, List<double>>{};
    for (final s in b.samples) {
      for (final g in s.gradeShares) {
        byName.putIfAbsent(g.name, () => []).add(g.percent);
      }
    }
    final out = <CheckIssue>[];
    byName.forEach((name, vals) {
      if (vals.length != b.samples.length) return; // 有的小样没登记该组分
      final spread = vals.reduce((a, c) => a > c ? a : c) -
          vals.reduce((a, c) => a < c ? a : c);
      if (spread >= config.compositionSpreadPctPoints) {
        out.add(CheckIssue(
          code: IssueCode.gradeCompositionSpread,
          severity: Severity.warning,
          message: '各小样"$name"占比相差 ${spread.toStringAsFixed(0)} 个百分点，'
              '局部组成差异明显，级配以各小样记录为准，勿用大批平均代替',
          facts: {'grade': name, 'spreadPoints': spread, 'values': vals},
        ));
      }
    });
    return out;
  }

  // ---- 规则 6：鲜叶状态（红变/闷热/表面水/异味，逐小样保留） ----
  Iterable<CheckIssue> _checkLeafCondition(ReceivingBatch b) {
    final out = <CheckIssue>[];
    for (final s in b.samples) {
      if (s.hotSpot || s.red.order >= config.hotSpotRedLevel.order) {
        out.add(CheckIssue(
          code: IssueCode.localHotSpot,
          severity: Severity.block,
          message: '小样 ${s.id}（${s.position.label}）'
              '${s.hotSpot ? "标记为局部闷热" : ""}'
              '${s.hotSpot && s.red != RedDamageLevel.none ? "、" : ""}'
              '${s.red != RedDamageLevel.none ? "存在${s.red.label}" : ""}'
              '，需现场单独处置，该事实保留在小样上，不并入大批平均',
          facts: {
            'sampleId': s.id,
            'position': s.position.name,
            'red': s.red.name,
            'bruise': s.bruise.name,
            'hotSpot': s.hotSpot,
          },
        ));
      }
      if (s.water == SurfaceWater.wet ||
          s.water == SurfaceWater.dripping) {
        out.add(CheckIssue(
          code: IssueCode.wetSurface,
          severity: Severity.warning,
          message: '小样 ${s.id}（${s.position.label}）表面水：${s.water.label}',
          facts: {'sampleId': s.id, 'water': s.water.name},
        ));
      }
      if (s.hasRealOffOdor) {
        final names = s.offOdors
            .where((o) => o != OffOdorType.none)
            .map((o) => o.label)
            .join('、');
        out.add(CheckIssue(
          code: IssueCode.offOdor,
          severity: Severity.block,
          message: '小样 ${s.id}（${s.position.label}）检出异味：$names',
          facts: {
            'sampleId': s.id,
            'offOdors': s.offOdors
                .where((o) => o != OffOdorType.none)
                .map((o) => o.name)
                .toList(),
          },
        ));
      }
    }
    return out;
  }

  // ---- 规则 7：时间线（混装提示、先摊后登记） ----
  Iterable<CheckIssue> _checkTimeline(ReceivingBatch b) {
    final out = <CheckIssue>[];
    if (b.isMixedGardens) {
      out.add(CheckIssue(
        code: IssueCode.mixedGardens,
        severity: Severity.info,
        message: '本批为多个茶园混装：${b.lots.length} 张鲜叶票，'
            '区块/采法/采摘时间/芽叶组成/红变损伤按票分别保留',
        facts: {'lotCount': b.lots.length, 'lotIds': lotIds(b)},
      ));
    }
    if (b.spreadStartedAt != null) {
      final reg = b.registeredAt;
      final ref = reg ?? _clock();
      final delayMin = ref.difference(b.spreadStartedAt!).inMinutes;
      out.add(CheckIssue(
        code: IssueCode.spreadBeforeRegister,
        severity:
            delayMin >= config.registerDelayWarnMinutes && reg == null
                ? Severity.warning
                : Severity.info,
        message: reg == null
            ? '鲜叶已先摊开 $delayMin 分钟但尚未登记，请尽快补登记'
            : '鲜叶到场后先摊开、$delayMin 分钟后补登记（允许），'
                '采后时长以到场 ${b.arrivedAt.toIso8601String()} 为准',
        facts: {
          'spreadAt': b.spreadStartedAt!.toIso8601String(),
          'registeredAt': reg?.toIso8601String(),
          'delayMinutes': delayMin,
        },
      ));
    }
    return out;
  }

  /// 仅列出 lot id（避免在 service 里依赖 block 档案）。
  List<String> lotIds(ReceivingBatch b) =>
      b.lots.map((l) => l.id).toList();

  /// 提示的唯一键：代码 + 事实定位（如同篓重复过秤、某小样闷热）。
  /// 收青员必须逐条处置，批量确认同类问题会被拒绝。
  String issueKey(CheckIssue i) {
    final loc = _locators[i.code];
    if (loc == null) return i.code.name;
    final v = i.facts[loc];
    return v == null ? i.code.name : '${i.code.name}|$loc=$v';
  }

  static const _locators = <IssueCode, String>{
    IssueCode.postHarvestLong: 'lotId',
    IssueCode.postHarvestUnknownInterval: 'lotId',
    IssueCode.duplicateWeighing: 'basketCode',
    IssueCode.netWeightMismatch: 'basketCode',
    IssueCode.localHotSpot: 'sampleId',
    IssueCode.offOdor: 'sampleId',
    IssueCode.wetSurface: 'sampleId',
    IssueCode.nonBreathableContainer: 'basketCode',
    IssueCode.labelDamaged: 'basketCode',
  };

  /// 尚未被人工处置的 block 提示。
  List<CheckIssue> openBlocks(ReceivingBatch b, CheckReport r) {
    return r.blocks.where((i) {
      final key = issueKey(i);
      final ack = b.acks.where((a) => a.issueCode == key);
      return ack.isEmpty;
    }).toList();
  }

  /// 人工处置后完成收青。
  ///
  /// 系统只校验"每条 block 都有对应的人、时间、处置意见"；
  /// 是否真的可以收青由 [by] 决定，系统绝不给等级、不给价格。
  ReceiptFinalization finalize(
    ReceivingBatch b, {
    required String by,
    required String note,
  }) {
    if (note.trim().isEmpty) {
      throw ArgumentError('请填写人工处置结论');
    }
    final report = check(b);
    final open = openBlocks(b, report);
    if (open.isNotEmpty) {
      return ReceiptFinalization(
        ok: false,
        report: report,
        openBlockKeys: open.map(issueKey).toList(),
      );
    }
    b.status = ReceiptStatus.awaitingChecks;
    b.finalize(by: by, note: note); // 聚合内再次校验净重等不变量
    return ReceiptFinalization(ok: true, report: report, openBlockKeys: const []);
  }
}

/// 完成收青的尝试结果。失败时 [openBlockKeys] 指出还缺人工处置的提示。
class ReceiptFinalization {
  const ReceiptFinalization({
    required this.ok,
    required this.report,
    required this.openBlockKeys,
  });

  final bool ok;
  final CheckReport report;
  final List<String> openBlockKeys;
}
