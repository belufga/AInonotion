# SandboxGore architecture

SandboxGore is a Godot 4.7 prototype of a first-person gore and physics sandbox, written in
GDScript. Everything is built in code: apart from the one-node `main.tscn` the project has no
scenes, meshes, textures or sounds. This document describes how the systems are divided, how a
hit travels through them, and where the model is deliberately approximate.

## Layout

| Path | Contents |
| --- | --- |
| `src/core/` | `Layers` (physics and render masks), `BallisticMaterial` (penetration table), `PIDController`, `Sfx` |
| `src/damage/` | `DamageInfo`, `HealthComponent`, `HitboxComponent`, `OrganVolume3D`, `VitalsComponent`, `Wound`, `Anatomy` |
| `src/npc/` | `Humanoid`, `HumanoidRig`, `ActiveRagdoll`, `ProceduralAnimator`, `NPCBrain` |
| `src/gore/` | `BloodFX`, `DecalRingPool`, `ParticleRingPool`, `GibPool`, `Gib`, `BloodTextures`, `StumpCap`, `GoreComponent` |
| `src/weapons/` | `WeaponBase3D`, `Pistol`, `Shotgun`, `AK47`, `FragGrenade`, `GrenadeProjectile`, `BallisticsComponent`, `Ballistics`, `BallisticsRaycaster`, `BallisticShot`, `Caliber`, `Explosion`, `WeaponModels`, `WeaponPickup` |
| `src/tools/` | `Toolgun`, `RadialMenu`, `SpawnCatalog` |
| `src/player/` | `Player`, `HUD` |
| `src/world/` | `Main`, `PropFactory`, `ExplosiveBarrel`, `BreakableGlass` |
| `tests/` | `TestRunner` (headless integration tests), `ScreenshotTour` (scripted visual tour) |
| `tools/export_windows.sh` | Headless Windows export, see [WINDOWS_EXPORT.md](WINDOWS_EXPORT.md) |

`BloodFX`, `Ballistics` and `Sfx` are autoloads.

## Runtime scene tree

```
root
├── BloodFX        autoload: Decals (320), BloodParticles (40), DebrisParticles (16), Gibs (96)
├── Ballistics     autoload: shots in flight, tracer ring
├── Sfx            autoload: synthesised sounds
└── Main           src/world/Main.gd
    ├── WorldEnvironment, DirectionalLight3D, GPUParticlesCollisionHeightField3D
    ├── Floor, walls, cover, platform      static bodies from PropFactory
    ├── Entities                           group "entity_container": everything spawned or removable
    │   ├── Humanoid x 9
    │   └── crates, barrels, glass and other props
    └── Player                             CharacterBody3D
        ├── Camera3D
        │   └── Hand
        │       ├── Toolgun
        │       ├── Pistol ── BallisticsComponent
        │       ├── Shotgun ── BallisticsComponent
        │       ├── AK47 ── BallisticsComponent
        │       └── FragGrenade
        └── HUD                            crosshair, readouts, RadialMenu
```

A humanoid is composed in `Humanoid._ready`:

```
Humanoid                                   groups "sandbox_entity" and "npc"
├── HealthComponent
├── VitalsComponent
├── Rig                                    HumanoidRig
│   ├── Skeleton                           simulated pose
│   │   └── PhysicalBoneSimulator
│   │       └── Bone<Part> x 14            PhysicalBone3D on the Body layer
│   │           ├── collision shape and primitive meshes
│   │           ├── HitboxComponent
│   │           └── organs                 OrganVolume3D on the Organs layer
│   └── AnimRig                            target pose
├── ActiveRagdoll
├── ProceduralAnimator
├── GoreComponent
└── NPCBrain
```

The 14 parts are Hips, Spine, Chest and Head, plus left and right UpperArm, LowerArm, UpperLeg,
LowerLeg and Foot. The 11 organ volumes are the brain, the heart, two lungs, the liver, and the
carotid, brachial and femoral arteries on each side. Shapes, masses, joint limits, motor gains,
hitbox layers and organs all come from one table, `Anatomy.humanoid()`.

## Components

