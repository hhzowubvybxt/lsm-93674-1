/// 收青业务错误。
library;

/// 业务前置条件不满足（如竹篓未绑定、净重缺失、同篓重复称量重复提交）。
class ReceivingStateError extends StateError {
  ReceivingStateError(super.message);
}

/// 字段校验失败（如级配合计不是 100%、负数重量）。
class ReceivingValidationError extends ArgumentError {
  ReceivingValidationError(super.message);
}
