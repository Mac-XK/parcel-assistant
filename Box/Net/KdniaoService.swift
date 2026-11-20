import Foundation

// MARK: - 快递鸟（查单兜底）

struct KdCredential: Codable, Hashable {
    var eBusinessId: String
    var appKey: String
    var userId: String?
}

struct KdNode: Codable, Hashable {
    var time: String
    var text: String
}

struct KdTrack: Codable, Hashable {
    var mailNo: String
    var shipperCode: String
    var company: String
    /// 3 = 已签收
    var state: String
    var latest: String
    var nodes: [KdNode]
    var pickupCode: String?

    var isDelivered: Bool { state == "3" || latest.contains("签收") || latest.contains("已取件") }
}

@MainActor
final class KdniaoService {
    static let shared = KdniaoService()

    private let apiBase = "https://api.kdniao.com/Ebusiness/EbusinessOrderHandle.aspx"

    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    var account: Account? { AccountStore.shared.active(.kdniao) }

    var credential: KdCredential? {
        guard let a = account, let d = a.blob.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KdCredential.self, from: d)
    }

    var isLoggedIn: Bool { credential != nil }

    func save(_ c: KdCredential) {
        let raw = (try? JSONEncoder().encode(c)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let short = String(c.eBusinessId.suffix(6))
        AccountStore.shared.upsert(Account(id: "kdniao:\(c.eBusinessId)", platform: .kdniao,
                                           label: "快递鸟 \(short)", blob: raw))
        PlatformSession.shared.refreshAll()
    }

    func clear() {
        AccountStore.shared.removeAll(.kdniao)
        PlatformSession.shared.refreshAll()
    }

    /// DataSign = base64(hex(md5(RequestData + AppKey)))，小写十六进制
    private func dataSign(_ requestData: String, _ appKey: String) -> String {
        let hex = Crypto.md5Hex(requestData + appKey).lowercased()
        return Data(hex.utf8).base64EncodedString()
    }

    private func postForm(_ pairs: [(String, String)]) async throws -> [String: Any] {
        guard let url = URL(string: apiBase) else { throw Failure.message("快递鸟地址异常") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Form.encode(pairs)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw Failure.message("快递鸟返回异常：\(text.prefix(80))")
        }
        return json
    }

    // MARK: 8001 即时查询

    func query(mailNo: String, shipperCode: String?, phone: String = "") async throws -> KdTrack {
        guard let cred = credential else { throw Failure.message("还没有连接快递鸟账号") }
        var code = shipperCode ?? ""
        var companyName = ""
        if code.isEmpty {
            let d = try await detectShipper(mailNo: mailNo)
            code = d.code
            companyName = d.name
        }
        var rd: [String: Any] = ["LogisticCode": mailNo, "ShipperCode": code]
        if !phone.isEmpty { rd["CustomerName"] = phone }
        guard let data = try? JSONSerialization.data(withJSONObject: rd, options: [.sortedKeys]),
              let requestData = String(data: data, encoding: .utf8) else {
            throw Failure.message("请求体编码失败")
        }
        let sign = dataSign(requestData, cred.appKey)
        let json = try await postForm([
            ("RequestData", requestData),
            ("EBusinessID", cred.eBusinessId),
            ("RequestType", "8001"),
            ("DataSign", sign),
            ("DataType", "2"),
        ])
        let success = (json["Success"] as? Bool) ?? false
        let reason = (json["Reason"] as? String) ?? ""
        let traces = json["Traces"] as? [[String: Any]] ?? []
        if !success && traces.isEmpty {
            throw Failure.message(reason.isEmpty ? "快递鸟没有返回轨迹" : reason)
        }
        let nodes: [KdNode] = traces.reversed().compactMap { t in
            let time = (t["AcceptTime"] as? String) ?? ""
            let text = (t["AcceptStation"] as? String) ?? ""
            return text.isEmpty ? nil : KdNode(time: time, text: text)
        }
        let latest = nodes.first?.text ?? ""
        var pick: String? = nil
        for n in nodes {
            if let c = Self.pickupCode(in: n.text, mailNo: mailNo) { pick = c; break }
        }
        let state = (json["State"] as? String) ?? ""
        return KdTrack(mailNo: mailNo,
                       shipperCode: (json["ShipperCode"] as? String) ?? code,
                       company: companyName.isEmpty ? Self.companyName(code) : companyName,
                       state: state,
                       latest: latest,
                       nodes: nodes,
                       pickupCode: pick)
    }

    // MARK: 单号识别（先菜鸟，后快递100）

    func detectShipper(mailNo: String) async throws -> (code: String, name: String) {
        var comps = URLComponents(string: "https://www.kuaidi100.com/autonumber/autoComNum")!
        comps.queryItems = [.init(name: "resultv2", value: "1"), .init(name: "text", value: mailNo)]
        if let url = comps.url {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = json["comCode"] as? [[String: Any]],
               let first = list.first,
               let comCode = first["comCode"] as? String, !comCode.isEmpty {
                return (Self.shipperCode(comCode), Self.companyName(Self.shipperCode(comCode)))
            }
        }
        throw Failure.message("没认出快递公司，请手动选择或先授权菜鸟")
    }

    static func pickupCode(in text: String, mailNo: String) -> String? {
        let patterns = [
            "(?:取件码|提货码|取货码)[:：\\s]*([0-9A-Za-z][0-9A-Za-z\\-]{2,14})",
            "([0-9]+-[0-9]+-[0-9]{3,6})",
        ]
        for p in patterns {
            if let m = text.range(of: p, options: .regularExpression) {
                var code = String(text[m])
                if let colon = code.firstIndex(where: { $0 == "：" || $0 == ":" }) {
                    code = String(code[code.index(after: colon)...])
                }
                code = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[，,。；;]+$", with: "", options: .regularExpression)
                if !code.isEmpty, code != mailNo { return code }
            }
        }
        return nil
    }

    static func shipperCode(_ com: String) -> String {
        let map: [String: String] = [
            "zhongtong": "ZTO", "zto": "ZTO",
            "yunda": "YUNDA",
            "yuantong": "YTO", "yto": "YTO",
            "shentong": "STO", "sto": "STO",
            "shunfeng": "SF", "sf": "SF",
            "jd": "JD",
            "jtexpress": "JT", "jt": "JT",
            "youzhengguonei": "YZPY", "ems": "EMS",
            "youshu": "YS",
            "debang": "DBWL",
            "bestex": "HTKY", "bestexpress": "HTKY",
            "zhaijisong": "ZJS", "tiantian": "TTKDEX", "guotong": "GTO",
        ]
        return map[com.lowercased()] ?? com.uppercased()
    }

    static func companyName(_ shipper: String) -> String {
        let map: [String: String] = [
            "ZTO": "中通快递", "SF": "顺丰速运", "YTO": "圆通速递", "YUNDA": "韵达快递",
            "STO": "申通快递", "JT": "极兔速递", "JD": "京东物流", "DBWL": "德邦快递",
            "HTKY": "百世快递", "YZPY": "中国邮政", "EMS": "EMS", "YS": "邮政快递包裹",
            "ZJS": "宅急送", "TTKDEX": "天天快递", "GTO": "国通快递",
        ]
        return map[shipper.uppercased()] ?? shipper
    }
}
