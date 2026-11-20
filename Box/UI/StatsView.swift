import SwiftUI

struct StatsView: View {
    @ObservedObject var store = Store.shared
    private var accent: Color { Palette.accent(store.settings.accentName) }

    private var s: StatsBundle { store.stats }

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        quickRow
                        trendCard
                        companyCard
                        detailCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 116)
                }
            }
            .navigationTitle("统计")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(s.total)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("累计快件").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.picked)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                    Text("累计已取").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
            }

            HStack(spacing: 0) {
                metric("当前待取", "\(s.pending)")
                Rectangle().fill(Palette.separator).frame(width: 0.6, height: 28)
                metric("平均每月", String(format: "%.1f", s.avgPerMonth))
                Rectangle().fill(Palette.separator).frame(width: 0.6, height: 28)
                metric("今日入库", "\(s.pickupToday)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(colors: [accent.opacity(0.18), Palette.card],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 0.8)
        )
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickRow: some View {
        HStack(spacing: 10) {
            mini("本月取件", "\(s.pickedThisMonth)", "calendar")
            mini("本周入库", "\(s.thisWeek)", "calendar")
            mini("最高频时段", s.peakHour >= 0 ? String(format: "%02d:00", s.peakHour) : "—", "clock")
        }
    }

    private func mini(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.text)
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle(radius: 16)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("近 7 天").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text("入库 \(s.trend.reduce(0) { $0 + $1.count }) 件")
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }

            let maxV = max(s.trend.map(\.count).max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(s.trend) { day in
                    VStack(spacing: 6) {
                        Text(day.count > 0 ? "\(day.count)" : "")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.secondary)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient(colors: [accent, accent.opacity(0.45)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(height: max(6, CGFloat(day.count) / CGFloat(maxV) * 70))
                        Text(day.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)
        }
        .padding(14)
        .cardStyle()
    }

    private var companyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快递公司").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            if s.byCompany.isEmpty {
                Text("还没有数据").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
            } else {
                let top = Array(s.byCompany.prefix(5))
                let maxC = max(top.first?.count ?? 1, 1)
                ForEach(top) { row in
                    let code = Courier.code(fromName: row.name)
                    HStack(spacing: 9) {
                        CompanyLogo(code: code, size: 24)
                        Text(row.name).font(.system(size: 13)).foregroundStyle(Palette.text)
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.field).frame(height: 7)
                                Capsule().fill(accent.opacity(0.85))
                                    .frame(width: max(8, geo.size.width * CGFloat(row.count) / CGFloat(maxC)), height: 7)
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 14)
                        Text("\(row.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 22, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .cardStyle()
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            infoRow("最常取件驿站", s.topStation.isEmpty ? "—" : s.topStation, "mappin.and.ellipse")
            DividerLine()
            infoRow("最高频时段", s.peakHour >= 0 ? String(format: "%02d:00 前后", s.peakHour) : "—", "clock")
            DividerLine()
            infoRow("当前在途", "\(store.transit.count) 件", "shippingbox")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .cardStyle()
    }

    private func infoRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.tertiary)
                .frame(width: 20)
            Text(title).font(.system(size: 14)).foregroundStyle(Palette.text)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .padding(.vertical, 11)
    }
}
