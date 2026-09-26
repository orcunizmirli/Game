import SwiftUI

struct MainMenuView: View {
    @ObservedObject var app: AppModel
    private let theme = Palette.menu

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            // Floor strip, like a level.
            VStack {
                Spacer()
                Rectangle().fill(theme.inkColor).frame(height: 36)
            }
            .ignoresSafeArea()

            HStack(spacing: 48) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "TRICK\nTILES")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(theme.inkColor)
                        .lineSpacing(-12)
                    Text("trust nothing. especially the floor.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.inkColor.opacity(0.65))
                    MascotView(theme: theme, size: 54)
                        .padding(.top, 18)
                }

                VStack(spacing: 12) {
                    if app.levelCount > 0 {
                        Button(app.hasStarted ? LocalizedStringKey("Continue · \(app.continueLevel + 1)") : LocalizedStringKey("Play")) {
                            app.play(app.continueLevel)
                        }
                        .buttonStyle(ChunkyButtonStyle(theme: theme))
                        Button("Levels") { app.screen = .levels }
                            .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                    } else {
                        Text(app.loadError ?? "No levels found")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
                            .frame(maxWidth: 260)
                    }
                    Button("Settings") { app.screen = .settings }
                        .buttonStyle(ChunkyButtonStyle(theme: theme, prominent: false))
                    stats
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 30)
        }
    }

    private var stats: some View {
        HStack(spacing: 16) {
            Label("\(app.completedCount)/\(app.levelCount)", systemImage: "flag.checkered")
            Label("\(app.progress.totalDeaths)", systemImage: "heart.slash.fill")
        }
        .font(.system(size: 14, weight: .bold, design: .rounded))
        .foregroundStyle(theme.inkColor.opacity(0.6))
        .id(app.progressVersion)
    }
}