| Component | Type | Role |
| --- | --- | --- |
| `HealthComponent` | `Node` | Structural hit points. Decides when props, barrels and glass break; on a humanoid it is only a coarse whole-body trauma budget |
| `VitalsComponent` | `Node` | Physiology of one humanoid: blood volume, pressure, heart rate, oxygen saturation, pain, consciousness and cause of death |
| `OrganVolume3D` | `Area3D` | A vital organ or major artery inside a body part. Only ballistic queries can hit it; trauma becomes the matching failure in `VitalsComponent` |
| `HitboxComponent` | `Node` under each bone | Layered damage model of one body part for projectiles, blunt impacts and blast. Emits signals and spawns nothing |
| `BallisticsComponent` | `Node` under each firearm | Projectile emitter: the round, the pellets per shot and the hitscan range |
| `BallisticsRaycaster` | static functions | Penetrating tracer shared by bullets, pellets and shrapnel |
| `Ballistics` | autoload | Hybrid hitscan and projectile service; owns the shots in flight and the tracers |
| `GoreComponent` | `Node` | Turns the damage model's events into blood, and performs severing and gibbing |
| `ActiveRagdoll` | `Node` | Joint motors and balance for the physical skeleton |
| `ProceduralAnimator` | `Node` | Writes the target pose the motors chase |
| `NPCBrain` | `Node` | Behaviour state machine. Sets strengths and targets and never moves a bone |

Components find each other through their owner, never through the scene path: `Humanoid`
creates them, hands each one what it needs, and connects their signals.

## How a hit travels

1. **Trigger.** `WeaponBase3D` handles the fire mode, ammunition, spread and recoil, then
   calls `BallisticsComponent.fire`. That creates one `BallisticShot` per pellet from the
   round's `Caliber`: mass, muzzle velocity and diameter, with energy derived from them.
2. **Flight.** `Ballistics.fire` resolves the shot at once out to the weapon's hitscan range
   (pistol 40 m, shotgun 35 m, rifle 60 m). A shot that is still alive is then simulated: every
   physics tick it is pulled down by gravity, slowed by quadratic air drag and swept along its
   path, until it stops, falls below 50 m/s or has flown for 4 s.
3. **Penetration.** Both phases use `BallisticsRaycaster.trace`. It follows the shot surface
   by surface on the World, Props and Body layers, measures each solid with a reverse ray and
   lets the surface's `BallisticMaterial` remove energy for that thickness
   (`dE/dx = -(drag * A/m * E + strength * A)`). What is left carries on from the far side, for
   up to 12 surfaces. Rigid bodies receive the momentum that was lost.
4. **Anatomy.** A body part hands the shot to its `HitboxComponent`, which resolves skin, bone
   shell (skull, ribs, pelvis), muscle, organs or the bone core, and the same layers again on
   the way out. Rifle rounds yaw in tissue and dump energy, which widens the exit wound. The
   outcome is a `DamageInfo`, entry and exit `Wound`s, and possibly a fracture, a destroyed
   joint or a request to sever the part.
5. **Organs.** An `OrganVolume3D` crossed by the path damages the brain, the heart or a lung
   in `VitalsComponent`, or opens an arterial or venous bleed.
6. **Physiology.** `VitalsComponent` ticks at 20 Hz. Wounds drain blood; volume sets preload;
   preload, heart function and heart rate set pressure; pressure, oxygen saturation and
   haemoglobin set cerebral perfusion; perfusion decides consciousness: awake, stunned,
   unconscious or dead. Rates are compressed to about eight times real speed.
7. **Reaction.** `Humanoid` routes the events. `NPCBrain` stumbles or drops the body according
   to the energy that arrived within 0.15 s, goes limp when consciousness is lost and crawls
   when the legs no longer carry. Limbs with a fracture, a destroyed joint or an amputation
   lose their motors, and an armed NPC drops its rifle. `GoreComponent` shows the wounds.

Two other sources enter the same model at step 4. Blunt trauma comes from `ActiveRagdoll`,
which sums the contact impulses on each bone and passes anything above 20 N s to
`HitboxComponent.apply_blunt`. Blast comes from `Explosion`, through
`HitboxComponent.apply_blast`.

Materials are `concrete`, `wood`, `metal`, `glass`, `rubber`, `flesh` and `bone`. A collider
names its material in the `surface` metadata, and hollow props give their wall thickness in
`wall`.

