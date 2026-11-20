import Foundation

/// 极小正则包装：与 Scripting 版 smsParse.ts 一一对应
struct RX {
    private let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        re = (try? NSRegularExpression(pattern: pattern, options: options)) ?? NSRegularExpression()
    }

    func test(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func first(_ s: String, group: Int = 1) -> String? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              group < m.numberOfRanges,
              let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    func groups(_ s: String, group: Int = 1) -> [String] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard group < m.numberOfRanges, m.range(at: group).location != NSNotFound else { return nil }
            return ns.substring(with: m.range(at: group))
        }
    }
}

struct ParsedDelivery {
    var mailNo: String?
    var company: String?
    var code: String?
    var station: String?
    var tail: String?
    var raw: String
    var hits: [String] = []

    var summary: String {
        var bits: [String] = []
        if let code { bits.append("取件码 \(code)") }
        if let mailNo { bits.append("单号 \(mailNo)") }
        if let station, !station.isEmpty { bits.append(station) }
        if let company, !company.isEmpty { bits.append(company) }
        return bits.isEmpty ? "未识别到包裹信息" : bits.joined(separator: " · ")
    }

    var isEmpty: Bool { mailNo == nil && (code ?? "").isEmpty && (station ?? "").isEmpty }
}

/// 短信 / 截图文字 → 包裹信息。纯本地正则，不联网。
enum DeliveryParser {

    // 快递公司：先看文案里的名字，没有再看单号前缀
    private static let companyWords: [(RX, String)] = [
        (RX("顺丰|丰声|SFExpress|SF\\s*速运", .caseInsensitive), "顺丰速运"),
        (RX("京东|京尊达"), "京东物流"),
        (RX("圆通"), "圆通快递"),
        (RX("中通"), "中通快递"),
        (RX("韵达"), "韵达快递"),
        (RX("申通"), "申通快递"),
        (RX("极兔|J&T", .caseInsensitive), "极兔速递"),
        (RX("德邦"), "德邦快递"),
        (RX("邮政|EMS|中国邮政", .caseInsensitive), "EMS"),
        (RX("百世|汇通"), "百世快递"),
        (RX("天天快递"), "天天快递"),
        (RX("宅急送"), "宅急送"),
        (RX("丰巢"), "丰巢"),
        (RX("菜鸟"), "菜鸟驿站"),
        (RX("兔喜"), "兔喜生活"),
        (RX("中邮|快宝"), "中邮快递"),
    ]

    // 单号：带前缀的优先
    private static let prefixMail: [(RX, String)] = [
        (RX("\\b(SF\\d{10,16})\\b", .caseInsensitive), "顺丰速运"),
        (RX("\\b(JDV?[A-Z0-9]{9,16})\\b", .caseInsensitive), "京东物流"),
        (RX("\\b(YT\\d{10,16})\\b", .caseInsensitive), "圆通快递"),
        (RX("\\b(JT\\d{10,16})\\b", .caseInsensitive), "极兔速递"),
        (RX("\\b(DPK[A-Z0-9]{8,16})\\b", .caseInsensitive), "德邦快递"),
        (RX("\\b([A-Z]{2}\\d{9}[A-Z]{2})\\b"), "EMS"),
        (RX("\\b(YD\\d{10,16})\\b", .caseInsensitive), "韵达快递"),
        (RX("\\b(STO\\d{10,16})\\b", .caseInsensitive), "申通快递"),
    ]

    // 取件码：多种写法，按可靠性排
    private static let codePatterns: [(RX, String)] = [
        (RX("(?:取件码|提货码|取货码|自提码|凭码|取件凭证|领取码)[:：\\s]*([0-9A-Za-z][0-9A-Za-z\\-]{2,14})(?![0-9A-Za-z])"), "取件码"),
        (RX("凭[:：\\s]*([0-9A-Za-z]+(?:-[0-9A-Za-z]+){1,3})(?=\\s*[到至去，,。\\s])"), "凭…到"),
        (RX("([0-9]+-[0-9]+-[0-9]{3,6})(?=\\s*[到至去，,。\\s]|$)"), "数字-数字-尾号"),
        (RX("(?:柜|格口|箱)[:：\\s]*([0-9]{3,8})(?![0-9])"), "柜格口"),
        (RX("(?:密码|开柜码)[:：\\s]*([0-9]{4,8})(?![0-9])"), "开柜码"),
    ]

    private static let tailPatterns: [RX] = [
        RX("尾号\\s*([0-9]{4})(?![0-9])"),
        RX("手机尾号\\s*([0-9]{4})(?![0-9])"),
        RX("\\(([0-9]{4})\\)\\s*(?:的|取件|包裹)"),
        RX("[（(]([0-9]{4})[)）]"),
    ]

    private static let stationPatterns: [(RX, Int)] = [
        (RX("[到至]\\s*([^\\s，,。；;、]{3,30}?)\\s*(?:取|领取|自取)"), 6),
        (RX("(?:存放至|放至|放置于|已放[到入]|已到达|已送达|已存入)\\s*([^\\s，,。；;]{2,30})"), 5),
        (RX("(?:位置|地址|网点)[:：]\\s*([^\\s，,。；;]{2,40})"), 4),
        (RX("([\\x{4e00}-\\x{9fa5}A-Za-z0-9]{2,20}(?:驿站|快递柜|自提点|快递超市|便利店|服务站|代收点|兔喜|丰巢))"), 2),
        // 原版没有这一条：「已到万科城店，取件码…」这种逗号断句的写法也能取到驿站
        (RX("(?:已到|到达|已至)\\s*([\\x{4e00}-\\x{9fa5}A-Za-z0-9]{2,20}(?:店|驿站|快递柜|自提点|超市|服务站|代收点))"), 3),
    ]

