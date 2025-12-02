# Performance & Architecture Audit Report

**Date:** 2025-05-24
**Target:** Core Gameplay Scripts (Combat, AI, Entities)
**Scope:** Performance, Memory, Engine Specifics, Data Structures

## Executive Summary
The codebase generally follows good modular practices, but several critical hotspots are causing the reported "stuttering" and "hitbox registration" issues. The most significant bottlenecks are O(N^2) complexity in entity loops (Bots/Orbs) and a fundamental flaw in the weapon hit verification logic causing RNG desync between client and server.

---

## 1. Critical Issues Analysis

### 🚨 Hit Registration Failures ("Ghost Bullets")
**Severity:** Critical
**Source:** `src/ServerScriptService/Blaster/Scripts/Blaster/init.server.luau` vs `BlasterController.luau`

*   **The Problem:** The Client calculates a random spread vector and visually confirms a hit. The Server receives the shoot event and *re-calculates* a new random spread vector using a new random seed.
*   **Result:** The Client sees a hit, but the Server calculates a miss (due to RNG divergence). The `tagged` list sent by the client is effectively ignored for hit validation.
*   **Fix Recommendation:**
    1.  **Seed Synchronization:** Client generates a seed (or uses timestamp), sends it to server. Server uses `Random.new(seed)` to generate the *exact same* spread vector.
    2.  **Hybrid Validation:** Server should perform a validation spherecast against the `tagged` targets sent by the client to confirm they are reasonably close to the fire trajectory, rather than blindly re-casting.

### 📉 Stuttering & Frame Drops
**Severity:** High
**Source:** `BotService.luau`, `XPOrbService.luau`, `BlasterController.luau`

*   **Issue 1 (Bot AI):** `findNearestEnemy` in `BotService` runs an O(N) scan for *every* bot. In a lobby with 50 bots, this becomes 50 * 50 = 2,500 distance checks per AI tick.
*   **Issue 2 (Orb Magnetism):** `XPOrbService` iterates *all* active orbs and, for each orb, iterates *all* players to find magnet targets. This is O(Orbs * Players) running on `Heartbeat` (60 times/sec).
*   **Issue 3 (Network Serialization):** `BlasterController` sends a dictionary of `{[string]: Humanoid}` to the server on every shot. Serializing Instances over the network is heavier than sending IDs, especially for rapid-fire weapons.

---

## 2. Server-Side Optimization Findings

### `Services/Combat/BotService.luau`
*   **Time Complexity:** O(N^2) in `findNearestEnemy`.
    *   *Impact:* High FPS drop as bot count increases.
    *   *Fix:* Use a spatial partitioning system (e.g., Octree or Grid) or `CollectionService:GetTagged` with a periodic "Target Cache" so not every bot searches every frame.
*   **Memory Thrashing:** `RaycastParams.new()` is created inside the `handleCombat` and `moveToPath` functions.
    *   *Impact:* High GC pressure.
    *   *Fix:* Create a single reusable `RaycastParams` object at the module level or per-bot state and update its Filter list.
*   **Engine Specifics:** `PathfindingService:ComputeAsync` is called frequently.
    *   *Impact:* Engine throttling if called too often.
    *   *Fix:* Implement a "Path Request Queue" to limit path computations to X per frame.

### `Services/World/XPOrbService.luau`
*   **Time Complexity:** O(N*M) in `updateOrbs` (Magnet Logic).
    *   *Impact:* Server Heartbeat lag.
    *   *Fix:* Invert the loop. Iterate Players once, find nearby Orbs (using spatial hash), and apply pull. Or only check for magnets every 10 frames, not every frame.
*   **Optimization Win:** The "Virtual Orb" system (data-only, no Parts) is excellent and saves significant physics overhead.

### `Services/World/ScalingEngineService.luau`
*   **Memory:** `Instance.new("ParticleEmitter")` in `UpdateCharacter`.
    *   *Impact:* Low, but checks `FindFirstChild` every update.
    *   *Fix:* Ensure `UpdateCharacter` is debounced and not called on every frame of biomass gain (e.g., update visuals only when scale changes by > 1%).

### `Blaster/Scripts/Blaster/init.server.luau`
*   **Code Quality/Perf:** Frequent `require` inside the `onShoot` handler (e.g., `task.spawn(function() require(...).OnDamage end)`).
    *   *Impact:* Unnecessary overhead per shot.
    *   *Fix:* Require modules at the top of the script.

---

## 3. Client-Side Optimization Findings

### `StarterPlayerScripts/Controllers/BlasterController.luau`
*   **Network:** `shootRemote:FireServer` sends complex tables of Instances.
    *   *Impact:* Bandwidth usage and deserialization cost.
    *   *Fix:* Send a lightweight packet (Origin, Direction, RandomSeed). Let the server trust the seed for trajectory.
*   **Render:** `drawRayResults` creates new cosmetic parts/beams.
    *   *Impact:* Frame time spikes on rapid fire.
    *   *Fix:* Ensure `PartCache` or `ObjectPooling` is used for all visual effects (bullet trails, hit markers).

### `StarterPlayerScripts/Controllers/MovementController.luau`
*   **Physics:** Direct modification of `AssemblyLinearVelocity` for sliding.
    *   *Impact:* potential physics conflict if other scripts also set velocity. Generally acceptable, but `ApplyImpulse` or `VectorForce` is often smoother for networking.

---

## 4. Summary of Ratings

| File / System | Issue Type | Severity | Potential FPS Impact |
| :--- | :--- | :--- | :--- |
| **Blaster Hit Reg** | Logic Error | **Critical** | N/A (Gameplay Broken) |
| **XPOrbService** | Time Complexity | High | -5 to -10 FPS (Server) |
| **BotService** | Time Complexity | High | -10 to -20 FPS (Server) |
| **Blaster Net** | Bandwidth/CPU | Medium | Minor Stutter |
| **RaycastParams** | Memory Thrashing | Medium | Micro-stutters (GC) |
| **Lazy Requires** | CPU Overhead | Low | Negligible |

## 5. Recommended Action Plan

1.  **Fix Hit Reg:** Implement "Seeded Randomness" for weapon spread. Client sends Seed; Server uses same Seed. This guarantees the server calculates the *exact same* bullet path as the client.
2.  **Optimize Bot Vision:** Replace `findNearestEnemy` with a bucketed search (bots only search for enemies every 1-2 seconds, not every frame) or use a spatial grid.
3.  **Optimize Magnets:** Move Orb magnet logic to run fewer times per second, or invert the loop to be Player-centric.
4.  **Pool Objects:** Verify `DamageNumberController` and `BlasterController` visual effects utilize `PartCache` or similar pooling solutions.
