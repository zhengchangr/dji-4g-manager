import SwiftUI
import AppKit

/// 应用启动后根据设置决定是否在 Dock 中显示图标。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}

@main
struct DJI4GManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        Window("DJI 4G Manager", id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView()
                .environment(appState)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIcon: String {
        if appState.wakeRecovery != nil {
            return "arrow.triangle.2.circlepath"
        }
        return switch appState.phase {
        case .connected: "antenna.radiowaves.left.and.right"
        case .switching: "arrow.triangle.2.circlepath"
        case .failed, .searching, .gen2Only: "simcard"
        }
    }

}
