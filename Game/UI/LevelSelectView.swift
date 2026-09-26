import SwiftUI

struct LevelSelectView: View {
    @ObservedObject var app: AppModel
    private let theme = Palette.menu
    private let columns = Array(repeating: GridItem(.fixed(78), spacing: 14), count: 5)

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    IconButton(systemName: "chevron.left", theme: theme) { app.screen = .menu }
                    Spacer()
                    Text("Levels")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(theme.inkColor)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 24)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<app.levelCount, id: \.self) { index in
                            cell(index)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .id(app.progressVersion)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let unlocked = app.progress.isUnlocked(levelIndex: index)
        let record = app.progress.record(forLevel: app.levelID(index))
        Button {
            app.play(index)
        } label: {
            VStack(spacing: 2) {
                if unlocked {
                    Text("\(index + 1)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                    if record.isCompleted, let best = record.bestTime {
                        Text(verbatim: formatTime(best))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    } else if record.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                    } else {
                        Text(" ").font(.system(size: 11))
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .foregroundStyle(unlocked ? theme.backgroundColor : theme.inkColor.opacity(0.35))
            .frame(width: 78, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(unlocked ? theme.inkColor : theme.inkColor.opacity(0.1))
            )
            .overlay(alignment: .bottom) {
                if unlocked && record.deaths > 0 {
                    Text("☠︎ \(record.deaths)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.backgroundColor.opacity(0.7))
                        .padding(.bottom, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked ? Text("Level \(index + 1), \(app.levelName(index))") : Text("Level \(index + 1), locked"))
    }
}
