import GameController
import GameCore

/// Merges touch, gamepad and hardware keyboard into one `InputState` per frame.
final class InputRouter {
    struct Commands: OptionSet {
        let rawValue: Int
        static let pause = Commands(rawValue: 1 << 0)
        static let restart = Commands(rawValue: 1 << 1)
        static let toggleDebug = Commands(rawValue: 1 << 2)
        static let reloadLevels = Commands(rawValue: 1 << 3)
    }

    var touches = TouchTracker()
    private var keyboardJump = ButtonEdge()
    private var padJump = ButtonEdge()
    private var commandEdges: [Int: ButtonEdge] = [:]

    /// True when an extended gamepad is connected; the touch buttons hide then.
    var hasGamepad: Bool {
        GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    func poll() -> InputState {
        touches.poll()
            .merged(with: keyboard())
            .merged(with: gamepad())
    }

    func reset() {
        touches.cancelAll()
    }

    private func keyboard() -> InputState {
        guard let kb = GCKeyboard.coalesced?.keyboardInput else {
            _ = keyboardJump.update(isDown: false)
            return .none
        }
        func down(_ code: GCKeyCode) -> Bool { kb.button(forKeyCode: code)?.isPressed ?? false }
        let held = down(.spacebar) || down(.upArrow) || down(.keyW)
        return InputState(left: down(.leftArrow) || down(.keyA),
                          right: down(.rightArrow) || down(.keyD),
                          jumpPressed: keyboardJump.update(isDown: held),
                          jumpHeld: held)
    }

    private func gamepad() -> InputState {
        var state = InputState()
        var held = false
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            let x = pad.leftThumbstick.xAxis.value
            if pad.dpad.left.isPressed || x < -0.35 { state.left = true }
            if pad.dpad.right.isPressed || x > 0.35 { state.right = true }
            if pad.buttonA.isPressed || pad.buttonB.isPressed { held = true }
        }
        state.jumpHeld = held
        state.jumpPressed = padJump.update(isDown: held)
        return state
    }

    /// One-shot commands (pause, restart, debug) from keyboard and gamepad.
    func pollCommands() -> Commands {
        var commands: Commands = []
        func edge(_ id: Int, _ isDown: Bool, _ command: Commands) {
            if commandEdges[id, default: ButtonEdge()].update(isDown: isDown) { commands.insert(command) }
        }
        let kb = GCKeyboard.coalesced?.keyboardInput
        func key(_ code: GCKeyCode) -> Bool { kb?.button(forKeyCode: code)?.isPressed ?? false }
        edge(0, key(.escape) || key(.keyP), .pause)
        edge(1, key(.keyR), .restart)
        edge(2, key(.graveAccentAndTilde), .toggleDebug)
        edge(3, key(.keyL), .reloadLevels)

        var menu = false, restart = false
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            if pad.buttonMenu.isPressed { menu = true }
            if pad.buttonY.isPressed { restart = true }
        }
        edge(4, menu, .pause)
        edge(5, restart, .restart)
        return commands
    }
}
