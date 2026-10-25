# Tank scenes

Each scene contains one intact model, its matching hidden wreck, editable hull and turret hitboxes, model-specific suspension contacts, and left/right dust emitters. No model selector or runtime model construction is used.

| Model | Player | Enemy | Suspension contacts |
| --- | --- | --- | --- |
| Tank1 | `player/player_tank1.tscn` | `enemy/enemy_tank1.tscn` | 4 |
| TOG2 (tank2) | `player/player_tog2.tscn` | `enemy/enemy_tog2.tscn` | 4 |
| SDKFZ (tank3) | `player/player_sdkfz.tscn` | `enemy/enemy_sdkfz.tscn` | 6 |
| Greydog (tank4) | `player/player_greydog.tscn` | `enemy/enemy_greydog.tscn` | 8 |
| Cat | `player/player_cattank.tscn` | `enemy/enemy_cattank.tscn` | 4 |

Instance a player scene with the root name `playertank` in a gameplay level so enemy targeting continues to find `playertank/vehicle`. Player scenes include their HUD and cameras. The level supplies `BGMusic` and `heightmap`, as before.

The original `scenes/playertank.tscn` is a compatibility wrapper around Greydog, preserving the selection saved before the split. `scenes/enemytank.tscn` wraps the TOG2 enemy. `scenes/enemytankBig.tscn` retains its original, separate boss assembly, including the large tank, attached smaller tanks, and cat. Its scene references connect the original node hierarchy to the shared enemy script. Existing level references retain their scene UIDs.

The `Model/TurretRotation/GunElevation/Muzzle` path is shared by all ten scenes. `TurretCollisionShape` follows turret traverse through `scripts/tank_turret_hitbox.gd`; its shape dimensions are authored in vehicle units. `Wreck` is already aligned and stays hidden until destruction. Suspension positions account for static spring compression so the visible running gear meets a flat floor.

Wheel rolling axes must retain the original orientation: local Z points along vehicle +X (`Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, ...)` in the saved scene). Reversing that axis reverses the applied drive relative to the speed feedback and causes runaway acceleration.

Run `godot --headless --path . --script tests/player_tank_driving.gd --fixed-fps 60` to check all five players with forward, reverse, braking, pivoting, combined input, and lower speed settings. For 120 Hz physics, use `--fixed-fps 120 -- --tick-rate=120`.

## Tank selection

The startup flow is `mainmenu.tscn` → `tank_select.tscn` → `main.tscn`. Click one of the five square tank previews to select it; arrow keys, A/D, and a gamepad also navigate. All five turn slowly under an angled directional light. The selected model pulses from 1.5× to 3× and back every second. The eight stats sit in two columns of four in the bottom panel, with Deploy on the right. Escape returns to the menu. Deploy starts the level with that player scene, retaining the level's spawn transform and target marker.

`scripts/tank_catalog.gd` reads stats from off-tree player scene instances, including scene overrides and script defaults. The previews copy only the intact visual model, so preview tanks never run player physics. Forward/reverse speed is converted from m/s to km/h; aiming rates use degrees per second. Engine power displays the scene's `engine_force_value` setting.

Run `godot --headless --path . --script tests/tank_selection.gd --fixed-fps 60` to check the menu flow, clickable previews, pulse timing, keyboard navigation, stat sources, and deployment of all five tanks with correct enemy/boss targeting.
