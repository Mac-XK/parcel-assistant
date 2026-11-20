import Foundation
import CommonCrypto

/// MTOP H5 网关客户端：签名与 Scripting 版 utils/mtop.ts 一致
/// 签名 = md5("{_m_h5_tk 的 token 段}&{t}&{appKey}&{data}")
enum MTop {
    static let appKey = "12574478"
    static let host = "https://h5api.m.taobao.com"
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    static let referer = "https://h5.m.taobao.com/"

    enum Failure: LocalizedError {
        case noLogin
        case tokenMissing
        case badResponse(String)
        case business(String)

        var errorDescription: String? {
            switch self {
            case .noLogin: return "还没有淘宝登录态"
            case .tokenMissing: return "缺少 _m_h5_tk，先打开一次淘宝页面"
            case .badResponse(let s): return "网关返回异常 \(s)"
            case .business(let s): return s
            }
        }
    }

    static func md5(_ s: String) -> String {
        let data = Data(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func token(from cookieHeader: String) -> String {
        for pair in cookieHeader.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == "_m_h5_tk" {
                return String(kv[1].split(separator: "_").first ?? "")
            }
        }
        return ""
    }

    static func call(_ api: String, data: [String: Any], version: String = "1.0") async throws -> [String: Any] {
        let body: String
        if let d = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]),
           let s = String(data: d, encoding: .utf8) {
            body = s
        } else {
            body = "{}"
        }

        var attempt = 0
        while true {
            guard let cookieHeader = await PlatformSession.shared.cookieHeader(for: .taobao) else { throw Failure.noLogin }
            let token = token(from: cookieHeader)
            guard !token.isEmpty else {
                // 没有 _m_h5_tk：让网关下发一次（会带 Set-Cookie）
                if attempt == 0 { attempt += 1; try await primeToken(); continue }
                throw Failure.tokenMissing
            }

            let t = Int(Date().timeIntervalSince1970 * 1000)
            let sign = md5("\(token)&\(t)&\(appKey)&\(body)")
            var comps = URLComponents(string: "\(host)/h5/\(api.lowercased())/\(version)/")!
            comps.queryItems = [
                .init(name: "jsv", value: "2.7.4"),
                .init(name: "appKey", value: appKey),
                .init(name: "t", value: String(t)),
                .init(name: "sign", value: sign),
                .init(name: "api", value: api),
                .init(name: "v", value: version),
                .init(name: "type", value: "originaljson"),
                .init(name: "dataType", value: "json"),
                .init(name: "data", value: body),
            ]

            var req = URLRequest(url: comps.url!)
            req.httpMethod = "GET"
            req.timeoutInterval = 20
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue(referer, forHTTPHeaderField: "Referer")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                await captureToken(http, url: comps.url!)
            }
            let object = try? JSONSerialization.jsonObject(with: data)
            guard let json = object as? [String: Any] else {
                throw Failure.badResponse("不是 JSON")
            }
            let ret = (json["ret"] as? [String])?.first ?? ""
            if ret.hasPrefix("SUCCESS") { return json }

            let retriable = ["TOKEN", "SESSION", "ILLEGAL_ACCESS", "TRAFFIC_LIMIT"].contains { ret.uppercased().contains($0) }
            if retriable && attempt < 2 {
                attempt += 1
                try await primeToken()
                continue
            }
            if ret.contains("TOKEN") || ret.contains("SESSION") {
                throw Failure.business("登录态过期：\(ret)")
            }
            throw Failure.business(ret.isEmpty ? "接口无返回" : ret)
        }
    }

    /// 打开一次 h5 首页，让网关把新的 _m_h5_tk 写进 Set-Cookie
    private static func primeToken() async throws {
        guard let cookieHeader = await PlatformSession.shared.cookieHeader(for: .taobao) else { throw Failure.noLogin }
        var req = URLRequest(url: URL(string: referer)!)
        req.timeoutInterval = 15
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return }
        await captureToken(http, url: URL(string: referer)!)
    }

    private static func captureToken(_ http: HTTPURLResponse, url: URL) async {
        var fields: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if String(describing: k).lowercased() == "set-cookie" {
                fields["Set-Cookie"] = String(describing: v)
            }
        }
        guard !fields.isEmpty else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        let keep = cookies.filter { $0.name.hasPrefix("_m_h5_tk") || $0.name == "cookie2" || $0.name == "sgcookie" }
        if !keep.isEmpty {
            await PlatformSession.shared.merge(keep, for: .taobao)
        }
    }

    /// 网关把业务数据放在 data.data 或 data 里
    static func payload(_ json: [String: Any]) -> Any? {
        guard let d = json["data"] as? [String: Any] else { return json["data"] }
        return d["data"] ?? d
    }
}
