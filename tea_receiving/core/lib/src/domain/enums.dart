/// 收青业务枚举。
///
/// 系统只记录事实、给出人工核对提示；任何枚举都不表示"等级判定"或"价格档位"。
library;

/// 采摘手法。
enum PickingMethod {
  handSingleBud('单芽手采'),
  handOneBudOneLeaf('一芽一叶手采'),
  handOneBudTwoLeaves('一芽二叶手采'),
  handMixed('混合手采'),
  shears('剪采'),
  machine('机采'),
  other('其他');

  const PickingMethod(this.label);
  final String label;
}

/// 运输容器种类（竹篓需透气，编织袋/塑料袋易闷热）。
enum ContainerType {
  bambooBasket('竹篓', breathable: true),
  wickerBasket('藤篓', breathable: true),
  clothBag('布袋', breathable: true),
  wovenBag('编织袋', breathable: false),
  plasticBag('塑料袋', breathable: false),
  foamBox('泡沫箱', breathable: false),
  other('其他', breathable: false);

  const ContainerType(this.label, {required this.breathable});
  final String label;

  /// 容器是否透气。不透气只作为闷热核对的参考事实，不做自动结论。
  final bool breathable;
}

/// 抽样位置（随机抽样时记录实际抽到的位置）。
enum SamplePosition {
  top('篓面'),
  middle('篓中层'),
  bottom('篓底'),
  center('批中心'),
  edge('批边缘'),
  spreadTray('摊放匾');

  const SamplePosition(this.label);
  final String label;
}

/// 表面水情况（登记事实，不自动判级）。
enum SurfaceWater {
  none('无', moisture: false),
  slight('轻微潮', moisture: true),
  wet('湿', moisture: true),
  dripping('带明水/滴水', moisture: true);

  const SurfaceWater(this.label, {required this.moisture});
  final String label;
  final bool moisture;
}

/// 异味类别（多选时逐项记录）。
enum OffOdorType {
  none('无异味'),
  smoky('烟味'),
  pesticide('药味'),
  fermented('发酵味'),
  musty('霉味'),
  petrol('油气味'),
  other('其他异味');

  const OffOdorType(this.label);
  final String label;
}

/// 红变程度（红变/褐变，采后闷热的重要迹象）。
enum RedDamageLevel {
  none('无', order: 0),
  slight('轻微', order: 1),
  local('局部红变', order: 2),
  severe('明显红变', order: 3);

  const RedDamageLevel(this.label, {required this.order});
  final String label;
  final int order;
}

/// 机械伤程度。
enum BruiseLevel {
  none('无伤', order: 0),
  slight('轻微', order: 1),
  local('局部机械伤', order: 2),
  severe('严重机械伤', order: 3);

  const BruiseLevel(this.label, {required this.order});
  final String label;
  final int order;
}

/// 收青核对提示的严重度。
///
/// 即使 [block] 也不会被系统自动执行：完成收青需要收青员显式人工确认。
enum Severity {
  info('提示'),
  warning('警告'),
  block('需人工处置');

  const Severity(this.label);
  final String label;
}

/// 离线同步状态。
enum SyncState {
  pendingLocal('仅本机'),
  synced('已同步');

  const SyncState(this.label);
  final String label;
}

/// 收青单状态。系统不自动流转到"已收青"：核对提示必须由收青员人工处置。
enum ReceiptStatus {
  draft('登记中'),
  awaitingChecks('待人工处置'),
  finalized('已收青');

  const ReceiptStatus(this.label);
  final String label;
}

/// 照片用途标签。
enum PhotoTag {
  spreadSample('摊样照片'),
  labelPhoto('标签照片'),
  damage('红变/损伤部位'),
  other('其他');

  const PhotoTag(this.label);
  final String label;
}
