import Foundation
import Combine

/// 平台身份码：真接口，取不到就报错，不本地编假码
@MainActor
final class IdentityService {
    static let shared = IdentityService()

    private var cache: [IdentityKind: IdentityCode] = [:]

    enum Failure: LocalizedError {
        case needLogin(String)
        case message(String)
        var errorDescription: String? {
            switch self {
            case .needLogin(let s): return s
            case .message(let s): return s
            }
        }
    }

    func cached(_ kind: IdentityKind) -> IdentityCode? {
        guard let c = cache[kind], c.expiresAt > Date().addingTimeInterval(20) else { return nil }
        return c
    }

    func fetch(_ kind: IdentityKind, force: Bool = false) async throws -> IdentityCode {
        if !force, let c = cached(kind) { return c }
        switch kind {
        case .cainiao:
            guard PlatformSession.shared.isAuthorized(.taobao) else {
                throw Failure.needLogin("菜鸟身份码用的是淘宝登录态，先登录淘宝")
            }
            let json = try await MTop.call("mtop.cainiao.nbpickup.identitycode.get",
                                           data: ["appName": "GUOGUO", "verifyVersion": "V2"])
            let model = (MTop.payload(json) as? [String: Any])?["model"] as? [String: Any] ?? [:]
            guard let code = model["identityCode"] as? String, !code.isEmpty else {
                throw Failure.message("菜鸟接口没给身份码")
            }
            let seconds = Int((model["expireTime"] as? NSNumber)?.doubleValue ?? 600)
            let out = IdentityCode(id: kind, code: code,
                                   expiresAt: Date().addingTimeInterval(TimeInterval(max(60, seconds))),
                                   detail: (model["fullname"] as? String) ?? "")
            cache[kind] = out
            return out

        case .taobao:
            guard PlatformSession.shared.isAuthorized(.taobao) else {
                throw Failure.needLogin("先登录淘宝")
            }
            let json = try await MTop.call("mtop.cainiao.pickup.identity.getIdentityMessage", data: [:])
            let payload = MTop.payload(json)
            guard let code = Self.findCode(payload) else {
                throw Failure.message("淘宝接口没给身份码")
            }
            let seconds = Self.findExpire(payload) ?? 300
            let out = IdentityCode(id: kind, code: code,
                                   expiresAt: Date().addingTimeInterval(TimeInterval(max(60, seconds))))
            cache[kind] = out
            return out
        }
    }

    // 淘宝接口没有公开结构：按「CS/NB 开头 + 数字字母」递归找，最多 6 层
    private static func findCode(_ node: Any?, depth: Int = 0) -> String? {
        guard depth <= 6, let node else { return nil }
        if let s = node as? String {
            if s.range(of: "^[A-Z]{2}[0-9A-Z]{8,26}$", options: .regularExpression) != nil { return s }
            return nil
        }
        if let arr = node as? [Any] {
            for v in arr { if let hit = findCode(v, depth: depth + 1) { return hit } }
            return nil
        }
        if let dict = node as? [String: Any] {
            for (k, v) in dict where k.lowercased().contains("code") || k.lowercased().contains("identity") {
                if let hit = findCode(v, depth: depth + 1) { return hit }
            }
            for (_, v) in dict {
                if let hit = findCode(v, depth: depth + 1) { return hit }
            }
        }
        return nil
    }

    private static func findExpire(_ node: Any?, depth: Int = 0) -> Int? {
        guard depth <= 6, let node else { return nil }
        if let dict = node as? [String: Any] {
            for (k, v) in dict where k.lowercased().contains("expire") {
                if let n = v as? NSNumber, n.doubleValue > 0 {
                    let d = n.doubleValue
                    return d > 1_000_000 ? Int(d / 1000) : Int(d)
                }
            }
            for (_, v) in dict { if let hit = findExpire(v, depth: depth + 1) { return hit } }
        }
        if let arr = node as? [Any] {
            for v in arr { if let hit = findExpire(v, depth: depth + 1) { return hit } }
        }
        return nil
    }
}
