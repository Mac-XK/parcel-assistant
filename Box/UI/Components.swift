import SwiftUI

// MARK: - 通用容器

struct SectionCard<Content: View>: View {
    var title: String? = nil
    var caption: String? = nil
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.6)
    }
}

// MARK: - 徽标

struct CompanyLogo: View {
    var code: Int
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(Courier.tile(code))
            if let asset = Courier.asset(code) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }
}

struct PlatformBadge: View {
    var platform: Platform
    var size: CGFloat = 15

    var body: some View {
        Image(platform.asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct StatusPill: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - 空状态

struct EmptyBox: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

// MARK: - 可点按反馈

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - 代码块

struct CodeText: View {
    var text: String
    var size: CGFloat = 22
    var color: Color = Palette.text

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}

// MARK: - 行

struct RowLink<Trailing: View>: View {
    var icon: String
    var iconColor: Color = Palette.secondary
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(iconColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundStyle(Palette.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 9)
    }
}

// MARK: - 摇一摇/点击反馈的 toast

struct ToastView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

// MARK: - 多行输入（iOS 15 没有 scrollContentBackground，用 UITextView 包一层）

struct MultilineInput: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .systemFont(ofSize: 14)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = font
        tv.textColor = .label
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        tv.text = text
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        tv.textColor = .label
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) { text.wrappedValue = textView.text }
    }
}
