import Foundation

// MARK: - 丰巢

struct FcPick: Codable, Hashable {
    var expressId: String
    var code: String
    var companyName: String
    var cabinetCode: String
    var address: String
    var location: String
    var sendTm: String
    var clientMobile: String
    var postId: String
    var boxId: String
    var boxGlobalRow: String
    var companyLogoUrl: String
    var staffMobile: String
    var expressType: Int
}

struct FcBoxMeta: Codable, Hashable {
    var cabinetCode: String
    var boxId: String
    var boxGlobalRow: String
    var code: String
    var expressId: String
    var postId: String
    var address: String
    var location: String
    var clientMobile: String
    var companyName: String
    var expressType: Int

    init(_ p: FcPick) {
        cabinetCode = p.cabinetCode
        boxId = p.boxId
        boxGlobalRow = p.boxGlobalRow
        code = p.code
        expressId = p.expressId
        postId = p.postId
        address = p.address
        location = p.location
        clientMobile = p.clientMobile
        companyName = p.companyName
        expressType = p.expressType
    }
}

@MainActor
final class FengchaoService {
    static let shared = FengchaoService()

    private let base = "https://consumer.fcbox.com"
    private let op = "30b2718363204beeae98b7d03a75c3a4"
    private let K = (pending: "fc.pending", ip: "fc.clientip")

    var account: Account? { AccountStore.shared.active(.fengchao) }
    private var blob: [String: String] {
        guard let a = account, let d = a.blob.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }

