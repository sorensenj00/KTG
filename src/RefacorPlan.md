# Refactoring Recommendations & Architecture Plan

## 1. Executive Summary

The current codebase utilizes a flat structure within `GameLoop` and relies on manual `require` chains and standalone scripts. While functional, this scales poorly and makes tracking dependencies/execution order difficult. 

**Core Recommendations:**
1.  **Restructure Directories:** Group related systems (Combat, Progression, Entities).
2.  **Adopt a Framework:** Use a lightweight Service/Controller loader to standardize initialization.
3.  **Optimize Loops:** Centralize `Heartbeat` connections (especially in `XPOrbManager`).
4.  **Network Optimization:** Move visual-only logic (Orbs, Projectiles) to the Client, keeping the Server authoritative on state only.

---

## 2. Directory Structure

**Current:**
- `ServerScriptService/GameLoop/` (Contains everything)
- `StarterPlayerScripts/` (Mixed Controllers and local scripts)

**Proposed:**
```text
src/
├── ReplicatedStorage/
│   ├── Shared/
│   │   ├── Constants/
│   │   ├── Types/
│   │   └── Utility/
│   └── Networking/ (RemoteEvents/Functions)
│
├── ServerScriptService/
│   ├── Server.server.luau (Single Entry Point)
│   ├── Services/ (Core Game Logic - Singleton)
│   │   ├── Combat/
│   │   │   ├── BotService.luau
│   │   │   └── SafeZoneService.luau
│   │   ├── Progression/
│   │   │   ├── MetaProgressionService.luau
│   │   │   └── XPOrbService.luau
│   │   └── World/
│   │       ├── LightingService.luau
│   │       └── SpawnerService.luau
│   └── Components/ (Class/Object Logic)
│       ├── Bot.luau
│       └── YeetCannon.luau
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        ├── Client.client.luau (Single Entry Point)
        └── Controllers/ (Client-side Logic - Singleton)
            ├── MovementController.luau (Integrated)
            ├── HUDController.luau
            └── Visuals/
                ├── OrbVisualsController.luau
                └── BlasterVisualsController.luau
```

---

## 3. Architecture Pattern (Service/Controller)

Move away from manual `require` chains in `Main.server.luau`.

**Proposed Loader (`Server.server.luau`):**
1.  Iterate `ServerScriptService/Services`.
2.  Require all modules.
3.  Call `.Init()` on all (for internal setup).
4.  Call `.Start()` on all (for event listening/inter-service communication).

**Benefit:** Decouples file loading order from logic execution. Prevents "race conditions" where a module isn't ready when another tries to use it.

---

## 4. Specific Refactors

### A. XPOrbManager (Major Optimization)
**Current:**
- Server creates `Part` instance + Visuals + `Heartbeat` connection *per orb*.
- High server CPU usage due to physics calculation and Lua loops for animation.

**Recommendation:**
1.  **Server (`XPOrbService`):**
    - Maintains purely *data* (Position, Value, Tier).
    - Uses a single `Heartbeat` loop for Magnet logic (spatial query).
    - Replicates orb data to clients via a single RemoteEvent (Batched updates) or Attributes on a folder.
2.  **Client (`OrbVisualsController`):**
    - Listens for "OrbSpawned" / "OrbDespawned" events.
    - Creates visual Parts locally (using `PartCache` or pooling).
    - Handles floating animations and particle effects completely on the Client.
    - Uses `RunService.RenderStepped` for smooth interpolation.

### B. BotController (Structure & Perf)
**Current:**
- Monolithic loop handling State, Pathfinding, and Combat.
- Manual throttling.

**Recommendation:**
1.  **Separation of Concerns:**
    - `BotService`: Handles the global loop and spawning.
    - `Bot` (Component): A class representing a single bot instance. Holds its own state (`Target`, `Path`, etc).
2.  **Centralized Update:**
    - `BotService` iterates over all `Bot` objects.
    - Use "Time Slicing" (Buckets) to update 1/Nth of bots per frame for expensive logic (Pathfinding).
    - Update all bots every frame for cheap logic (Movement interpolation).

### C. Client Unification
**Current:**
- `MovementController` is a standalone script.
- `GameClient` loads other controllers.

**Recommendation:**
1.  Convert `MovementController` into a standard `Controller` module.
2.  Expose state methods (e.g., `MovementController:IsCrouching()`) so other controllers (like `BlasterController` for recoil) can access it easily without attribute hacks.
3.  Ensure `Client.client.luau` initializes it alongside others.

---

## 5. Implementation Steps

### ✅ Phase 1: Foundation (COMPLETE)
- ✅ Created new folder structure (`Services/Combat`, `Progression`, `World`)
- ✅ Wrote `Server.server.luau` and `Client.client.luau` loaders with auto-discovery
- ✅ Migrated all 22 server managers to `Services/` as `*Service.luau`
- ✅ Migrated all client controllers to `Controllers/`
- ✅ Implemented two-phase initialization (Init → Start)
- ✅ Added Loading Screen for smooth UX
- ✅ Verified game boots and runs correctly
- ✅ Deleted all old files from `GameLoop/` and `StarterPlayerScripts/`

**Completed:** 2025-11-29

---

### ✅ Phase 2: Client Unification (COMPLETE)
- ✅ Converted `MovementController` to standard Controller module
- ✅ Integrated `ClientRuntime` functionality into `Client.client.luau`
- ✅ All controllers now use consistent `Start()` pattern
- ✅ Eliminated standalone client scripts

**Completed:** 2025-11-29 (Done as part of Phase 1)

---

### 🔄 Phase 3: Orb Optimization (NEXT)
- [ ] Refactor `XPOrbService` to maintain data-only on server
- [ ] Implement batched replication via RemoteEvent or Attributes
- [ ] Create `OrbVisualsController` for client-side rendering
- [ ] Implement PartCache/pooling for orb visuals
- [ ] Move floating animations to client `RenderStepped`
- [ ] Optimize magnet logic with single server `Heartbeat`

**Status:** Ready to begin

---

### ⏳ Phase 4: Bot Restructuring (FUTURE)
- [ ] Extract `Bot` class from `BotController`
- [ ] Refactor to `BotService` + `Bot` Component pattern
- [ ] Implement time-slicing for pathfinding
- [ ] Add strict type checking (`--!strict`)

**Status:** Pending Phase 3 completion

