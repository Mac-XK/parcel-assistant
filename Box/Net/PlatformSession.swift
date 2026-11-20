import Foundation
import Combine

struct StoredCookie: Codable, Hashable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
}

/// 当前账号视图：真正的存储在 AccountStore，这里只做「某平台当前账号」的便捷读取
@MainActor
final class PlatformSession: ObservableObject {
    static let shared = PlatformSession()

    @Published private(set) var authorized: Set<Platform> = []

    init() { refreshAll() }

    func refreshAll() {
        var set = Set<Platform>()
        for p in Platform.allCases where live(p) { set.insert(p) }
        authorized = set
    }

    private func live(_ p: Platform) -> Bool {
        if p == .cainiao { return hasSession(.taobao) }
        guard let acc = AccountStore.shared.active(p) else { return false }
        switch p {
        case .taobao, .jd, .pdd:
            return hasSession(p)
        case .cainiao:
            return hasSession(.taobao)
        case .fengchao, .mi:
            return !acc.token.isEmpty
        case .kdniao:
            return !acc.blob.isEmpty
        }
    }

    func isAuthorized(_ p: Platform) -> Bool { authorized.contains(p) }

    // MARK: 当前账号的 Cookie

    func cookies(for p: Platform) -> [StoredCookie] {
        AccountStore.shared.effective(p)?.cookies ?? []
    }

    /// 登录成功：按平台身份合并到账号列表（同账号覆盖，不同账号新增）
    func save(_ cookies: [HTTPCookie], for p: Platform) {
        let keep = cookies.filter { c in
            p.cookieDomains.contains { c.domain.hasSuffix($0) || c.domain.hasSuffix("." + $0) }
        }
        guard !keep.isEmpty else { return }
        let list = keep.map {
            StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, expires: $0.expiresDate)
        }
        let ident = AccountStore.identity(p, cookies: list) ?? "default-\(Int(Date().timeIntervalSince1970))"
        let label = AccountStore.label(p, cookies: list) ?? p.title
        AccountStore.shared.upsert(Account(id: "\(p.rawValue):\(ident)", platform: p, label: label, cookies: list))
    }

    /// 合并轮换下发的 cookie（_m_h5_tk）
    func merge(_ incoming: [HTTPCookie], for p: Platform) {
        guard !incoming.isEmpty else { return }
        AccountStore.shared.updateActive(p) { acc in
            for c in incoming {
                let item = StoredCookie(name: c.name, value: c.value, domain: c.domain, path: c.path, expires: c.expiresDate)
                if let i = acc.cookies.firstIndex(where: { $0.name == c.name && $0.domain == c.domain }) {
                    acc.cookies[i] = item
                } else {
                    acc.cookies.append(item)
                }
            }
        }
    }

    func hasSession(_ p: Platform) -> Bool {
        let list = cookies(for: p)
        guard !list.isEmpty else { return false }
        return list.contains { c in
            p.sessionCookies.contains(where: { c.name == $0 }) && !c.value.isEmpty
        }
    }

    func cookieHeader(for p: Platform) -> String? {
        let list = cookies(for: p)
        guard !list.isEmpty else { return nil }
        return list.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func value(_ name: String, in p: Platform) -> String? {
        cookies(for: p).first { $0.name == name }?.value
    }

    func clear(_ p: Platform) {
        AccountStore.shared.removeAll(p)
        // 顺手清掉旧版单账号残留，避免迁移逻辑又造一个账号出来
        Keychain.remove("platform.cookies.\(p.rawValue)")
        if p == .fengchao {
            ["fc.token", "fc.mobile", "fc.pending", "fc.ip", "fc.flag", "fc.uauth"].forEach { Keychain.remove($0) }
        }
        if p == .mi {
            ["mi.serviceToken", "mi.user", "mi.phones"].forEach { Keychain.remove($0) }
        }
        if p == .kdniao {
            ["kd.credential", "kd.token"].forEach { Keychain.remove($0) }
        }
        refreshAll()
    }
}
