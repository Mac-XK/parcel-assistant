import Foundation
import Combine

/// 一个平台账号的全部凭证。Cookie 类存 cookies，丰巢/小米/快递鸟存 token + blob。
struct Account: Codable, Identifiable, Hashable {
    var id: String            // "<platform>:<identity>"
    var platform: Platform
    var label: String
    var cookies: [StoredCookie] = []
    var token: String = ""
    /// 额外信息 JSON：丰巢手机号/开柜头、小米 user、快递鸟密钥
    var blob: String = ""
    var addedAt: Date = Date()

    var identity: String { id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id }
}

/// 多账号仓库：所有平台的账号都在这里，active 记录每个平台当前用哪个
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var active: [Platform: String] = [:]

    private let listKey = "accounts.v2"
    private let activeKey = "accounts.active"

    init() {
        load()
        if accounts.isEmpty { migrateLegacy() }
    }

    // MARK: 读写

    private func load() {
        if let raw = Keychain.get(listKey), let d = raw.data(using: .utf8),
           let list = try? JSONDecoder().decode([Account].self, from: d) {
            accounts = list
        }
        if let raw = Keychain.get(activeKey),
           let map = try? JSONDecoder().decode([String: String].self, from: raw.data(using: .utf8) ?? Data()) {
            var out: [Platform: String] = [:]
            for (k, v) in map {
                if let p = Platform(rawValue: k) { out[p] = v }
            }
            active = out
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(accounts), let raw = String(data: d, encoding: .utf8) {
            Keychain.set(raw, for: listKey)
        }
        var map: [String: String] = [:]
        for (p, v) in active { map[p.rawValue] = v }
        if let d = try? JSONEncoder().encode(map), let raw = String(data: d, encoding: .utf8) {
            Keychain.set(raw, for: activeKey)
        }
        PlatformSession.shared.refreshAll()
    }

    // MARK: 查询

    func accounts(_ p: Platform) -> [Account] {
        accounts.filter { $0.platform == p }.sorted { $0.addedAt < $1.addedAt }
    }

    func active(_ p: Platform) -> Account? {
        let list = accounts(p)
        guard !list.isEmpty else { return nil }
        if let id = active[p], let hit = list.first(where: { $0.id == id }) { return hit }
        return list.first
    }

    func count(_ p: Platform) -> Int { accounts(p).count }

    /// 菜鸟没有自己的账号，永远跟随淘宝当前账号
    func effective(_ p: Platform) -> Account? {
        if p == .cainiao { return active(.taobao) }
        return active(p)
    }

    // MARK: 变更

    /// 同 id 覆盖（同一个账号重新登录），否则追加
    @discardableResult
    func upsert(_ account: Account, makeActive: Bool = true) -> Account {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            var merged = account
            merged.addedAt = accounts[i].addedAt
            accounts[i] = merged
        } else {
            accounts.append(account)
        }
        if makeActive { active[account.platform] = account.id }
        persist()
        return account
    }

    func switchTo(_ id: String, _ p: Platform) {
        active[p] = id
        persist()
    }

    func remove(_ id: String, _ p: Platform) {
        accounts.removeAll { $0.id == id }
        if active[p] == id {
            active[p] = accounts(p).first?.id
        }
        persist()
    }

    func removeAll(_ p: Platform) {
        accounts.removeAll { $0.platform == p }
        active[p] = nil
        persist()
    }

    func updateActive(_ p: Platform, _ mutate: (inout Account) -> Void) {
        guard let cur = active(p), let i = accounts.firstIndex(where: { $0.id == cur.id }) else { return }
        mutate(&accounts[i])
        persist()
    }

    // MARK: 旧版单账号数据迁移

    private func migrateLegacy() {
        // Cookie 平台
        for p in [Platform.taobao, .jd, .pdd] {
            let key = "platform.cookies.\(p.rawValue)"
            guard let raw = Keychain.get(key), let d = raw.data(using: .utf8),
                  let list = try? JSONDecoder().decode([StoredCookie].self, from: d), !list.isEmpty else { continue }
            let ident = Self.identity(p, cookies: list) ?? "default"
            let label = Self.label(p, cookies: list) ?? p.title
            upsert(Account(id: "\(p.rawValue):\(ident)", platform: p, label: label, cookies: list))
        }
        // 丰巢
        if let token = Keychain.get("fc.token"), !token.isEmpty {
            let mobile = Keychain.get("fc.mobile") ?? ""
            var blob: [String: String] = ["mobile": mobile]
            if let f = Keychain.get("fc.flag") { blob["flag"] = f }
            if let u = Keychain.get("fc.uauth") { blob["uauth"] = u }
            if let ip = Keychain.get("fc.clientip") { blob["ip"] = ip }
            let json = (try? JSONSerialization.data(withJSONObject: blob)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let label = mobile.count == 11 ? Self.mask(mobile) : "丰巢账号"
            upsert(Account(id: "fengchao:\(mobile.isEmpty ? "default" : mobile)", platform: .fengchao,
                           label: label, token: token, blob: json))
        }
        // 小米
        if let token = Keychain.get("mi.serviceToken"), !token.isEmpty {
            var blob: [String: String] = [:]
            if let u = Keychain.get("mi.user") { blob["user"] = u }
            if let ph = Keychain.get("mi.phones") { blob["phones"] = ph }
            let json = (try? JSONSerialization.data(withJSONObject: blob)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let userId = (Keychain.get("mi.user") ?? "").data(using: .utf8)
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["userId"] as? String
            upsert(Account(id: "mi:\(userId ?? "default")", platform: .mi, label: "小米 \(userId ?? "")".trimmingCharacters(in: .whitespaces),
                           token: token, blob: json))
        }
        // 快递鸟
        if let raw = Keychain.get("kd.credential"), let d = raw.data(using: .utf8),
           let cred = try? JSONDecoder().decode(KdCredential.self, from: d) {
            let json = (try? JSONEncoder().encode(cred)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            upsert(Account(id: "kdniao:\(cred.eBusinessId)", platform: .kdniao,
                           label: "EB\(cred.eBusinessId.prefix(6))", blob: json))
        }
        if !accounts.isEmpty {
            // 迁移完成就把旧 key 删掉，避免下次启动又造一份
            ["platform.cookies.taobao", "platform.cookies.jd", "platform.cookies.pdd",
             "fc.token", "fc.mobile", "fc.flag", "fc.uauth", "fc.clientip",
             "mi.serviceToken", "mi.user", "mi.phones", "kd.credential", "kd.token"].forEach { Keychain.remove($0) }
            persist()
        }
    }

    // MARK: 识别账号身份 / 名称

    static func identity(_ p: Platform, cookies: [StoredCookie]) -> String? {
        func v(_ n: String) -> String? {
            cookies.first { $0.name == n }.map(\.value).flatMap { $0.isEmpty ? nil : $0 }
        }
        switch p {
        case .taobao, .cainiao: return v("unb") ?? v("tracknick")
        case .jd: return v("pt_pin")?.removingPercentEncoding ?? v("pt_pin")
        case .pdd: return v("pdd_user_id") ?? v("api_uid") ?? v("PDDAccessToken")
        default: return nil
        }
    }

    static func label(_ p: Platform, cookies: [StoredCookie]) -> String? {
        func v(_ n: String) -> String? {
            cookies.first { $0.name == n }.map(\.value).flatMap { $0.isEmpty ? nil : $0 }
        }
        switch p {
        case .taobao, .cainiao:
            if let n = v("tracknick")?.removingPercentEncoding, !n.isEmpty { return n }
            if let u = v("unb"), u.count > 4 { return "淘宝 \(u.suffix(4))" }
        case .jd:
            if let n = v("pt_pin")?.removingPercentEncoding, !n.isEmpty { return n }
        case .pdd:
            if let u = v("pdd_user_id"), u.count > 4 { return "拼多多 \(u.suffix(4))" }
        default: break
        }
        return nil
    }

    static func mask(_ mobile: String) -> String {
        guard mobile.count >= 7 else { return mobile }
        return mobile.prefix(3) + "****" + mobile.suffix(4)
    }
}
