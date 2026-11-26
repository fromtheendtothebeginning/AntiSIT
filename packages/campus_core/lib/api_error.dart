/// 统一 API 错误：服务器模式（HTTP detail）与直连模式（校园系统报错）共用。
class ApiError implements Exception {
  final String message;
  final int? code;

  /// 写操作（扣款 / 报名 / 签到）专用：请求是否可能已经被处理。
  ///
  /// - `true`：网络中断、超时、网关 5xx 这类「发出去但不知道结果」的失败，
  ///   调用方**不能**提示「失败了你再点一次」，必须先让用户核实；
  /// - `false`：确定没被执行（明确的 4xx 拒绝、学校返回业务错误码）；
  /// - `null`：未标注，由 [writeOutcomeUncertain] 按错误类型推断。
  final bool? writeUncertain;

  ApiError(this.message, [this.code, this.writeUncertain]);
  @override
  String toString() => message;
}

/// 写操作失败后，结果是否「不确定」（可能已经扣款 / 已提交）。
///
/// 判定口径：**只有明确的拒绝才算确定失败**，其余一律按未确认处理。
/// 这类判断散落在电费充值、活动报名、扫码签到等处，此前各自维护关键词表
/// （只看文案含「超时 / 网络」），连接重置、502/504 等都会被误报成「失败」，
/// 诱导用户重复提交——这正是写操作最怕的事故链。
bool writeOutcomeUncertain(Object error) {
  if (error is! ApiError) return true; // 非业务异常（解析崩溃等）：请求可能已生效
  final flagged = error.writeUncertain;
  if (flagged != null) return flagged;
  final code = error.code;
  if (code == null) return false; // 学校/服务器给出的业务错误：明确没有生效
  if (code == 408 || code == 425 || code == 429 || code >= 500) return true;
  if (code >= 400) return false;
  return true; // 2xx/3xx 却走到失败分支：语义含糊，按未确认处理
}