## Active ragdoll

`HumanoidRig` builds two skeletons from the anatomy table. `Skeleton` carries the
`PhysicalBone3D` bodies and their 6DOF joints; `AnimRig` only holds a target pose.

- `ProceduralAnimator` writes that pose every tick: idle breathing, a walk cycle driven by the
  actual forward speed, weapon aiming, cowering and prone crawling. An `AnimationPlayer` could
  drive the same skeleton without touching the ragdoll code.
- `ActiveRagdoll` drives each joint toward the pose with an angular spring-damper. The step is
  integrated implicitly at velocity level and applied to the whole limb below the joint as one
  rigid rotation, so stiff motors stay stable at 60 Hz whatever the mass ratios, and a torque
  limit keeps every joint overpowerable. A second controller balances the body: an upright
  servo on the pelvis and a virtual-leg support force under it.
- Scaling `motor_strength` and `balance_strength` to zero turns the same rig into a passive
  ragdoll. `NPCBrain` does exactly that, per state: Idle, Wander, Aim, Stumble, Cower, Crawl,
  Ragdoll, Get up and Dead.

## Gore

`GoreComponent` listens to the hitboxes and to `VitalsComponent`. It places wound marks that
travel with the bone, blood bursts, arterial spurts timed by the heartbeat signal and scaled by
systolic pressure, drips for every 10 ml lost, and pools that grow.

Dismemberment is decided by the damage model and carried out here. `HitboxComponent` adds up
the trauma a part takes within 0.25 s; past the part's threshold (700 J for a forearm, 2100 J
for the head, or the matching blast pressure) it requests a sever. `GoreComponent.sever` opens
the joint, caps both sides with a `StumpCap` (a procedural cross-section with a bone stub),
limits how fast the limb may leave, and adds an arterial stump wound. `GoreComponent.gib`
handles explosions: every limb comes off and the torso is reduced to giblets.

