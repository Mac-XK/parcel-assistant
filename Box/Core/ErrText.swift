import Foundation

/// 把底层错误翻成一句人话：不带 URL、不带签名、不带 NSError 原文
/// 之前直接把 `"\(error)"` 塞进 toast，界面上会糊出一整屏 `NSURLErrorDomain -999` + 带 sign 的完整 URL
enum ErrText {
    static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        return false
    }

    static func short(_ error: Error, limit: Int = 52) -> String {
        if isCancelled(error) { return "请求已取消" }

        if let u = error as? URLError {
            switch u.code {
            case .cancelled:              return "请求已取消"
            case .notConnectedToInternet: return "没有网络"
            case .timedOut:               return "请求超时"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "连不上服务器"
            case .networkConnectionLost:  return "网络中断"
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot:
                return "证书校验失败"
            case .appTransportSecurityRequiresSecureConnection:
                return "连接被系统拦截"
            case .userAuthenticationRequired:
                return "登录态已失效"
            default:                      return "网络错误 \(u.code.rawValue)"
            }
        }

        let raw: String
        if let l = error as? LocalizedError, let d = l.errorDescription, !d.isEmpty {
            raw = d
        } else {
            raw = error.localizedDescription
        }

        let flat = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                let t = token.lowercased()
                return !t.hasPrefix("http") && !t.contains("sign=") && !t.contains("appkey=")
            }
            .joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
