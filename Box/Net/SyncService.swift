import Foundation

/// 平台数据拉取：目前接了菜鸟（用淘宝登录态走 MTOP），其余平台登录后可在此扩展
@MainActor
final class SyncService {
    static let shared = SyncService()

    private let listAPI = "mtop.cainiao.lpc.packageservice.queryPdsPackageDataList"

    func syncAll(store: Store) async -> String {
        let session = PlatformSession.shared
        let usable = Platform.allCases.filter { session.isAuthorized($0) }
        guard !usable.isEmpty else {
            return "还没有授权平台，去「设置 → 平台授权」登录一次"
        }
        store.lastSync = Date()
        store.save()

        var parts: [String] = []

        if session.isAuthorized(.taobao) || session.isAuthorized(.cainiao) {
            do {
                let packages = try await fetchCainiao()
                let added = mergeCainiao(packages, into: store)
                parts.append(added == 0 ? "菜鸟已是最新" : "菜鸟 +\(added)")
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                parts.append("菜鸟失败：\(msg)")
            }
        }
        if session.isAuthorized(.fengchao) {
            let r = await syncFengchao(store: store)
            parts.append(r)
        }
        if session.isAuthorized(.mi) {
            let r = await syncXiaomi(store: store)
            parts.append(r)
        }
        if session.isAuthorized(.jd) { parts.append("京东：到授权页点「同步」") }
        if session.isAuthorized(.pdd) { parts.append("拼多多：到授权页点「同步」") }
        return parts.isEmpty ? "没有可同步的平台" : parts.joined(separator: " · ")
    }

    // MARK: 丰巢

    func syncFengchao(store: Store) async -> String {
        do {
            let list = try await FengchaoService.shared.waitPick()
            var added = 0
            for pick in list {
                if let i = store.parcels.firstIndex(where: {
                    (!pick.expressId.isEmpty && $0.mailNo == pick.expressId) || (!pick.code.isEmpty && $0.code == pick.code)
                }) {
                    store.parcels[i].code = pick.code
                    store.parcels[i].station = pick.cabinetCode.isEmpty ? store.parcels[i].station : pick.cabinetCode
                    store.parcels[i].fcBox = FcBoxMeta(pick)
                    store.parcels[i].status = .awaiting
                    if store.parcels[i].arrivedAt == nil { store.parcels[i].arrivedAt = Date() }
                    continue
                }
                var p = Parcel()
                p.accountId = AccountStore.shared.active(.fengchao)?.id
                p.accountLabel = AccountStore.shared.active(.fengchao)?.label
                p.mailNo = pick.expressId.isEmpty ? nil : pick.expressId
                p.code = pick.code
                p.companyCode = Courier.code(fromName: pick.companyName.isEmpty ? "丰巢" : pick.companyName)
                p.station = pick.cabinetCode.isEmpty ? "丰巢快递柜" : pick.cabinetCode
                p.address = pick.address
                p.title = pick.companyName.isEmpty ? "丰巢在柜" : pick.companyName
                p.status = .awaiting
                p.source = Platform.fengchao.rawValue
                p.arrivedAt = Date()
                p.fcBox = FcBoxMeta(pick)
                if !pick.sendTm.isEmpty {
                    p.track = [TrackNode(time: pick.sendTm, text: "存放至丰巢柜 \(pick.cabinetCode) \(pick.location)")]
                }
                store.parcels.insert(p, at: 0)
                added += 1
            }
            store.lastSync = Date()
            store.save()
            return added == 0 ? "丰巢 \(list.count) 件在柜" : "丰巢 +\(added)"
        } catch {
            return "丰巢失败：\((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }

    // MARK: 小米

    func syncXiaomi(store: Store) async -> String {
        do {
            let list = try await XiaomiService.shared.fetchList()
            var added = 0
            for item in list {
                guard !item.mailNo.isEmpty else { continue }
                if let i = store.parcels.firstIndex(where: { $0.mailNo == item.mailNo }) {
                    if !item.pickupCode.isEmpty { store.parcels[i].code = item.pickupCode }
                    continue
                }
                var p = Parcel()
                p.accountId = AccountStore.shared.active(.mi)?.id
                p.accountLabel = AccountStore.shared.active(.mi)?.label
                p.mailNo = item.mailNo
                p.code = item.pickupCode
                p.companyCode = Courier.code(fromName: item.cpName)
                p.station = item.stationName
                p.address = item.address
                p.title = item.productName.isEmpty ? item.cpName : item.productName
                p.status = item.pickupCode.isEmpty ? .transit : .awaiting
                p.source = Platform.mi.rawValue
                if !item.pickupCode.isEmpty { p.arrivedAt = Date() }
                if !item.stateDesc.isEmpty {
                    p.track = [TrackNode(time: item.logisticsUpdateTime, text: item.stateDesc)]
                }
                store.parcels.insert(p, at: 0)
                added += 1
            }
            store.lastSync = Date()
            store.save()
            return added == 0 ? "小米 \(list.count) 条" : "小米 +\(added)"
        } catch {
            return "小米失败：\((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
    }

    /// 菜鸟包裹清单
    private func fetchCainiao() async throws -> [[String: Any]] {
        let json = try await MTop.call(listAPI, data: [
            "pageSize": 50,
            "currentPage": 1,
            "needTemporality": false,
            "needDynInfo": true,
        ])
        guard let payload = MTop.payload(json) as? [String: Any],
              let list = payload["packages"] as? [[String: Any]] else { return [] }
        return list
    }

    private func mergeCainiao(_ packages: [[String: Any]], into store: Store) -> Int {
        var added = 0
        for item in packages {
            let mailNo = str(item["mailNo"]) ?? str(item["mail_no"]) ?? ""
            let code = str(item["pickupCode"]) ?? str(item["pickup_code"]) ?? ""
            let status = str(item["status"]) ?? str(item["statusDesc"]) ?? ""
            guard !mailNo.isEmpty || !code.isEmpty else { continue }

            let station = (item["packageStation"] as? [String: Any]).flatMap {
                str($0["pointName"]) ?? str($0["stationName"]) ?? str($0["name"])
            } ?? ""
            let company = str(item["cpName"]) ?? str(item["companyName"]) ?? ""
            let title = str(item["title"]) ?? str(item["tradeOrderTitle"]) ?? ""

            if let i = store.parcels.firstIndex(where: { !mailNo.isEmpty && $0.mailNo == mailNo }) {
                // 已有包裹：只补取件码与驿站，不动已取状态
                if !code.isEmpty { store.parcels[i].code = code }
                if !station.isEmpty { store.parcels[i].station = station }
                store.parcels[i].status = code.isEmpty ? .transit : .awaiting
                continue
            }

            var p = Parcel()
            p.accountId = AccountStore.shared.effective(.cainiao)?.id
            p.accountLabel = AccountStore.shared.effective(.cainiao)?.label
            p.mailNo = mailNo.isEmpty ? nil : mailNo
            p.code = code
            p.companyCode = Courier.code(fromName: company)
            p.station = station
            p.title = title.isEmpty ? company : title
            p.status = code.isEmpty ? .transit : .awaiting
            p.source = Platform.cainiao.rawValue
            p.createdAt = Date()
            if !code.isEmpty { p.arrivedAt = Date() }
            if !status.isEmpty {
                p.track = [TrackNode(time: Fmt.mmddhm(), text: status)]
            }
            store.parcels.insert(p, at: 0)
            added += 1
        }
        store.lastSync = Date()
        store.save()
        return added
    }

    private func str(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
}

extension Fmt {
    static func mmddhm() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }
}
