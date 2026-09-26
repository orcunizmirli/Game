import Foundation

/// Builds runtime traps and effects from their JSON definitions.
public enum TrapFactory {
    public static func make(_ definition: TrapDefinition) -> any Trap {
        TriggeredTrap(definition: definition)
    }

    public static func makeAll(_ definitions: [TrapDefinition]) -> [any Trap] {
        definitions.map(make)
    }

    public static func makeEffect(_ effect: Effect) -> any TrapEffect {
        switch effect {
        case .collapse(let tiles):
            return CollapseEffect(tiles: tiles)
        case .spawnSpikes(let tiles, let direction):
            return SpawnSpikesEffect(tiles: tiles, direction: direction)
        case .moveDoor(let target, let speed):
            return MoveDoorEffect(target: target, speed: speed)
        case .dropCeiling(let tiles, let speed):
            return DropCeilingEffect(tiles: tiles, speed: speed)
        case .invertControls(let duration):
            return InvertControlsEffect(duration: duration)
        case .emit(let event):
            return EmitEffect(event: event)
        case .addTiles(let tiles):
            return AddTilesEffect(tiles: tiles)
        case .slideTiles(let tiles, let offset, let speed):
            return SlideTilesEffect(tiles: tiles, offset: offset, speed: speed)
        }
    }
}