    struct Pending: Codable {
        var pubKey: String
        var ts: String
        var ip: String
        var rc: String
    }

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let m) = self { return m }
            return nil
        }
    }

    var token: String { account?.token ?? "" }
    var mobile: String { blob["mobile"] ?? "" }
    var isLoggedIn: Bool { !token.isEmpty }

    func clear() {
        AccountStore.shared.removeAll(.fengchao)
        Keychain.remove(K.pending)
        Keychain.remove(K.ip)
        PlatformSession.shared.refreshAll()
    }

    private func ua(ip: String = "") -> String {
        "channel=xiaomi,ip=\(ip),os=15,deviceType=2211133C,platform=Android,resolution=1080*2296,versionCode=6007000,versionName=6.7.0,timestamp=\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    private struct Resp {
        var status: Int
        var json: [String: Any]?
        var text: String
        var headers: [AnyHashable: Any]
        func header(_ name: String) -> String {
            for (k, v) in headers where String(describing: k).lowercased() == name.lowercased() {
                return String(describing: v)
            }
            return ""
        }
    }

    private func call(_ path: String, method: String = "GET", auth: String? = nil,
                      body: [String: Any]? = nil, extra: [String: String] = [:]) async throws -> Resp {
        guard let url = URL(string: base + path) else { throw Failure.message("丰巢地址异常") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(ua(ip: Keychain.get(K.ip) ?? ""), forHTTPHeaderField: "User-Agent")
        req.setValue("", forHTTPHeaderField: "FC_USER_FLAG")
        req.setValue("1", forHTTPHeaderField: "pinpoint-spanid")
        req.setValue("true", forHTTPHeaderField: "pinpoint-sampled")
        req.setValue("-1", forHTTPHeaderField: "pinpoint-pspanid")
        for (k, v) in extra where !v.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
        if let auth, !auth.isEmpty { req.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let text = String(data: data, encoding: .utf8) ?? ""
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return Resp(status: http?.statusCode ?? 0, json: json, text: text, headers: http?.allHeaderFields ?? [:])
    }

    private func ok(_ j: [String: Any]?) -> Bool {
        guard let j else { return false }
        let code = (j["code"] as? NSNumber)?.intValue ?? -1
        return code == 0 || code == 150_100_000 || (j["success"] as? Bool) == true
    }

    private func msg(_ j: [String: Any]?, _ status: Int) -> String {
        let m = (j?["msg"] as? String) ?? (j?["message"] as? String) ?? ""
        return m.isEmpty ? "HTTP \(status)" : m
    }

    // MARK: 发验证码

    func sendCode(_ input: String) async throws {
        let m = input.filter(\.isNumber)
        guard m.count == 11, m.hasPrefix("1") else { throw Failure.message("手机号格式不对") }
        let chk = try await call("/v1/account/secureCheckMobile?mobile=\(m)&type=11&opCode=\(op)&nationCode=86")
        guard let d = chk.json?["data"] as? [String: Any] else {
            throw Failure.message("丰巢接口无响应（\(chk.status)）")
        }
        if let slider = d["needSliderCode"] as? Bool, slider {
            throw Failure.message("丰巢要求滑块验证，请先在丰巢 App 登录一次")
        }
        func s(_ v: Any?) -> String {
            if let x = v as? String { return x == "null" ? "" : x }
            if let x = v as? NSNumber { return x.stringValue }
            return ""
        }
        let order = s(d["keyOrder"]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var pubKey = ""
        for i in 1...5 {
            guard order.count >= i else { break }
            pubKey += s(d["key" + order[i - 1]])
        }
        guard pubKey.count > 100 else { throw Failure.message("取签名公钥失败") }

        let ts = s(d["timestamp"])
        let ip = s(d["clientIp"])
        let rc = s(d["requestCode"])
        if !ip.isEmpty { Keychain.set(ip, for: K.ip) }

        let md5text = "86\(m)11\(ts)\(ip)\(rc)\(op)"
        let sign = "86\(m)" + Crypto.md5Hex(md5text)
        guard let enc = RSA.encryptPKCS1(sign, spkiBase64: pubKey) else {
            throw Failure.message("RSA 签名失败")
        }
        let encEsc = enc.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? enc

        let res = try await call("/v1/account/secureSendCode?mobile=\(m)&type=11&opCode=\(op)&nationCode=86&sliderTicket=&sliderRandstr=&sign=\(encEsc)",
                                 method: "POST")
        guard ok(res.json) else { throw Failure.message("发码失败：\(msg(res.json, res.status))") }

        if let data = try? JSONEncoder().encode(Pending(pubKey: pubKey, ts: ts, ip: ip, rc: rc)),
           let raw = String(data: data, encoding: .utf8) {
            Keychain.set(raw, for: K.pending)
        }
    }

    // MARK: 登录

    func login(mobile input: String, code input2: String) async throws {
        let m = input.filter(\.isNumber)
        let c = input2.filter(\.isNumber)
        guard c.count >= 4 else { throw Failure.message("验证码不对") }
        guard let raw = Keychain.get(K.pending), let d = raw.data(using: .utf8),
              let p = try? JSONDecoder().decode(Pending.self, from: d), !p.pubKey.isEmpty else {
            throw Failure.message("请先获取验证码")
        }
        let md5text = "86\(m)\(c)01\(p.ts)\(p.ip)\(p.rc)\(op)"
        let sign = "86\(m)" + Crypto.md5Hex(md5text)
        guard let enc = RSA.encryptPKCS1(sign, spkiBase64: p.pubKey) else {
            throw Failure.message("RSA 签名失败")
        }
        let encEsc = enc.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? enc
        let res = try await call("/v1/account/secureLoginByPhone?mobile=\(m)&verifyCode=\(c)&channel=0&type=1&weiXinUser=&nationCode=86&opCode=\(op)&sign=\(encEsc)",
                                 method: "POST")
        let auth = res.header("Authorization")
        guard !auth.isEmpty else { throw Failure.message("登录失败：\(msg(res.json, res.status))") }
        let flag = res.header("FC_USER_FLAG")
        let uauth = res.header("FC_USER_AUTH")
        var info = blob
        info["mobile"] = m
        info["ip"] = Keychain.get(K.ip) ?? info["ip"] ?? ""
        if !flag.isEmpty { info["flag"] = flag }
        if !uauth.isEmpty { info["uauth"] = uauth }
        let json = (try? JSONSerialization.data(withJSONObject: info))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        AccountStore.shared.upsert(Account(id: "fengchao:\(m)", platform: .fengchao,
                                           label: AccountStore.mask(m), token: auth, blob: json))
        Keychain.remove(K.pending)
        PlatformSession.shared.refreshAll()
    }

    // MARK: 在柜待取

    func waitPick() async throws -> [FcPick] {
        guard !token.isEmpty else { throw Failure.message("丰巢未授权") }
        let res = try await call("/post/mobilePick/queryWaitPick?channelCode=ANDROID_FC_APP", auth: token)
        if !ok(res.json) {
            if res.status == 401 || ((res.json?["code"] as? NSNumber)?.intValue == 401) {
                clear()
                throw Failure.message("丰巢登录已失效，请重新授权")
            }
            throw Failure.message("丰巢查件失败：\(msg(res.json, res.status))")
        }
        var out: [FcPick] = []
        let data = res.json?["data"] as? [String: Any]
        let cabinets = data?["cabinets"] as? [[String: Any]] ?? []
        for cab in cabinets {
            for box in (cab["boxes"] as? [[String: Any]] ?? []) {
                for pkg in (box["packages"] as? [[String: Any]] ?? []) {
                    func s(_ v: Any?) -> String {
                        if let x = v as? String { return x.trimmingCharacters(in: .whitespaces) }
                        if let x = v as? NSNumber { return x.stringValue }
                        return ""
                    }
                    out.append(FcPick(
                        expressId: s(pkg["expressId"]),
                        code: s(pkg["code"]),
                        companyName: s(pkg["companyName"]),
                        cabinetCode: s(cab["cabinetCode"]),
                        address: s(cab["address"]),
                        location: s(box["location"]),
                        sendTm: s(pkg["sendTm"]),
                        clientMobile: s(pkg["clientMobile"]),
                        postId: s(pkg["postId"]),
                        boxId: s(box["boxId"]),
                        boxGlobalRow: s(pkg["boxGlobalRow"]),
                        companyLogoUrl: s(pkg["companyLogoUrl"]),
                        staffMobile: s(pkg["staffMobile"]),
                        expressType: (pkg["expressType"] as? NSNumber)?.intValue ?? 1
                    ))
                }
            }
        }
        return out
    }

    // MARK: 一键开柜

    private var openedKey = ""
    private var openedAt: Date = .distantPast

    func openBox(_ meta: FcBoxMeta) async throws {
        guard !token.isEmpty else { throw Failure.message("丰巢未授权") }
        guard !meta.cabinetCode.isEmpty, !(meta.boxId.isEmpty && meta.code.isEmpty) else {
            throw Failure.message("缺少柜机信息，请先刷新丰巢")
        }
        let key = [meta.cabinetCode, meta.boxId, meta.code, meta.expressId].joined(separator: "|")
        if key == openedKey && Date().timeIntervalSince(openedAt) < 20 { return }

        let body: [String: Any] = [
            "cabinetCode": meta.cabinetCode,
            "channel": "APP-ANDRIOD",
            "clientMobile": meta.clientMobile.isEmpty ? mobile : meta.clientMobile,
            "cmdkType": "1",
            "expressId": meta.expressId,
            "localActivityId": "",
            "localAddress": meta.address,
            "localAllBoxIdList": [],
            "localBoxGlobalRow": meta.boxGlobalRow,
            "localCode": meta.code,
            "localCurrBoxId": meta.boxId,
            "localDigitizationStatus": 0,
            "localFromSource": "2",
            "localOneClickOpenCabinetValidTime": "",
            "localOrderId": "",
            "localPopupTimeout": 120,
            "localRefusePackages": [],
            "localRefuseSessionTokenTime": 120,
            "localScanFirst": true,
            "localScanTotal": 0,
            "localSource": "0",
            "localSupportVisual": false,
            "mobilePickType": "APP-ANDRIOD",
            "pickType": "ANDROID_PICK_MOBILE_APP",
            "postId": meta.postId,
        ]
        var extra: [String: String] = [:]
        let flag = blob["flag"] ?? ""
        let uauth = blob["uauth"] ?? ""
        if !flag.isEmpty { extra["FLAG"] = flag; extra["FC_USER_FLAG"] = flag }
        if !uauth.isEmpty { extra["FC_USER_AUTH"] = uauth }
        let res = try await call("/post/clientGet/openBox", method: "POST", auth: token, body: body, extra: extra)
        if res.status == 401 || ((res.json?["code"] as? NSNumber)?.intValue == 401) {
            clear()
            throw Failure.message("丰巢登录已失效，请重新授权")
        }
        guard ok(res.json) else { throw Failure.message("丰巢开柜失败：\(msg(res.json, res.status))") }
        openedKey = key
        openedAt = Date()
    }
}
