/// 收青核对提示。系统只核对事实、生成提示；不自动定级、定价或拒绝收青。
library;


import '../domain/enums.dart';

/// 核对提示代码（也是人工确认 ManualAck.issueCode 的键）。
enum IssueCode {
  postHarvestLong('采后时长偏长'),
  postHarvestUnknownInterval('采摘时间区间过宽，时长不确定'),
  sampleCoverageThin('抽样覆盖不足'),
  sampleMissingPosition('抽样位置未覆盖篓底/中层'),
  netWeightMismatch('净重与报量不符'),
  netWeightZero('净重为零或缺失'),
  duplicateWeighing('疑似重复过秤'),
  localHotSpot('局部闷热：小样红变/发热'),
  nonBreathableContainer('运输容器不透气'),
  labelDamaged('标签受雨损坏'),
  mixedGardens('多个茶园混装'),
  wetSurface('表面水明显'),
  offOdor('检出异味'),
  spreadBeforeRegister('先摊开后登记'),
  gradeCompositionSpread('各样方芽叶级配差异大');

  const IssueCode(this.label);
  final String label;
}

class CheckIssue {
  const CheckIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.facts = const {},
  });

  final IssueCode code;
  final Severity severity;
  final String message;

  /// 支撑提示的客观事实（数值、位置、小样号等），界面展示给收青员。
  final Map<String, Object?> facts;

  String get id => code.name;

  @override
  bool operator ==(Object other) =>
      other is CheckIssue &&
      other.code == code &&
      _mapEq(other.facts, facts);

  @override
  int get hashCode => Object.hash(code, Object.hashAll(facts.values));

  static bool _mapEq(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

/// 一次核对的结果。
class CheckReport {
  const CheckReport(this.issues, {required this.checkedAt});

  final List<CheckIssue> issues;
  final DateTime checkedAt;

  List<CheckIssue> bySeverity(Severity s) =>
      issues.where((i) => i.severity == s).toList();

  List<CheckIssue> get blocks => bySeverity(Severity.block);
  List<CheckIssue> get warnings => bySeverity(Severity.warning);
  List<CheckIssue> get infos => bySeverity(Severity.info);
}
