import SwiftUI

/// Big, flat, rounded button matching the game's two-tone look.
struct ChunkyButtonStyle: ButtonStyle {
    var theme: Theme = Palette.menu
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(prominent ? theme.backgroundColor : theme.inkColor)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .frame(minWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? theme.inkColor : theme.inkColor.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Small round icon button used in the HUD.
struct IconButton: View {
    let systemName: String
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(theme.inkColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(theme.inkColor.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

/// The hero, drawn in SwiftUI for menus. Blinks and bounces.
struct MascotView: View {
    var theme: Theme = Palette.menu
    var size: CGFloat = 64
    @State private var bounce = false
    @State private var blink = false
    @State private var blinking = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(theme.inkColor)
                .frame(width: size * 0.78, height: size)
            HStack(spacing: size * 0.08) {
                eye
                eye
            }
            .offset(x: size * 0.05, y: -size * 0.12)
        }
        .scaleEffect(x: bounce ? 1.06 : 0.96, y: bounce ? 0.94 : 1.04, anchor: .bottom)
        .offset(y: bounce ? 0 : -size * 0.12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                bounce = true
            }
            if !blinking {
                blinking = true
                blinkLoop()
            }
        }
        .onDisappear { blinking = false }
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.26, height: size * 0.26)
            Circle().fill(theme.inkColor).frame(width: size * 0.12, height: size * 0.12).offset(x: size * 0.04)
        }
        .scaleEffect(y: blink ? 0.1 : 1)
    }

    private func blinkLoop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2...4)) {
            guard blinking else { return }
            withAnimation(.easeInOut(duration: 0.08)) { blink = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
                blinkLoop()
            }
        }
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let hundredths = Int((seconds - Double(total)) * 100)
    if total >= 60 {
        return String(format: "%d:%02d.%02d", total / 60, total % 60, hundredths)
    }
    return String(format: "%d.%02ds", total, hundredths)
}
