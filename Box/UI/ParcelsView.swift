import SwiftUI

struct ParcelsView: View {
    @ObservedObject var store = Store.shared
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var accountFilter: String? = nil
    @State private var detail: Parcel? = nil

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部", awaiting = "待取", transit = "在途", picked = "已取"
        var id: String { rawValue }
    }

    private var accent: Color { Palette.accent(store.settings.accentName) }

    private var accountOptions: [(id: String, label: String)] {
        var seen: [String: String] = [:]
        for p in store.parcels {
            if let id = p.accountId, seen[id] == nil { seen[id] = p.accountLabel ?? "账号" }
        }
        return seen.map { (id: $0.key, label: $0.value) }.sorted { $0.label < $1.label }
    }

    private var filtered: [Parcel] {
        var list = store.parcels
        if let af = accountFilter { list = list.filter { $0.accountId == af } }
        switch filter {
        case .all: break
        case .awaiting: list = list.filter { $0.isAwaiting }
        case .transit: list = list.filter { $0.isTransit }
        case .picked: list = list.filter { $0.isPicked }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { p in
                [p.title, p.code, p.mailNo ?? "", p.station, p.companyName, p.notes]
                    .contains { $0.localizedCaseInsensitiveContains(q) }
            }
        }
        return list.sorted { ($0.createdAt) > ($1.createdAt) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        searchField
                        filterRow
                        if accountOptions.count > 1 { accountRow }

                        if filtered.isEmpty {
                            EmptyBox(icon: "magnifyingglass", title: "没有匹配的包裹", subtitle: "换个关键词，或到「取件」里添加")
                                .cardStyle()
                                .padding(.top, 30)
                        } else {
                            ForEach(filtered) { p in
                                ParcelCard(parcel: p, onPick: {
                                    withAnimation { store.markPicked(p.id) }
                                    store.toast = "已标记「\(p.title)」已取"
                                })
                                .onTapGesture { detail = p }
                                .swipeActionsIfAvailable {
                                    store.delete(p.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 116)
                }
            }
            .navigationTitle("包裹")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(filtered.count) 件")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .sheet(item: $detail) { p in
                ParcelDetailView(parcelID: p.id)
            }
        }
    }

    private var accountRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Haptic.tap()
                    withAnimation(.easeInOut) { accountFilter = nil }
                } label: {
                    Text("全部账号")
                        .font(.system(size: 12, weight: accountFilter == nil ? .semibold : .regular))
                        .foregroundStyle(accountFilter == nil ? accent : Palette.secondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(accountFilter == nil ? accent.opacity(0.14) : Palette.card))
                }
                .buttonStyle(.plain)

                ForEach(accountOptions, id: \.id) { acc in
                    Button {
                        Haptic.tap()
                        withAnimation(.easeInOut) { accountFilter = acc.id }
                    } label: {
                        Text(acc.label)
                            .font(.system(size: 12, weight: accountFilter == acc.id ? .semibold : .regular))
                            .foregroundStyle(accountFilter == acc.id ? accent : Palette.secondary)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().fill(accountFilter == acc.id ? accent.opacity(0.14) : Palette.card))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.tertiary)
            TextField("取件码 / 运单号 / 驿站 / 商品", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.field))
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { f in
                Button {
                    Haptic.tap()
                    withAnimation(.easeInOut) { filter = f }
                } label: {
                    Text(f.rawValue)
                        .font(.system(size: 13, weight: filter == f ? .semibold : .regular))
                        .foregroundStyle(filter == f ? .white : Palette.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(filter == f ? accent : Palette.card)
                        )
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
        }
    }
}

// 允许卡片在 ScrollView 里也带一点点滑动手感（用按钮代替 swipe，避免复杂的 List 样式）
private extension View {
    func swipeActionsIfAvailable(_ delete: @escaping () -> Void) -> some View {
        self.contextMenu {
            Button("删除", systemImage: "trash", role: .destructive) { delete() }
        }
    }
}
