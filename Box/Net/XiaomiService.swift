import Foundation

// MARK: - 小米快递（智能助理聚合）

struct MiItem: Codable, Hashable {
    var mailNo: String = ""
    var cpCode: String = ""
    var cpName: String = ""
    var state: Int = 0
    var stateDesc: String = ""
    var stationName: String = ""
    var address: String = ""
    var pickupCode: String = ""
    var productName: String = ""
    var logisticsUpdateTime: String = ""
}

/// 不跟随 302：小米的 serviceToken 在跳转响应的 Set-Cookie 里
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    static let shared = NoRedirect()

    lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class XiaomiService {
    static let shared = XiaomiService()

    private let host = "https://verca.xpa.assistant.miui.com"
    private let aesKey = "d101b17c77ff93cs"
    private let signSalt = "77eb2e8a5755abd016c0d69ba74b219c"
    private let paVersion = 25000031

    struct User: Codable {
        var userId: String
        var passToken: String
        var deviceId: String
        var cUserId: String?
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    var account: Account? { AccountStore.shared.active(.mi) }

    private var blob: [String: String] {
        guard let a = account, let d = a.blob.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }

    private func writeBlob(_ info: [String: String]) {
        let json = (try? JSONSerialization.data(withJSONObject: info))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        AccountStore.shared.updateActive(.mi) { $0.blob = json }
    }

    var token: String { account?.token ?? "" }
    var isLoggedIn: Bool { !token.isEmpty }
    var user: User? {
        guard let raw = blob["user"], let d = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(User.self, from: d)
    }
    var phones: [String] {
        get {
            guard let raw = blob["phones"], let d = raw.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: d) else { return [] }
            return list
        }
        set {
            var info = blob
            info["phones"] = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            writeBlob(info)
        }
    }

    func clear() {
        AccountStore.shared.removeAll(.mi)
        PlatformSession.shared.refreshAll()
    }

    /// 扫码登录后把 Cookie 存下来（userId / passToken / deviceId）
    @discardableResult
    func saveLogin(cookies: [HTTPCookie]) -> Bool {
        func val(_ name: String) -> String {
            cookies.first { $0.name == name }?.value ?? ""
        }
        let userId = val("userId")
        let passToken = val("passToken")
        guard !userId.isEmpty, !passToken.isEmpty else { return false }
        var deviceId = val("deviceId")
        if deviceId.isEmpty {
            // 部分登录链路不下发 deviceId，用稳定的伪值占位
            deviceId = Keychain.get("mi.deviceFallback") ?? ""
            if deviceId.isEmpty {
                deviceId = (0..<16).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
                Keychain.set(deviceId, for: "mi.deviceFallback")
            }
        }
        let u = User(userId: userId, passToken: passToken, deviceId: deviceId, cUserId: val("cUserId"))
        let userJSON = (try? JSONEncoder().encode(u)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var info = blob
        info["user"] = userJSON
        if info["phones"] == nil { info["phones"] = "[]" }
        let json = (try? JSONSerialization.data(withJSONObject: info))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let short = String(userId.suffix(4))
        AccountStore.shared.upsert(Account(id: "mi:\(userId)", platform: .mi,
                                           label: "小米 \(short)", token: token, blob: json))
        return true
    }

    // MARK: 换 serviceToken

    func mintToken() async throws -> String {
        guard let u = user else { throw Failure.message("小米登录态不完整，请重新扫码") }
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
        let cookie = "userId=\(enc(u.userId)); passToken=\(enc(u.passToken)); deviceId=\(enc(u.deviceId))"
        let loginURL = URL(string: "https://account.xiaomi.com/pass/serviceLogin?sid=assistant&_json=true&_appName=com.miui.personalassistant&_locale=zh_CN")!
        var req = URLRequest(url: loginURL)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let start = text.firstIndex(of: "{") else { throw Failure.message("小米 serviceLogin 返回异常") }
        let jsonText = String(text[start...])
        guard let obj = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any] else {
            throw Failure.message("小米 serviceLogin 解析失败")
        }
        let code = (obj["code"] as? NSNumber)?.intValue ?? -1
        guard code == 0 else {
            throw Failure.message("小米 serviceLogin 失败：\((obj["desc"] as? String) ?? "code \(code)")")
        }
        let ssecurity = (obj["ssecurity"] as? String) ?? ""
        let nonce = (obj["nonce"] as? NSNumber)?.stringValue ?? (obj["nonce"] as? String) ?? ""
        let location = (obj["location"] as? String) ?? ""
        let cUserId = (obj["cUserId"] as? String) ?? u.userId
        guard !location.isEmpty, !ssecurity.isEmpty else { throw Failure.message("小米返回缺少 location") }

        let clientSign = Crypto.sha1Base64("nonce=\(nonce)&\(ssecurity)")
        let sep = location.contains("?") ? "&" : "?"
        guard let stsURL = URL(string: "\(location)\(sep)clientSign=\(enc(clientSign))&_userIdNeedEncrypt=true") else {
            throw Failure.message("小米跳转地址异常")
        }
        var stsReq = URLRequest(url: stsURL)
        stsReq.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (_, resp) = try await NoRedirect.shared.session.data(for: stsReq)
        let headers = (resp as? HTTPURLResponse)?.allHeaderFields ?? [:]
        var tokenValue = ""
        for (k, v) in headers where String(describing: k).lowercased() == "set-cookie" {
            let text = String(describing: v)
            for part in text.split(separator: ",") {
                let piece = part.split(separator: ";").first.map(String.init) ?? ""
                let kv = piece.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces).hasSuffix("serviceToken") {
                    tokenValue = kv[1]
                }
            }
        }
        guard !tokenValue.isEmpty else { throw Failure.message("小米返回空令牌，可能账号风控，请重新扫码") }
        var updated = u
        updated.cUserId = cUserId
        let userJSON = (try? JSONEncoder().encode(updated)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var info = blob
        info["user"] = userJSON
        let json = (try? JSONSerialization.data(withJSONObject: info))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        AccountStore.shared.updateActive(.mi) { acc in
            acc.token = tokenValue
            acc.blob = json
        }
        PlatformSession.shared.refreshAll()
        return tokenValue
    }

    // MARK: 加密请求

    private func aesB64(_ plain: String) throws -> String {
        guard let d = Crypto.aesECB(Data(plain.utf8), key: aesKey, decrypt: false) else {
            throw Failure.message("AES 加密失败")
        }
        return d.base64EncodedString()
    }

    private func aesUnb64(_ b64: String) -> String? {
        guard let d = Data(base64Encoded: b64),
              let out = Crypto.aesECB(d, key: aesKey, decrypt: true) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    private func wrapBody(_ plain: String, userId: String) -> String {
        let env: [String: Any] = [
            "terminal": "phone",
            "assistantVersion": paVersion,
            "launchVersion": 0,
            "androidVersion": "14",
            "androidSdkVersion": 34,
            "miuiType": "stable",
            "phoneModel": "2210132C",
            "phoneDevice": "sky",
            "connectionType": "WIFI",
            "miuiVersionName": "V14",
            "miuiVersion": "14.0.6",
            "osVersionName": "HyperOS 1.0",
            "osVersion": "1.0",
            "miSettingsVersionName": "",
            "miSettingsVersionCode": 0,
            "timeZone": "Asia/Shanghai",
            "language": "zh",
            "country": "CN",
            "screen": 1,
            "coordinate": "",
            "reqId": (0..<32).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined(),
            "ip": "",
            "cpuArchitecture": "arm64",
            "marketVersion": 0,
            "os": "",
            "clientFlag": 0,
            "hwVersion": "",
        ]
        let now = Date().timeIntervalSince1970 * 1000
        let root: [String: Any] = [
            "userSignal": ["oaid": "", "vaid": "", "userId": userId],
            "environmentSignal": env,
            "timeSignal": ["clientTs": String(Int(now)), "timeZone": "中国标准时间"],
            "eventSignal": (try? JSONSerialization.jsonObject(with: Data(plain.utf8))) ?? [:],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: root, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func post(_ path: String, event: [String: Any]) async throws -> [String: Any] {
        guard !token.isEmpty, let u = user else { throw Failure.message("小米未登录") }
        let userId = u.cUserId ?? u.userId
        let eventData = (try? JSONSerialization.data(withJSONObject: event)) ?? Data()
        let eventText = String(data: eventData, encoding: .utf8) ?? "{}"
        let body = try aesB64(wrapBody(eventText, userId: userId))
        let encPath = try aesB64(path)
        let sign = Crypto.sha1Hex("yellowpage_encparam\(encPath)\(signSalt)")
        let e = encPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? encPath
        guard let url = URL(string: "\(host)\(path)?version=\(paVersion)&appkey=yellowpage&yellowpage_encparam=\(e)&sign=\(sign)&_encparam=\(e)") else {
            throw Failure.message("小米接口地址异常")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("serviceToken=\(token); cUserId=\(userId)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(body.utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard status == 200 else {
            throw Failure.message("小米接口 HTTP \(status)：\(text.prefix(80))")
        }
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.message("小米接口响应异常：\(text.prefix(80))")
        }
        if var encrypted = root["data"] as? String, !encrypted.isEmpty, encrypted != "null" {
            if let plain = aesUnb64(encrypted) {
                if let obj = try? JSONSerialization.jsonObject(with: Data(plain.utf8)) {
                    root["data"] = obj
                } else {
                    root["data"] = plain
                }
            }
            encrypted = ""
        }
        return root
    }

    // MARK: 列表

    func fetchList() async throws -> [MiItem] {
        do {
            return try await fetchListOnce()
        } catch {
            // serviceToken 过期：用存着的 passToken 重新换一次，不用重新扫码
            _ = try? await mintToken()
            return try await fetchListOnce()
        }
    }

    private func fetchListOnce() async throws -> [MiItem] {
        guard !phones.isEmpty else { throw Failure.message("先在小米设置里填要查询的手机号") }
        let root = try await post("/cpa/express/v2/getList",
                                  event: ["info": ["limit": 29, "phones": phones,
                                                   "deletedMailNos": [], "modifiedMailNos": []]])
        let code = (root["code"] as? NSNumber)?.intValue
        let status = (root["status"] as? [String: Any])?["code"] as? NSNumber
        if let code, code != 0 { throw Failure.message("小米列表失败：\(String(describing: root).prefix(100))") }
        if let status, status.intValue != 0 { throw Failure.message("小米列表失败：\(String(describing: root).prefix(100))") }

        let data = root["data"] as? [String: Any]
        let list = (data?["expressList"] as? [[String: Any]])
            ?? ((data?["info"] as? [String: Any])?["list"] as? [[String: Any]])
            ?? (data?["list"] as? [[String: Any]])
            ?? []
        return list.map { item in
            func s(_ keys: [String]) -> String {
                for k in keys {
                    if let v = item[k] as? String, !v.isEmpty { return v }
                    if let v = item[k] as? NSNumber { return v.stringValue }
                }
                return ""
            }
            return MiItem(
                mailNo: s(["mailNo", "mail_no"]),
                cpCode: s(["cpCode", "cp_code"]),
                cpName: s(["cpName", "cp_name"]),
                state: (item["state"] as? NSNumber)?.intValue ?? 0,
                stateDesc: s(["stateDesc", "state_desc"]),
                stationName: s(["stationName", "station_name"]),
                address: s(["address"]),
                pickupCode: s(["pickupCode", "pickup_code"]),
                productName: s(["productName", "product_name"]),
                logisticsUpdateTime: s(["logisticsUpdateTime", "logistics_update_time"])
            )
        }
    }
}
