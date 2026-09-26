import SwiftUI

/// Top-level navigation between menu, level select, settings and the game.
struct RootView: View {
    @StateObject private var app = AppModel()

    var body: some View {
        ZStack {
            switch app.screen {
            case .menu:
                MainMenuView(app: app)
                    .transition(.opacity)
            case .levels:
                LevelSelectView(app: app)
                    .transition(.opacity)
            case .settings:
                SettingsView(app: app)
                    .transition(.opacity)
            case .playing(let level):
                GameContainerView(app: app, startLevel: level)
                    .id(level)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.screen)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .preferredColorScheme(.light)
    }
}
