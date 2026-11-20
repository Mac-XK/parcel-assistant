import SwiftUI

struct ParcelDetailView: View {
    let parcelID: UUID
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var opening = false
    @State private var askOpen = false

    private var parcel: Parcel? { store.parcels.first { $0.id == parcelID } }
    private var accent: Color { Palette.accent(store.settings.accentName) }

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if let p = parcel {
                    ScrollView {
                        VStack(spacing: 16) {
                            header(p)
                            codeCard(p)
                            infoCard(p)
                            trackCard(p)
                            actionBar(p)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                    }
                } else {
                    EmptyBox(icon: "questionmark.folder", title: "包裹不存在", subtitle: "可能已被删除")
                }
            }
            .navigationTitle("包裹详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    // MARK: 头部

    private func header(_ p: Parcel) -> some View {
        HStack(spacing: 13) {
            CompanyLogo(code: p.companyCode, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.title.isEmpty ? p.companyName : p.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(p.companyName).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    if let src = p.source.flatMap({ Platform(rawValue: $0) }) {
                        Text("·").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                        HStack(spacing: 4) {
                            PlatformBadge(platform: src, size: 12)
                            Text(src.title).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: 取件码

    private func codeCard(_ p: Parcel) -> some View {
        VStack(spacing: 12) {
            if p.code.isEmpty {
                Text(p.isTransit ? "在途，暂无取件码" : "没有取件码")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            } else {
                Text("取件码")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
                Text(p.code)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.isPicked ? Palette.tertiary : Palette.text)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                BarcodeView(text: p.code)
                    .frame(height: 54)
                    .padding(.horizontal, 20)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .padding(.horizontal, 30)
                HStack(spacing: 14) {
                    Button {
                        UIPasteboard.general.string = p.code
                        Haptic.tap()
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Label(copied ? "已复制" : "复制取件码", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)

                    if !p.placeText.isEmpty {
                        Button {
                            let q = p.placeText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(q)") {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        } label: {
                            Label("地图", systemImage: "map")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    // MARK: 信息

    private func infoCard(_ p: Parcel) -> some View {
        VStack(spacing: 0) {
            if let mail = p.mailNo, !mail.isEmpty {
                infoRow("运单号", mail, copyable: true)
                DividerLine()
            }
            if !p.placeText.isEmpty {
                infoRow("驿站", p.placeText)
                DividerLine()
            }
            if !p.address.isEmpty {
                infoRow("地址", p.address)
                DividerLine()
            }
            if let arrived = p.arrivedAt {
                infoRow("到站", Fmt.monthDayTime(arrived))
                DividerLine()
            }
            if let picked = p.pickedAt {
                infoRow("取件", Fmt.monthDayTime(picked))
                DividerLine()
            }
            if let eta = p.eta {
                infoRow("预计送达", Fmt.monthDay(eta))
                DividerLine()
            }
            if let acc = p.accountLabel {
                infoRow("账号", acc)
                DividerLine()
            }
            infoRow("入库", Fmt.monthDayTime(p.createdAt))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .cardStyle()
    }

    private func infoRow(_ k: String, _ v: String, copyable: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(k).font(.system(size: 13)).foregroundStyle(Palette.tertiary).frame(width: 62, alignment: .leading)
            Text(v).font(.system(size: 13)).foregroundStyle(Palette.text).lineLimit(2)
            Spacer()
            if copyable {
                Button {
                    UIPasteboard.general.string = v
                    Haptic.tap()
                    store.toast = "已复制"
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: 轨迹

    @ViewBuilder
    private func trackCard(_ p: Parcel) -> some View {
        if !p.track.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("物流轨迹").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(p.track.enumerated()), id: \.element.id) { idx, node in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(idx == 0 ? accent : Palette.tertiary.opacity(0.5))
                                    .frame(width: idx == 0 ? 8 : 6, height: idx == 0 ? 8 : 6)
                                    .padding(.top, 5)
                                if idx < p.track.count - 1 {
                                    Rectangle().fill(Palette.separator).frame(width: 1.2)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(width: 10)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(node.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(idx == 0 ? Palette.text : Palette.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(node.time)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.tertiary)
                            }
                            .padding(.bottom, idx == p.track.count - 1 ? 0 : 14)
                            Spacer(minLength: 0)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    // MARK: 操作

    private func actionBar(_ p: Parcel) -> some View {
        VStack(spacing: 10) {
            if let box = p.fcBox, p.isAwaiting {
                Button {
                    askOpen = true
                } label: {
                    HStack(spacing: 6) {
                        if opening { ProgressView().tint(.white) }
                        Image(systemName: "lock.open.fill").font(.system(size: 14, weight: .semibold))
                        Text(opening ? "正在开柜…" : "一键开柜（(box.location)）")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.orange))
                }
                .buttonStyle(PressableStyle())
                .disabled(opening)
                .alert("确认开启丰巢柜门？", isPresented: $askOpen) {
                    Button("开柜", role: .destructive) { Task { await openBox(box) } }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("\(box.cabinetCode) · \(box.location) · 取件码 \(box.code)")
                }
            }
            HStack(spacing: 10) {
            if p.isAwaiting || p.isTransit {
                Button {
                    withAnimation(.easeInOut) {
                        store.markPicked(p.id)
                    }
                    store.toast = "已标记已取"
                    dismiss()
                } label: {
                    Text("标记已取")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent))
                }
                .buttonStyle(PressableStyle())
            }
            Button {
                withAnimation { store.delete(p.id) }
                store.toast = "已删除"
                dismiss()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.red)
                    .frame(width: 50, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.red.opacity(0.12)))
            }
            .buttonStyle(PressableStyle())
            }
        }
    }

    private func openBox(_ box: FcBoxMeta) async {
        opening = true
        defer { opening = false }
        do {
            try await FengchaoService.shared.openBox(box)
            Haptic.success()
            store.toast = "柜门已打开"
        } catch {
            Haptic.warn()
            store.toast = (error as? LocalizedError)?.errorDescription ?? "开柜失败"
        }
    }
}
