import Foundation
import Combine
import SwiftUI

// MARK: - 唯一数据源

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var parcels: [Parcel] = []
    @Published var stations: [CourierStation] = []
    @Published var settings: Settings = Settings()
    @Published var lastSync: Date? = nil
    @Published var toast: String? = nil

    private var saveTask: Task<Void, Never>? = nil
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Box", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        _ = load()
        cleanupCainiaoJunkOnce()
    }

    /// 一次性清理：旧版菜鸟同步把「无码、无驿站、未取、无到达时间」的历史订单也灌了进来
    /// （表现为「累计快件 50、待取 0」）。这些行没有任何可用信息，删掉不影响真实包裹。
    private func cleanupCainiaoJunkOnce() {
        let key = "migrate.cleanCainiaoJunk.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let before = parcels.count
        parcels.removeAll { p in
            p.source == Platform.cainiao.rawValue
                && p.code.isEmpty && p.station.isEmpty
                && p.pickedAt == nil && p.arrivedAt == nil
                && p.status == .transit
        }
        if parcels.count != before {
            lastSync = nil
            save()
        }
    }

    // MARK: 持久化

    /// 3 = 彻底去掉演示数据后的版本号：任何旧版本数据都会清空一次
    private static let schemaVersion = 3

    private struct Snapshot: Codable {
        var schema: Int?
        var parcels: [Parcel]
        var stations: [CourierStation]
        var settings: Settings
        var lastSync: Date?
    }

    @discardableResult
    private func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        settings = snap.settings
        if (snap.schema ?? 1) < Self.schemaVersion {
            // 旧版首启动会写 15 条演示包裹：升级时一次性清空，只保留设置
            parcels = []
            stations = []
            lastSync = nil
            save()
            return true
        }
        parcels = snap.parcels
        stations = snap.stations
        lastSync = snap.lastSync
        return true
    }

    func save() {
        saveTask?.cancel()
        let snap = Snapshot(schema: Self.schemaVersion, parcels: parcels, stations: stations,
                            settings: settings, lastSync: lastSync)
        saveTask = Task { [fileURL] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: 增删改

    func add(_ p: Parcel) {
        parcels.insert(p, at: 0)
        lastSync = Date()
        save()
        Notifier.shared.refresh(parcels: parcels, settings: settings)
    }

    func update(_ p: Parcel) {
        guard let i = parcels.firstIndex(where: { $0.id == p.id }) else { return }
        parcels[i] = p
        save()
    }

    func markPicked(_ id: UUID) {
        guard let i = parcels.firstIndex(where: { $0.id == id }) else { return }
        guard parcels[i].pickedAt == nil else { return }
        parcels[i].pickedAt = Date()
        parcels[i].status = .picked
        parcels[i].track.insert(TrackNode(time: Fmt.ymd(Date()), text: "你已取件"), at: 0)
        save()
        Notifier.shared.refresh(parcels: parcels, settings: settings)
        Haptic.success()
    }

    func delete(_ id: UUID) {
        parcels.removeAll { $0.id == id }
        save()
        Notifier.shared.refresh(parcels: parcels, settings: settings)
    }

    func delete(ids: Set<UUID>) {
        parcels.removeAll { ids.contains($0.id) }
        save()
    }

    /// 「清除缓存」：删掉已取超过 30 天的历史，其余不动
    func clearHistory(olderThan days: Int = 30) -> Int {
        let cut = Date().addingTimeInterval(-Double(days) * 86_400)
        let before = parcels.count
        parcels.removeAll { p in
            let t = p.pickedAt ?? p.createdAt
            return p.isPicked && t < cut
        }
        save()
        return before - parcels.count
    }

    // MARK: 查询

    var pending: [Parcel] {
        parcels.filter { $0.isAwaiting }
            .sorted { ($0.arrivedAt ?? $0.createdAt) > ($1.arrivedAt ?? $1.createdAt) }
    }

    var transit: [Parcel] {
        parcels.filter { $0.isTransit }
            .sorted { ($0.track.first?.time ?? "") > ($1.track.first?.time ?? "") }
    }

    var pickedRecent: [Parcel] {
        parcels.filter { $0.isPicked }
            .sorted { ($0.pickedAt ?? $0.createdAt) > ($1.pickedAt ?? $1.createdAt) }
    }

    /// 驿站分组：命中驿站管理里的名字，否则「其他驿站」
    func stationName(for p: Parcel) -> String {
        let hay = "\(p.station) \(p.address) \(p.title)"
        if let hit = stations.first(where: { st in
            hay.contains(st.name) || st.keywords.contains(where: { hay.contains($0) })
        }) { return hit.name }
        return p.station.isEmpty ? "其他驿站" : p.station
    }

    func groupByStation() -> [(name: String, parcels: [Parcel])] {
        var order: [String] = []
        var map: [String: [Parcel]] = [:]
        for p in pending {
            let key = stationName(for: p)
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(p)
        }
        return order
            .sorted { a, b in
                if a == "其他驿站" { return false }
                if b == "其他驿站" { return true }
                return (map[a]?.count ?? 0) > (map[b]?.count ?? 0)
            }
            .map { ($0, map[$0] ?? []) }
    }

    // MARK: 统计

    var stats: StatsBundle {
        var s = StatsBundle()
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let dayStart = cal.startOfDay(for: now)

        s.pending = pending.count
        s.total = parcels.count
        s.picked = parcels.filter { $0.isPicked }.count
        s.pickupToday = parcels.filter { ($0.pickedAt ?? $0.createdAt) >= dayStart }.count
        s.thisWeek = parcels.filter { $0.createdAt >= weekStart }.count
        s.thisMonth = parcels.filter { $0.createdAt >= monthStart }.count
        s.pickedThisMonth = parcels.filter { ($0.pickedAt ?? .distantPast) >= monthStart }.count

        var counts: [String: Int] = [:]
        for p in parcels { counts[p.companyName, default: 0] += 1 }
        s.byCompany = counts.map { CompanyCount(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        var hours = [Int](repeating: 0, count: 24)
        for p in parcels { hours[cal.component(.hour, from: p.createdAt)] += 1 }
        if let peak = hours.max(), peak > 0, let idx = hours.firstIndex(of: peak) { s.peakHour = idx }

        var days: [TrendDay] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: dayStart) ?? dayStart
            let next = cal.date(byAdding: .day, value: 1, to: d) ?? d
            let n = parcels.filter { $0.createdAt >= d && $0.createdAt < next }.count
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M/d"
            days.append(TrendDay(label: f.string(from: d), count: n))
        }
        s.trend = days

        var stationCount: [String: Int] = [:]
        for p in parcels { stationCount[stationName(for: p), default: 0] += 1 }
        s.topStation = stationCount.max { $0.value < $1.value }?.key ?? ""

        let months = Set(parcels.map { cal.dateComponents([.year, .month], from: $0.createdAt) }
            .map { "\($0.year ?? 0)-\($0.month ?? 0)" }).count
        s.avgPerMonth = months > 0 ? Double(parcels.count) / Double(max(months, 1)) : 0
        return s
    }

    /// 清空所有包裹 / 驿站 / 身份码（保留设置）
    func clearAllData() {
        parcels = []
        stations = []
        lastSync = nil
        save()
        toast = "已清空包裹数据"
    }
}
