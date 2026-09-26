import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: AppModel
    @AppStorage(SettingsKeys.sound) private var sound = true
    @AppStorage(SettingsKeys.haptics) private var haptics = true
    @AppStorage(SettingsKeys.hints) private var hints = true
    @State private var confirmReset = false
    private let theme = Palette.menu

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    IconButton(systemName: "chevron.left", theme: theme) { app.screen = .menu }
                    Spacer()
                    Text("Settings")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(theme.inkColor)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }

                VStack(spacing: 10) {
                    Toggle("Sound effects", isOn: $sound)
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Offer a ghost hint after \(GameScene.hintThreshold) deaths", isOn: $hints)
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.inkColor)
                .tint(theme.accentColor)
                .frame(maxWidth: 440)

                HStack(spacing: 12) {
                    Button("Reset progress") { confirmReset = true }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                    #if DEBUG
                    Button("Unlock all") { app.unlockAll() }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                    #endif
                }

                Text("Controls: left half of the screen moves, right half jumps. Hold jump to jump higher. Gamepads and keyboards (arrows / WASD + space, R restart, Esc pause) work too.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.inkColor.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { app.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlocked levels, deaths and best times will be erased.")
        }
    }
}
