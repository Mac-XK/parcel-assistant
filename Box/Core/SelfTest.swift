#if DEBUG
import Foundation

/// `-selftest` 启动参数：无 UI 跑一遍核心逻辑，输出到控制台，方便脚本化回归
enum SelfTest {
    static func runIfRequested() {
        if ProcessInfo.processInfo.arguments.contains("-simpletest") {
            Task { @MainActor in
                Store.shared.settings.simpleMode = true
                Store.shared.save()
                print("[simpletest] on")
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                Store.shared.settings.simpleMode = false
                Store.shared.save()
                print("[simpletest] off")
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-simple") {
            Task { @MainActor in
                Store.shared.settings.simpleMode = true
                Store.shared.save()
                print("[simple] on")
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-normal") {
            Task { @MainActor in
                Store.shared.settings.simpleMode = false
                Store.shared.save()
                print("[simple] off")
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-resetall") {
            Task { @MainActor in
                for p in Platform.allCases { AccountStore.shared.removeAll(p) }
                Store.shared.clearAllData()
                print("[resetall] accounts=\(AccountStore.shared.accounts.count) parcels=\(Store.shared.parcels.count)")
                exit(0)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-acctest") {
            Task { @MainActor in
                let st = AccountStore.shared
                func acc(_ id: String, _ label: String, _ unb: String) -> Account {
                    Account(id: "taobao:\(id)", platform: .taobao, label: label,
                            cookies: [StoredCookie(name: "unb", value: unb, domain: ".taobao.com", path: "/", expires: nil),
                                      StoredCookie(name: "tracknick", value: label, domain: ".taobao.com", path: "/", expires: nil)])
                }
                st.upsert(acc("1001", "账号A", "1001"))
                st.upsert(acc("2002", "账号B", "2002"))
                print("[acctest] count=\(st.accounts(.taobao).count) active=\(st.active(.taobao)?.label ?? "-")")
                if let first = st.accounts(.taobao).first { st.switchTo(first.id, .taobao) }
                print("[acctest] after switch active=\(st.active(.taobao)?.label ?? "-") cookies=\(PlatformSession.shared.cookies(for: .taobao).count)")
                st.upsert(acc("1001", "账号A2", "1001"))
                print("[acctest] upsert same id count=\(st.accounts(.taobao).count) label=\(st.accounts(.taobao).first?.label ?? "-")")
                if let b = st.accounts(.taobao).last { st.remove(b.id, .taobao) }
                print("[acctest] after remove count=\(st.accounts(.taobao).count)")
                st.removeAll(.taobao)
                print("[acctest] after removeAll=\(st.accounts(.taobao).count)")
                exit(0)
            }
            return
        }
        guard ProcessInfo.processInfo.arguments.contains("-selftest") else {
            if ProcessInfo.processInfo.arguments.contains("-keytest") {
                let key = "selftest.persist"
                if let v = Keychain.get(key) {
                    print("[keytest] found \(v)")
                } else {
                    let v = "v\(Int(Date().timeIntervalSince1970))"
                    Keychain.set(v, for: key)
                    print("[keytest] written \(v)")
                }
                exit(0)
            }
            return
        }
        Task { @MainActor in
            let store = Store.shared
            print("[selftest] parcels=\(store.parcels.count) pending=\(store.pending.count) transit=\(store.transit.count)")

            let text = "【菜鸟驿站】您的包裹已到万科城店，取件码 6-5-9955，请及时领取。"
            let parsed = DeliveryParser.parse(text)
            print("[selftest] parse code=\(parsed.code ?? "-") station=\(parsed.station ?? "-") company=\(parsed.company ?? "-")")

            var p = Parcel()
            p.code = parsed.code ?? ""
            p.station = parsed.station ?? ""
            p.title = "自测包裹"
            p.arrivedAt = Date()
            store.add(p)
            print("[selftest] after add pending=\(store.pending.count)")

            store.markPicked(p.id)
            let s = store.stats
            print("[selftest] after pick pending=\(store.pending.count) picked=\(s.picked) total=\(s.total) trend=\(s.trend.map(\.count))")

            let removed = store.clearHistory()
            print("[selftest] clearHistory removed=\(removed)")
            store.delete(p.id)
            print("[selftest] done parcels=\(store.parcels.count)")
            exit(0)
        }
    }
}
#endif
