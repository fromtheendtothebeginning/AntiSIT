/// 统一 API 错误：服务器模式（HTTP detail）与直连模式（校园系统报错）共用。
class ApiError implements Exception {
  final String message;
  final int? code;
  ApiError(this.message, [this.code]);
  @override
  String toString() => message;
}