All effects go through the `BloodFX` autoload (`blood_splat`, `blood_burst`, `arterial_spurt`,
`project_splatter`, `wound_mark`, `drip`, `surface_impact`, `scorch` and others). It owns the
pools: a ring of 320 decals, two rings of particle emitters and 96 giblets. The budgets and the
reasoning behind them are in [WINDOWS_EXPORT.md](WINDOWS_EXPORT.md#performance-guidance).

## Weapons and explosions

`WeaponBase3D` is the base of everything the player holds. It provides the procedural
viewmodel (hip and aim-down-sights poses, a recoil spring, sway, bob, reload dip), fire modes,
magazines, spread and the recoil and shake requests to the wielder. Subclasses set the exported
values in `_init` and override hooks; a firearm returns its emitter from `_make_ballistics`.

| Weapon | Round | Magazine / reserve | Action |
| --- | --- | --- | --- |
| Tactical Pistol | 9x19 mm, 8 g at 360 m/s, 518 J | 17 / 102 | Semi-automatic |
| Pump Shotgun | 12 ga 00 buck, 9 pellets of 3.5 g at 380 m/s, 253 J each | 6 / 48 | Pump, 0.55 s cycle, shells loaded one by one |
| AK-47 | 7.62x39 mm, 7.9 g at 715 m/s, 2019 J | 30 / 180 | Automatic, 600 rpm |
| M67 Frag Grenade | 0.23 kg TNT equivalent, 96 traced fragments | 1 / 7 | Pin, spoon and a 3.5 to 4.0 s fuse; can be cooked |

`Explosion.detonate` has three parts. The shockwave takes its peak overpressure from
Sadovsky's free-air formula, pushes every body in range and applies blast trauma; solid cover
between the charge and a target takes most of it. Shrapnel is traced with the same raycaster
as bullets. Humanoids whose torso is inside the lethal radius are gibbed. Barrels use the same
function with a larger charge, and a short random delay staggers chain reactions.

## Toolgun

`Toolgun` is a `WeaponBase3D` with a beam of 80 m and six modes:

| Mode | Primary | Secondary |
| --- | --- | --- |
| Grab | Hold a body with a PID-tracked force at the grabbed point; wheel pushes and pulls, E + mouse rotates | Freeze it in place |
| Freeze | Toggle a body static | Unfreeze |
| Weld | Pick two bodies to join with a `Generic6DOFJoint3D` | Remove the target's joints |
| Pin | Pick two bodies, or a body and the world, to join with a `PinJoint3D` | Remove the target's joints |
| Spawn | Create the selected `SpawnCatalog` entry on the aimed surface | Delete the target |
| Remove | Delete the target | Delete the target |

Ragdoll bones are valid targets in every mode. Grabbing a limb makes the NPC go limp while it
is held, and removing any bone removes the whole NPC.

## Physics layers

| Layer | Name | Used by |
| --- | --- | --- |
| 1 | World | Static level geometry |
| 2 | Props | Dynamic bodies, vehicles, breakables |
| 3 | Player | The player capsule |
| 4 | Body | Ragdoll bones: the skin layer of the hitbox model |
| 5 | Organs | `OrganVolume3D` areas |
| 6 | Gibs | Giblets |
| 7 | Projectiles | Thrown grenades |

Ballistic rays query World, Props and Body. The toolgun beam also sees Gibs and Projectiles.

## Jolt specifics

The project runs on Jolt Physics (`3d/physics_engine="Jolt Physics"`), and a few decisions
follow from how Jolt behaves in Godot 4.7:

- Setting `PhysicalBone3D.joint_type` to `NONE` leaves the old constraint alive in the physics
  server. `HumanoidRig.detach` therefore opens the 6DOF joint on every axis instead.
- Jolt ignores the soft-limit parameters of the joint nodes (softness, restitution, damping,
  ERP). Joint limits are hard stops; all compliance comes from the ragdoll motors.
- Contact impulses reported by Jolt are estimates made ahead of the solve. The blunt trauma
  thresholds were tuned against those numbers.
- A ray hit reports `face_index` -1 by default. The tests use that to prove Jolt is the engine
  actually running, because an unknown engine name falls back to Godot Physics silently.

## Tests

`tests/TestRunner.gd` runs 22 scenarios with 117 checks against the real systems, headless:

```sh
godot --headless --path . --import      # once per clone, and after adding a class_name script
godot --headless --fixed-fps 60 --path . res://tests/TestRunner.tscn
godot --headless --fixed-fps 60 --path . res://tests/TestRunner.tscn -- grenade   # name filter
```

The exit status is 0 only when every check passes. With `--fixed-fps 60` the run takes a few
seconds and is repeatable. The scenarios cover: scripts compile, Jolt is active, standing and
walking, head, heart, lung and femoral trauma, a crippled leg, weapon drop, buckshot
dismemberment, penetration by material, exit wounds, bullet drop, the grenade, a barrel chain
reaction, the decal ring, blunt trauma, the firearms and the grenade through the player, the
toolgun and wheels, and the main scene.

`tests/ScreenshotTour.gd` plays a fixed sequence in the main scene and saves 13 screenshots for
visual review. It needs a display.

## Extending

- **Round:** add a preset to `Caliber` from mass, velocity and diameter.
- **Weapon:** subclass `WeaponBase3D`, set the exported values in `_init`, return a
  `BallisticsComponent` from `_make_ballistics`, add a model to `WeaponModels` and add the
  class to the list in `Player._ready`.
- **Material:** add a row to `BallisticMaterial` and tag colliders with the `surface` metadata.
- **Organ or body part:** add an entry to `Anatomy.humanoid()`; a new organ function also needs
  an `OrganVolume3D.Kind` and its handling in `VitalsComponent`.
- **Spawnable:** add an entry to `SpawnCatalog.ITEMS` and a case to `SpawnCatalog._create`.

## Known approximations

- Bodies are capsules, boxes and ellipsoids, and organs are spheres and capsules. There is no
  skinned mesh.
- The ragdoll motors rotate the limb below a joint without reacting on the parent, and balance
  is an upright servo with a support force. There is no foot placement or step recovery.
- The physiology is time-compressed and tuned for play. It is not clinically validated.
- Momentum transfer from bullets and blast is exaggerated on purpose (`Caliber.impulse_scale`,
  `Explosion.IMPULSE_GAIN`).
- Armed NPCs turn, aim and drop their weapon when the arm is hit, but they do not shoot.
- Sound is synthesised at startup; there are no audio assets.
- There is one hand-built test range and no saving.
