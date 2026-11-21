import Foundation

/// 平台数据拉取：目前接了菜鸟（用淘宝登录态走 MTOP）、丰巢、小米
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

        var parts: [String] = []
        var touched = false

        if session.isAuthorized(.taobao) || session.isAuthorized(.cainiao) {
            do {
                let fetched = try await fetchCainiao()
                parts.append(mergeCainiao(fetched.list, shape: fetched.shape, into: store))
                touched = true
            } catch {
                // 被系统取消（下拉刷新被打断 / 切页）不是失败，别弹红字
                if ErrText.isCancelled(error) { return "" }
                parts.append("菜鸟：\(ErrText.short(error))")
            }
        }
        if session.isAuthorized(.fengchao) {
            parts.append(await syncFengchao(store: store))
        }
        if session.isAuthorized(.mi) {
            parts.append(await syncXiaomi(store: store))
        }
        if session.isAuthorized(.jd) { parts.append("京东：到授权页点「同步」") }
        if session.isAuthorized(.pdd) { parts.append("拼多多：到授权页点「同步」") }

        if touched {
            store.lastSync = Date()
            store.save()
        }
        return parts.isEmpty ? "没有可同步的平台" : parts.joined(separator: " · ")
    }

    // MARK: - 菜鸟

    private struct CainiaoFetch {
        var list: [[String: Any]]
        /// 首条记录的键名（只拿键名做诊断，绝不含值）
        var shape: String
    }

    private func fetchCainiao() async throws -> CainiaoFetch {
        let json = try await MTop.call(listAPI, data: [
            "pageSize": 50,
            "currentPage": 1,
            "needTemporality": false,
            "needDynInfo": true,
        ])
        let payload = MTop.payload(json) ?? json
        guard let list = Self.findPackageList(in: payload, depth: 0) else {
            throw CainiaoError.noList(Self.keyPreview(payload))
        }
        let shape = list.first.map { preview($0) } ?? "空"
        return CainiaoFetch(list: list, shape: shape)
    }

    private enum CainiaoError: LocalizedError {
        case noList(String)
        var errorDescription: String? {
            if case .noList(let keys) = self {
                return "返回里没找到包裹列表（顶层键：\(keys)）"
            }
            return nil
        }
    }

    /// 响应结构每版都可能换壳：按常见键名逐层找，最后退化成「最大的字典数组」
    private static func findPackageList(in node: Any?, depth: Int) -> [[String: Any]]? {
        guard depth <= 5, let node else { return nil }
        if let dict = node as? [String: Any] {
            let preferred = ["packages", "packageList", "packageInfoList", "packageDataList",
                             "list", "datas", "data", "items", "result", "results"]
            for key in preferred {
                if let arr = dict[key] as? [[String: Any]], !arr.isEmpty { return arr }
                if let inner = dict[key], let found = findPackageList(in: inner, depth: depth + 1) {
                    return found
                }
            }
            var best: [[String: Any]]?
            for (_, v) in dict {
                if let arr = v as? [[String: Any]], arr.count > (best?.count ?? 0) {
                    best = arr
                } else if let found = findPackageList(in: v, depth: depth + 1),
                          found.count > (best?.count ?? 0) {
                    best = found
                }
            }
            return best
        }
        if let arr = node as? [Any] {
            for v in arr {
                if let found = findPackageList(in: v, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    // MARK: 字段别名（不同版本/不同端字段名不一样，按顺序取第一个非空）

    private static let mailKeys = ["mailNo", "mail_no", "waybillCode", "waybill_code",
                                   "billCode", "bill_code", "expressNo", "express_no",
                                   "mailNumber", "trackingNumber", "nu"]
    private static let codeKeys = ["pickupCode", "pickup_code", "takeCode", "take_code",
                                   "pickCode", "pick_code", "receiveCode", "receive_code",
                                   "pickupNum", "pickup_num", "stationCode", "station_code",
                                   "codeText", "code_text", "code"]
    private static let stationDictKeys = ["packageStation", "package_station", "station",
                                          "pickupPoint", "pickup_point", "stationInfo"]
    private static let stationKeys = ["pointName", "point_name", "stationName", "station_name",
                                      "pickupPointName", "packageStationName", "name"]
    private static let companyKeys = ["cpName", "cp_name", "companyName", "company_name",
                                      "expressCompanyName", "logisticsName"]
    private static let titleKeys = ["title", "tradeOrderTitle", "trade_order_title", "goodsTitle",
                                    "itemTitle", "productName", "tradeTitle", "desc"]
    private static let statusKeys = ["statusDesc", "status_desc", "statusText", "status_name",
                                     "stateDesc", "state_desc", "status"]
    private static let timeKeys = ["arriveTime", "arrivedTime", "arrive_time", "arrived_time",
                                   "gmtModified", "modifyTime", "updateTime", "createTime",
                                   "mailTime", "sendTime", "takeTime"]

    /// 菜鸟同步：只把「有取件码」的件收进来，在途/历史订单不再灌进列表
    private func mergeCainiao(_ packages: [[String: Any]], shape: String, into store: Store) -> String {
        var added = 0, refreshed = 0, awaiting = 0, ignored = 0, matchedMail = 0

        // 清掉以前字段没解析到、灌进来的空壳记录（无码、无驿站、未取、无到达时间）
        let junkIDs = Set(store.parcels.filter { p in
            p.source == Platform.cainiao.rawValue
                && p.code.isEmpty && p.station.isEmpty
                && p.pickedAt == nil && p.arrivedAt == nil
        }.map(\.id))
        if !junkIDs.isEmpty {
            store.parcels.removeAll { junkIDs.contains($0.id) }
        }

        let account = AccountStore.shared.effective(.cainiao)

        for item in packages {
            let mailNo = Self.firstString(item, Self.mailKeys)
            let code = Self.firstString(item, Self.codeKeys)
            if !mailNo.isEmpty { matchedMail += 1 }

            let station = Self.station(item)
            let company = Self.firstString(item, Self.companyKeys)
            let title = Self.firstString(item, Self.titleKeys)
            let status = Self.firstString(item, Self.statusKeys)
            let when = Self.firstDate(item, Self.timeKeys)

            guard !code.isEmpty else {
                // 没有取件码：只补已有记录的驿站/轨迹，绝不新建
                if !mailNo.isEmpty,
                   let i = store.parcels.firstIndex(where: { $0.mailNo == mailNo }) {
                    if !station.isEmpty { store.parcels[i].station = station }
                    if !status.isEmpty {
                        store.parcels[i].track = [TrackNode(time: Fmt.mmddhm(when ?? Date()), text: status)]
                    }
                    refreshed += 1
                } else {
                    ignored += 1
                }
                continue
            }

            awaiting += 1

            if let i = store.parcels.firstIndex(where: {
                (!$0.code.isEmpty && $0.code == code) || (!mailNo.isEmpty && $0.mailNo == mailNo)
            }) {
                store.parcels[i].code = code
                if !station.isEmpty { store.parcels[i].station = station }
                if !company.isEmpty { store.parcels[i].companyCode = Courier.code(fromName: company) }
                if store.parcels[i].title.isEmpty || store.parcels[i].source == Platform.cainiao.rawValue {
                    if !title.isEmpty { store.parcels[i].title = title }
                }
                if store.parcels[i].pickedAt == nil {
                    store.parcels[i].status = .awaiting
                    if store.parcels[i].arrivedAt == nil { store.parcels[i].arrivedAt = when ?? Date() }
                }
                refreshed += 1
                continue
            }

            var p = Parcel()
            p.accountId = account?.id
            p.accountLabel = account?.label
            p.mailNo = mailNo.isEmpty ? nil : mailNo
            p.code = code
            p.companyCode = Courier.code(fromName: company)
            p.station = station
            p.title = title.isEmpty ? (company.isEmpty ? "菜鸟包裹" : company) : title
            p.status = .awaiting
            p.source = Platform.cainiao.rawValue
            p.createdAt = when ?? Date()
            p.arrivedAt = when ?? Date()
            if !status.isEmpty {
                p.track = [TrackNode(time: Fmt.mmddhm(when ?? Date()), text: status)]
            }
            store.parcels.insert(p, at: 0)
            added += 1
        }

        // 一条都没认出字段：把键名回传，方便定位是不是接口改版了
        if !packages.isEmpty && awaiting == 0 && matchedMail == 0 {
            return "菜鸟 \(packages.count) 条未识别（字段：\(shape)）"
        }

        var bits: [String] = []
        if awaiting > 0 { bits.append("菜鸟待取 \(awaiting)") }
        if added > 0 { bits.append("新增 \(added)") }
        if refreshed > 0 { bits.append("更新 \(refreshed)") }
        if ignored > 0 { bits.append("在途/历史 \(ignored) 条未入库") }
        if bits.isEmpty { bits.append("菜鸟没有待取包裹") }
        return bits.joined(separator: " · ")
    }

    // MARK: 取值工具

    static func firstString(_ item: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let s = item[key] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, t != "null", t != "0" { return t }
            }
            if let n = item[key] as? NSNumber { return n.stringValue }
        }
        return ""
    }

    static func station(_ item: [String: Any]) -> String {
        for key in stationDictKeys {
            if let d = item[key] as? [String: Any] {
                let hit = firstString(d, stationKeys)
                if !hit.isEmpty { return hit }
            }
        }
        return firstString(item, stationKeys)
    }

    static func firstDate(_ item: [String: Any], _ keys: [String]) -> Date? {
        for key in keys {
            if let v = item[key] {
                if let n = v as? NSNumber { return dateFrom(number: n.doubleValue) }
                if let s = v as? String, let d = dateFrom(string: s) { return d }
            }
        }
        return nil
    }

    private static func dateFrom(number v: Double) -> Date? {
        guard v > 0 else { return nil }
        let seconds = v > 10_000_000_000 ? v / 1000 : v   // 13 位是毫秒
        let d = Date(timeIntervalSince1970: seconds)
        // 明显不在合理范围就丢弃（防止把 0 / 版本号当时间）
        guard d > Date(timeIntervalSince1970: 1_400_000_000), d < Date().addingTimeInterval(86_400) else {
            return nil
        }
        return d
    }

    private static func dateFrom(string s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let v = Double(t) { return dateFrom(number: v) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
                    "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "yyyy/MM/dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    private func preview(_ item: [String: Any]) -> String {
        item.keys.sorted().prefix(8).joined(separator: ",")
    }

    private static func keyPreview(_ node: Any?) -> String {
        if let d = node as? [String: Any] {
            let keys = d.keys.sorted().prefix(10).joined(separator: ",")
            return keys.isEmpty ? "空" : keys
        }
        return "非字典"
    }

    // MARK: - 丰巢

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
            if ErrText.isCancelled(error) { return "" }
            return "丰巢：\(ErrText.short(error))"
        }
    }

    // MARK: - 小米

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
            if ErrText.isCancelled(error) { return "" }
            return "小米：\(ErrText.short(error))"
        }
    }
}

extension Fmt {
    static func mmddhm() -> String { mmddhm(Date()) }

    static func mmddhm(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
