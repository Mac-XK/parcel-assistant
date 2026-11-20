import SwiftUI

struct ParcelCard: View {
    var parcel: Parcel
    var compact: Bool = false
    var onPick: (() -> Void)? = nil

    private var mainColor: Color {
        if parcel.isClosed { return Palette.red }
        if parcel.isPicked { return Palette.tertiary }
        if parcel.isTransit {
            return parcel.latestTrackText.contains("派送") ? Palette.orange : Palette.blue
        }
        return Palette.text
    }

    private var statusIcon: String {
        if parcel.isClosed { return "xmark.circle.fill" }
        if parcel.isPicked { return "checkmark.circle.fill" }
        if parcel.isTransit {
            return parcel.latestTrackText.contains("派送") ? "bicycle" : "shippingbox"
        }
        return "shippingbox.circle.fill"
    }

    private var statusColor: Color {
        if parcel.isClosed { return Palette.red }
        if parcel.isPicked { return Palette.tertiary }
        if parcel.isTransit {
            return parcel.latestTrackText.contains("派送") ? Palette.orange : Palette.blue
        }
        return Palette.green
    }

    private var timeText: String {
        if let picked = parcel.pickedAt { return "取件 \(Fmt.monthDay(picked))" }
        if parcel.isClosed { return "已关闭" }
        if parcel.isTransit {
            if let eta = parcel.eta { return "预计 \(Fmt.monthDay(eta))" }
            return parcel.track.first.map { "更新 \(Fmt.trackRelative($0.time))" } ?? "运输中"
        }
        if let arrived = parcel.arrivedAt { return Fmt.arrived(arrived) }
        return Fmt.relative(parcel.createdAt)
    }

    private var platform: Platform? {
        parcel.source.flatMap { Platform(rawValue: $0) }
    }

    var body: some View {
        HStack(spacing: compact ? 9 : 11) {
            CompanyLogo(code: parcel.companyCode, size: compact ? 36 : 44)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                HStack(spacing: 6) {
                    CodeText(text: parcel.mainText,
                             size: compact ? 17 : (parcel.isTransit ? 17 : 22),
                             color: mainColor)
                    if !parcel.extraCodes.isEmpty && !compact {
                        Text(parcel.extraCodes.joined(separator: " · "))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.tertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    if let platform { PlatformBadge(platform: platform, size: 13) }
                    Text(parcel.title.isEmpty ? parcel.companyName : parcel.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: compact ? 3 : 5) {
                if !parcel.placeText.isEmpty {
                    Text(parcel.placeText)
                        .font(.system(size: 12))
                        .foregroundStyle(parcel.isPicked ? Palette.tertiary : Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(parcel.placeText.contains("驿站") ? .tail : .head)
                        .frame(maxWidth: 118, alignment: .trailing)
                }
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                    Text(timeText)
                        .font(.system(size: 12))
                        .foregroundStyle(parcel.eta != nil ? Palette.secondary : statusColor)
                        .lineLimit(1)
                }
                if let onPick, parcel.isAwaiting {
                    Button {
                        onPick()
                    } label: {
                        Text("标记已取")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.accent(Store.shared.settings.accentName))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 9 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// 轨迹时间只有 "11-20 10:24"，补上今年的年份再算相对时间
extension Fmt {
    static func trackRelative(_ text: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        guard let base = f.date(from: text) else { return text }
        let cal = Calendar.current
        var comps = cal.dateComponents([.month, .day, .hour, .minute], from: base)
        comps.year = cal.component(.year, from: Date())
        guard var d = cal.date(from: comps) else { return text }
        if d > Date().addingTimeInterval(3600) { d = cal.date(byAdding: .year, value: -1, to: d) ?? d }
        return relative(d)
    }
}