    private static let stationJunk = RX("如遇|请联系|联系|客服|热线|投诉|咨询|致电|电话|短信|退订|回复|截图|截屏|问题|请勿|注意|温馨|谢谢|官方|营业时间|工作时间|全天|自取请|取件请|凭码|凭取件")

    static func looksLikeStation(_ s: String) -> Bool {
        let v = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if v.count < 2 || v.count > 40 { return false }
        return !stationJunk.test(v)
    }

    private static func unescapeWidth(_ s: String) -> String {
        var out = ""
        for sc in s.unicodeScalars {
            let v = sc.value
            if v >= 0xFF01 && v <= 0xFF5E, let u = Unicode.Scalar(v - 0xFEE0) {
                out.append(Character(String(u)))
            } else if "－—–".unicodeScalars.contains(where: { $0 == sc }) {
                out.append("-")
            } else {
                out.append(Character(String(sc)))
            }
        }
        return out
    }

    private static func isNoise(_ v: String) -> Bool {
        let s = v.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return true }
        if RX("^1[3-9]\\d{9}$").test(s) { return true }
        if RX("^\\d{1,2}:\\d{2}$").test(s) { return true }
        if RX("^\\d{4}[-/年]\\d{1,2}[-/月]\\d{1,2}日?$").test(s) { return true }
        if RX("^\\d+(\\.\\d+)?$").test(s) && s.count <= 3 { return true }
        if RX("^\\d{4}-\\d{4}-\\d{4}-\\d{4}$").test(s) { return true }
        return false
    }

    private static func normalizeCode(_ v: String) -> String {
        v.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^[:：\\s]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[。，,；;]+$", with: "", options: .regularExpression)
    }

    private static let cutHead = RX("^(?:您的|你的)?(?:包裹|快件|快递|订单)?(?:已经|已)?(?:到达|送到|存放至|放至|放置于|送达|存入|到了|到)\\s*")
    private static let genericStation = RX("^(驿站|自提点|快递柜|快递超市|便利店|代收点|柜|快递驿站|快递点|服务点)$")
    private static let scoreGood = RX("驿站|快递柜|自提点|超市|便利店|服务站|代收点|柜|店|中心")
    private static let scoreBad = RX("您的|你的|订单|快件已|包裹已|快递已|已到|已经|请到|请至|可到|尽快")

    private static func bestStation(_ text: String) -> String? {
        var cands: [(s: String, base: Int)] = []
        for (rx, base) in stationPatterns {
            for raw in rx.groups(text) {
                var s = raw.trimmingCharacters(in: .whitespaces)
                s = s.replacingOccurrences(of: "[，,。；;、]+$", with: "", options: .regularExpression)
                if let cut = cutHead.first(s), cut.count >= 3, cut != s { s = cut }
                if genericStation.test(s) { continue }
                if s.count >= 3 && s.count <= 30 && looksLikeStation(s) {
                    cands.append((s, base))
                }
            }
        }
        func score(_ s: String, _ base: Int) -> Int {
            var n = base
            if scoreGood.test(s) { n += 3 }
            if scoreBad.test(s) { n -= 6 }
            if !looksLikeStation(s) { n -= 20 }
            if s.count >= 4 && s.count <= 20 { n += 1 }
            return n
        }
        var best: String?
        var bestScore = 0
        for c in cands {
            let sc = score(c.s, c.base)
            if sc > bestScore || (sc == bestScore && best != nil && sc > 0 && c.s.count > (best?.count ?? 0)) {
                bestScore = sc
                best = c.s
            }
        }
        return bestScore > 0 ? best : nil
    }

    static func parse(_ input: String) -> ParsedDelivery {
        let raw = input.replacingOccurrences(of: "\r", with: "")
        let text = unescapeWidth(raw)
        var out = ParsedDelivery(raw: raw)

        // 1) 带前缀单号
        for (rx, company) in prefixMail {
            if let m = rx.first(text), !isNoise(m) {
                out.mailNo = m.uppercased()
                out.company = company
                out.hits.append("单号 \(m)（\(company)）")
                break
            }
        }

        // 2) 公司名
        for (rx, name) in companyWords where rx.test(text) {
            if out.company == nil { out.company = name }
            out.hits.append("公司 \(name)")
            break
        }

        // 3) 取件码
        for (rx, label) in codePatterns {
            guard let m = rx.first(text) else { continue }
            let code = normalizeCode(m)
            if code.isEmpty || isNoise(code) { continue }
            if let no = out.mailNo, code.uppercased() == no.uppercased() { continue }
            out.code = code
            out.hits.append("取件码 \(code)（\(label)）")
            break
        }

        // 4) 长数字里的运单号
        if out.mailNo == nil {
            let cands = RX("\\b(\\d{12,20})\\b").groups(text)
            for c in cands {
                guard RX("^\\d{12,20}$").test(c), !RX("^1[3-9]\\d{9}$").test(c) else { continue }
                if let code = out.code, c == code.replacingOccurrences(of: "-", with: "") { continue }
                out.mailNo = c
                out.hits.append("单号 \(c)")
                break
            }
        }

        // 5) 尾号
        for rx in tailPatterns {
            if let m = rx.first(text) {
                out.tail = m
                out.hits.append("尾号 \(m)")
                break
            }
        }

        // 6) 驿站
        if let st = bestStation(text), !(out.code.map { st.contains($0) } ?? false) {
            out.station = st
            out.hits.append("驿站 \(st)")
        }

        return out
    }
}
