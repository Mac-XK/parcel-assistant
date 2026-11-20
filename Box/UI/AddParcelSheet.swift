import SwiftUI

struct AddParcelSheet: View {
    @ObservedObject var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable { case smart = "智能识别", manual = "手动添加" }

    @State private var mode: Mode = .smart
    @State private var text: String = ""
    @State private var parsed: ParsedDelivery? = nil
    @State private var parsedSource: String = ""
    @State private var showingHits = false

    // 手动表单
    @State private var code = ""
    @State private var mailNo = ""
    @State private var title = ""
    @State private var companyCode = 0
    @State private var station = ""
    @State private var transit = false

    private struct Sample { let title: String; let text: String }
    private static let samples: [Sample] = [
        Sample(title: "菜鸟短信", text: "【菜鸟驿站】您的包裹已到万科城店，取件码 6-5-9955，请及时领取，营业时间 08:00-22:00。"),
        Sample(title: "丰巢取件", text: "【丰巢】您的快件已存放至丰巢快递柜科技园A座，取件码 8-2-3021，请凭取件码取件。"),
        Sample(title: "顺丰在途", text: "顺丰速运：您的快件 SF1234567890123 已发出，下一站深圳南山集散点，预计明天送达。"),
    ]

    private var accent: Color { Palette.accent(store.settings.accentName) }

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)

                        if mode == .smart { smartSection } else { manualSection }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            .task {
                // 截图/调试：`-sample` 自动填第一段示例并识别
                if ProcessInfo.processInfo.arguments.contains("-sample"), parsed == nil {
                    text = Self.samples[0].text
                    parsedSource = text
                    parsed = DeliveryParser.parse(text)
                }
            }
            .navigationTitle("添加包裹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        Text("保存").font(.system(size: 17, weight: .semibold))
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: 智能识别

    private var smartSection: some View {
        VStack(spacing: 14) {
            SectionCard(title: "粘贴短信或截图里的文字") {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("例如：\n【菜鸟驿站】您的包裹已到万科城店，取件码 6-5-9955，请及时领取。")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    MultilineInput(text: $text)
                        .frame(height: 132)
                        .onChange(of: text) { newValue in
                            if newValue != parsedSource { parsed = nil }
                        }
                }
                DividerLine().padding(.vertical, 8)
                HStack(spacing: 10) {
                    Button {
                        if let s = UIPasteboard.general.string { text = s; Haptic.tap() }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)

                    Button {
                        text = ""
                        parsed = nil
                    } label: {
                        Label("清空", systemImage: "xmark.circle")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.tertiary)

                    Spacer()

                    Button {
                        Haptic.tap()
                        parsedSource = text
                        parsed = DeliveryParser.parse(text)
                    } label: {
                        Text("识别")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack(spacing: 8) {
                Text("试试示例").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                ForEach(Self.samples, id: \.title) { sample in
                    Button {
                        Haptic.tap()
                        text = sample.text
                        parsedSource = sample.text
                        parsed = DeliveryParser.parse(sample.text)
                    } label: {
                        Text(sample.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(accent.opacity(0.12)))
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
            }

            if let p = parsed {
                SectionCard(title: "识别结果", caption: "规则来自原版 utils/smsParse.ts，纯本地计算。") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            if let code = p.code, !code.isEmpty {
                                chip("取件码", code, accent)
                            }
                            if let mail = p.mailNo {
                                chip("单号", mail, Palette.blue)
                            }
                        }
                        if let st = p.station, !st.isEmpty {
                            labelRow("驿站", st)
                        }
                        if let c = p.company, !c.isEmpty {
                            labelRow("公司", c)
                        }
                        if let tail = p.tail {
                            labelRow("手机尾号", tail)
                        }
                        if p.isEmpty {
                            Text("没认出取件码或单号，换一段文字试试")
                                .font(.system(size: 13)).foregroundStyle(Palette.red)
                        }
                        DividerLine()
                        Button {
                            withAnimation { showingHits.toggle() }
                        } label: {
                            HStack {
                                Text("识别依据（\(p.hits.count)）")
                                    .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                                Spacer()
                                Image(systemName: showingHits ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showingHits {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(p.hits, id: \.self) { h in
                                    Text("· \(h)").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ k: String, _ v: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(k).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.12)))
    }

    private func labelRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(.system(size: 12)).foregroundStyle(Palette.tertiary).frame(width: 52, alignment: .leading)
            Text(v).font(.system(size: 13)).foregroundStyle(Palette.text).lineLimit(2)
            Spacer()
        }
    }

    // MARK: 手动

    private var manualSection: some View {
        VStack(spacing: 14) {
            SectionCard(title: "必填") {
                field("取件码", text: $code, placeholder: "如 6-5-9955")
                DividerLine()
                field("运单号", text: $mailNo, placeholder: "可留空")
            }
            SectionCard(title: "详情") {
                field("商品名", text: $title, placeholder: "如 鼠标、纸巾")
                DividerLine()
                HStack {
                    Text("快递公司").font(.system(size: 14)).foregroundStyle(Palette.text)
                    Spacer()
                    Picker("", selection: $companyCode) {
                        Text("其他快递").tag(0)
                        ForEach(1...21, id: \.self) { i in
                            Text(Courier.name(i)).tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.secondary)
                }
                .padding(.vertical, 10)
                DividerLine()
                HStack {
                    Text("驿站").font(.system(size: 14)).foregroundStyle(Palette.text)
                    Spacer()
                    Picker("", selection: $station) {
                        Text("不指定").tag("")
                        ForEach(store.stations) { st in
                            Text(st.name).tag(st.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.secondary)
                }
                .padding(.vertical, 10)
                DividerLine()
                Toggle(isOn: $transit) {
                    Text("还在路上（在途）").font(.system(size: 14)).foregroundStyle(Palette.text)
                }
                .tint(accent)
                .padding(.vertical, 10)
            }
        }
    }

    private func field(_ label: String, text binding: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 14)).foregroundStyle(Palette.text).frame(width: 64, alignment: .leading)
            TextField(placeholder, text: binding)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 10)
    }

    // MARK: 保存

    private var canSave: Bool {
        if mode == .smart {
            guard let p = parsed else { return false }
            return !p.isEmpty
        }
        return !code.trimmingCharacters(in: .whitespaces).isEmpty || !transit
    }

    private func save() {
        if mode == .smart, let p = parsed {
            var parcel = Parcel()
            parcel.code = p.code ?? ""
            parcel.mailNo = p.mailNo
            parcel.companyCode = Courier.code(fromName: p.company ?? "")
            parcel.station = p.station ?? ""
            parcel.title = p.company ?? "识别导入"
            parcel.status = transit || parcel.code.isEmpty ? .transit : .awaiting
            if !parcel.code.isEmpty { parcel.arrivedAt = Date() }
            if let first = p.hits.first {
                parcel.track = [TrackNode(time: Fmt.mmddhm(), text: first)]
            }
            store.add(parcel)
            store.toast = "已添加「\(parcel.title)」"
        } else {
            var parcel = Parcel()
            parcel.code = code.trimmingCharacters(in: .whitespaces)
            parcel.mailNo = mailNo.isEmpty ? nil : mailNo
            parcel.title = title.isEmpty ? Courier.name(companyCode) : title
            parcel.companyCode = companyCode
            parcel.station = station
            parcel.status = transit ? .transit : .awaiting
            if !parcel.code.isEmpty { parcel.arrivedAt = Date() }
            store.add(parcel)
            store.toast = "已添加「\(parcel.title)」"
        }
        dismiss()
    }
}
