import SwiftUI

struct DebugSheet: Identifiable {
    let id: String
}

struct ContentView: View {
    @ObservedObject var store = Store.shared
    @State private var tab: Int = ContentView.initialTab
    @State private var debugSheet: DebugSheet? = ContentView.initialSheet

    /// 调试/截图用：`-tab2` 直接启动到统计页
    static var initialTab: Int {
        for arg in ProcessInfo.processInfo.arguments {
            if arg.hasPrefix("-tab"), let v = Int(arg.dropFirst(4)) { return v }
        }
        return 0
    }

    /// 调试/截图用：`-sheet detail|add|identity|platforms|about`
    static var initialSheet: DebugSheet? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-sheet"), i + 1 < args.count else { return nil }
        return DebugSheet(id: args[i + 1])
    }

    private var scheme: ColorScheme? {
        switch store.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        Group {
            if store.settings.simpleMode {
                PickupView()
            } else {
                TabView(selection: $tab) {
                    PickupView()
                        .tabItem { Label("取件", systemImage: "shippingbox") }
                        .tag(0)
                    ParcelsView()
                        .tabItem { Label("包裹", systemImage: "archivebox") }
                        .tag(1)
                    StatsView()
                        .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }
                        .tag(2)
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                        .tag(3)
                }
            }
        }
        .tint(Palette.accent(store.settings.accentName))
        .preferredColorScheme(scheme)
        .sheet(item: $debugSheet) { item in
            switch item.id {
            case "detail":
                ParcelDetailView(parcelID: Store.shared.pending.first?.id ?? UUID())
            case "add":
                AddParcelSheet()
            case "identity":
                IdentitySheet(kind: .cainiao)
            case "platforms":
                NavigationView { PlatformAuthView() }
            case "about":
                AboutSheet()
            case "login":
                PlatformLoginSheet(platform: .taobao)
            case "fc":
                FengchaoLoginSheet()
            case "mi":
                XiaomiLoginSheet()
            case "kd":
                KdniaoCredentialSheet()
            case "track":
                TrackSearchSheet()
            case "harvestjd":
                HarvestSheet(platform: .jd)
            case "harvestpdd":
                HarvestSheet(platform: .pdd)
            default:
                EmptyView()
            }
        }
        .task {
            await Notifier.shared.refreshAuthorization()
            Notifier.shared.refresh(parcels: store.parcels, settings: store.settings)
        }
    }
}
