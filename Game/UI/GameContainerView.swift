import SwiftUI
import SpriteKit

/// The game screen: SpriteKit scene underneath, SwiftUI HUD and menus on top.
struct GameContainerView: View {
    @StateObject private var model: GameViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(app: AppModel, startLevel: Int) {
        _model = StateObject(wrappedValue: GameViewModel(app: app, startLevel: startLevel))
    }

    var body: some View {
        ZStack {
            if let scene = model.scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
            } else {
                errorView
            }

            HUDView(model: model)

            if let banner = model.banner {
                Text(banner)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(model.theme.backgroundColor)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(model.theme.inkColor))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if model.isPaused {
                PauseMenuView(model: model)
                    .transition(.opacity)
            }

            if model.hud.finished {
                FinishedView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.banner)
        .animation(.easeOut(duration: 0.15), value: model.isPaused)
        .animation(.easeOut(duration: 0.3), value: model.hud.finished)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && !model.hud.finished { model.pause() }
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Text("Couldn't start the game")
                .font(.title2.bold())
            Text(model.error ?? "")
                .font(.footnote.monospaced())
            Button("Back") { model.quitToMenu() }
                .buttonStyle(ChunkyButtonStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.menu.backgroundColor)
    }
}

struct HUDView: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        let theme = model.theme
        let hud = model.hud
        VStack {
            HStack(spacing: 10) {
                IconButton(systemName: "pause.fill", theme: theme) { model.pause() }
                    .accessibilityLabel("Pause")
                #if DEBUG
                IconButton(systemName: model.showsDebugOverlay ? "ladybug.fill" : "ladybug", theme: theme) {
                    model.showsDebugOverlay.toggle()
                }
                IconButton(systemName: "arrow.clockwise.circle", theme: theme) { model.reloadLevels() }
                    .accessibilityLabel("Reload levels from disk")
                #endif
                Spacer()
                Text("\(hud.levelIndex + 1)/\(max(hud.levelCount, 1))  \(hud.levelName)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Spacer()
                if model.showsHintButton {
                    Button {
                        model.toggleGhost()
                    } label: {
                        Label(hud.ghostVisible ? "Hide hint" : "Hint", systemImage: "lightbulb.fill")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(theme.backgroundColor)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(theme.accentColor))
                    }
                    .buttonStyle(.plain)
                }
                Text("☠︎ \(hud.levelDeaths)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                    .accessibilityLabel("\(hud.levelDeaths) deaths")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            if hud.controlsInverted {
                Label("CONTROLS INVERTED", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(theme.backgroundColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.accentColor))
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(duration: 0.25), value: hud.controlsInverted)
    }
}

struct PauseMenuView: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        let theme = model.theme
        ZStack {
            theme.backgroundColor.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Paused")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(theme.inkColor)
                Button("Resume") { model.resume() }
                    .buttonStyle(ChunkyButtonStyle(theme: theme))
                Button("Restart level") { model.restart() }
                    .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                HStack(spacing: 12) {
                    Button("Levels") { model.quitToLevels() }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                    Button("Menu") { model.quitToMenu() }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                }
            }
        }
    }
}

struct FinishedView: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        let theme = model.theme
        let progress = model.scene?.session.progress
        ZStack {
            theme.backgroundColor.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 14) {
                MascotView(theme: theme, size: 56)
                Text("You made it out!")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(theme.inkColor)
                Text("Every trap survived. Total deaths: \(progress?.totalDeaths ?? 0)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.inkColor.opacity(0.7))
                HStack(spacing: 12) {
                    Button("Levels") { model.quitToLevels() }
                        .buttonStyle(ChunkyButtonStyle(theme: theme))
                    Button("Menu") { model.quitToMenu() }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                }
            }
        }
    }
}
