import SwiftUI

/// 平台身份码：内容来自平台接口，加载失败就说失败，不造假码
struct IdentitySheet: View {
    let kind: IdentityKind
    @Environment(\.dismiss) private var dismiss
    @State private var code: IdentityCode? = nil
    @State private var loading = true
    @State private var error: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Palette.bg.ignoresSafeArea()
                VStack(spacing: 18) {
                    codeCard
                    Text("身份码由平台接口实时下发，有效期通常 5–10 分钟。")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
                .padding(.top, 10)
            }
            .navigationTitle("\(kind.title)身份码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(kind.asset)
                    .resizable().scaledToFit().frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(kind.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                Spacer()
                if let code {
                    Text(Fmt.countdown(code.expiresAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.45))
                }
            }

            if loading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在向\(kind.title)请求身份码…")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.45))
                }
                .frame(height: 170)
            } else if let error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.black.opacity(0.35))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Text("重试")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(Color(hex: kind.tint)))
                    }
                }
                .frame(height: 170)
            } else if let code {
                BarcodeView(text: code.code)
                    .frame(height: 74)
                    .frame(maxWidth: .infinity)

                Text(spaced(code.code))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)

                Text(code.detail.isEmpty ? "出示给驿站工作人员扫码" : "\(code.detail) · 出示给工作人员")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.4))
                    .lineLimit(1)
            }

            Button {
                Task { await load(force: true) }
            } label: {
                Label("刷新身份码", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color(hex: kind.tint)))
            }
            .disabled(loading)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
        .padding(.horizontal, 20)
    }

    private func load(force: Bool = false) async {
        if !force, let cached = IdentityService.shared.cached(kind) {
            code = cached
            loading = false
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            code = try await IdentityService.shared.fetch(kind, force: force)
            Haptic.tap()
        } catch {
            code = nil
            self.error = (error as? LocalizedError)?.errorDescription ?? "身份码加载失败"
        }
    }

    private func spaced(_ s: String) -> String {
        guard s.count > 8 else { return s }
        var out: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: 4, limitedBy: s.endIndex) ?? s.endIndex
            out.append(String(s[idx..<end]))
            idx = end
        }
        return out.joined(separator: " ")
    }
}
