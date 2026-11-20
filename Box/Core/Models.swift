import Foundation

// MARK: - 包裹

enum ParcelStatus: String, Codable, Hashable {
    case awaiting   // 已到站，等取
    case transit    // 在路上
    case picked     // 已取
    case closed     // 退款 / 取消
}

struct TrackNode: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: String
    var text: String
}

struct Parcel: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 取件码；空串表示还没到站 / 没有码
    var code: String = ""
    /// 同一包裹在不同平台识别到的其它码
    var extraCodes: [String] = []
    var mailNo: String? = nil
    var companyCode: Int = 0
    /// 驿站 / 自提点 / 柜机名
    var station: String = ""
    var address: String = ""
    /// 商品或平台标题
    var title: String = ""
    var phone: String = ""
    var notes: String = ""
    var status: ParcelStatus = .awaiting
    /// 来源平台 rawValue；nil 表示手动添加
    var source: String? = nil
    /// 来源 App 名（截图/短信识别时带上）
    var sourceApp: String? = nil
    var createdAt: Date = Date()
    var arrivedAt: Date? = nil
    var pickedAt: Date? = nil
    var eta: Date? = nil
    /// 退款/关闭文案，有值即终态
    var closed: String? = nil
    var track: [TrackNode] = []
    var receiver: String? = nil
    /// 平台订单号（京东 orderId / 拼多多 orderSn），用来去重
    var orderId: String? = nil
    /// 这条包裹来自哪个平台账号（多账号时用来区分）
    var accountId: String? = nil
    var accountLabel: String? = nil
    /// 丰巢在柜信息：有它才能一键开柜
    var fcBox: FcBoxMeta? = nil

    var companyName: String { Courier.name(companyCode) }
    var companyAsset: String? { Courier.asset(companyCode) }

    /// 真待取：到站了、有码、没取、没关单
    var isAwaiting: Bool {
        closed == nil && pickedAt == nil && (status == .awaiting) && (!code.isEmpty || arrivedAt != nil)
    }

    var isTransit: Bool { closed == nil && pickedAt == nil && status == .transit }
    var isPicked: Bool { pickedAt != nil || status == .picked }
    var isClosed: Bool { closed != nil }

    /// 卡片主行文案
    var mainText: String {
        if let closed { return closed }
        if !code.isEmpty { return code }
        if isTransit { return latestTrackText }
        return isPicked ? "已取件" : "暂无取件码"
    }

    var latestTrackText: String {
        track.first?.text ?? notes
    }

    var placeText: String {
        if !station.isEmpty { return station }
        return address
    }
}

// MARK: - 驿站

struct CourierStation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var address: String
    var phone: String = ""
    var hours: String = "08:00-22:00"
    var note: String = ""
    var keywords: [String] = []
}

// MARK: - 身份码

enum IdentityKind: String, Codable, CaseIterable, Identifiable {
    case taobao, cainiao
    var id: String { rawValue }
    var title: String {
        switch self {
        case .taobao: return "淘宝"
        case .cainiao: return "菜鸟"
        }
    }
    var asset: String {
        switch self {
        case .taobao: return "taobao"
        case .cainiao: return "cainiao"
        }
    }
    var tint: String {
        switch self {
        case .taobao: return "#F08A2E"
        case .cainiao: return "#34A853"
        }
    }
}

struct IdentityCode: Identifiable, Codable, Hashable {
    var id: IdentityKind
    var code: String
    var expiresAt: Date
    var detail: String = ""
}

// MARK: - 设置

struct Settings: Codable, Hashable {
    var reminderEnabled: Bool = true
    var reminderHour: Int = 20
    var quietStart: Int = 22
    var quietEnd: Int = 8
    var notifyOnArrive: Bool = true
    var appearance: String = "system"     // system / light / dark
    var accentName: String = "星辉紫"
    var refreshAppMin: Int = 20
    var nickName: String = ""
    var simpleMode: Bool = false
    var showTransitInWidget: Bool = true
}

// MARK: - 统计

struct CompanyCount: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var count: Int
}

struct TrendDay: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var count: Int
}

struct StatsBundle {
    var pending: Int = 0
    var pickupToday: Int = 0
    var thisWeek: Int = 0
    var thisMonth: Int = 0
    var pickedThisMonth: Int = 0
    var total: Int = 0
    var picked: Int = 0
    var byCompany: [CompanyCount] = []
    var trend: [TrendDay] = []
    var peakHour: Int = -1
    var avgPerMonth: Double = 0
    var topStation: String = ""
}
