import Foundation

enum Fmt {
    private static let cal = Calendar(identifier: .gregorian)

    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func monthDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f.string(from: d)
    }

    static func monthDayTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }

    static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    /// 列表右侧的时间：今天只给时分，更早给月日
    static func compact(_ d: Date) -> String {
        if cal.isDateInToday(d) { return hm(d) }
        if cal.isDateInYesterday(d) { return "昨天" }
        if cal.isDate(d, equalTo: Date(), toGranularity: .year) { return monthDay(d) }
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: d)
    }

    static func relative(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86_400 { return "\(Int(s / 3600)) 小时前" }
        if cal.isDateInYesterday(d) { return "昨天" }
        if s < 7 * 86_400 { return "\(Int(s / 86_400)) 天前" }
        return monthDay(d)
    }

    /// 「已到站 3 小时」
    static func arrived(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 3600 { return "刚送到" }
        let h = Int(s / 3600)
        if h > 99 { return "已到站 \(h / 24) 天" }
        return "已到站 \(h) 小时"
    }

    static func countdown(_ d: Date) -> String {
        let s = d.timeIntervalSinceNow
        if s <= 0 { return "已过期" }
        let m = Int(s / 60)
        if m < 60 { return "剩 \(max(1, m)) 分钟" }
        return "剩 \(m / 60) 小时"
    }
}

extension Date {
    static func daysAgo(_ d: Int, hour: Int = 10, minute: Int = 30) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -d, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    static func hoursAgo(_ h: Double) -> Date { Date().addingTimeInterval(-h * 3600) }
}
