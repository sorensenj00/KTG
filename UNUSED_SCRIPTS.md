# Unused Scripts
The following scripts were identified as unused or broken and have been removed or flagged:

1.  **`src/ServerScriptService/GameLoop/RandomEventManager.luau`**
    *   **Status**: Deleted
    *   **Reason**: It required `GoldenGunManager` which does not exist in the codebase. It was also not required by `Main.server.luau`.
2.  **`src/ServerScriptService/GameLoop/YeetCannon.server.luau`**
    *   **Status**: Deleted
    *   **Reason**: Refactored into `YeetCannonManager.luau` (module) to fix performance issues with multiple event listeners and fragile `WaitForChild` logic.

## Other Notes
*   **`src/ServerScriptService/GameLoop/GiantFootstepHandler.server.luau`**: This script runs automatically (Server Script) and handles the "Giant Footstep" mechanic via RemoteEvents. Although not explicitly required by `Main`, it is "used" by the game logic listening to client events.
*   **`src/ServerScriptService/GameLoop/DamageTracker.luau`**: This module is required by `BotController`, `ProgressionManager`, and `Blaster` scripts, so it is definitely used.
