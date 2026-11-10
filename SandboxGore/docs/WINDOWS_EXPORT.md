# Windows Desktop export (x86_64, Jolt Physics)

How to turn this project into a Windows build, what ends up in the build, and what to watch
for. Everything here was exercised with Godot 4.7.2 stable on a Linux host; see
[Verification status](#verification-status) for what that does and does not cover.

## What ships

| File | Size | Purpose |
| --- | --- | --- |
| `SandboxGore.exe` | 104 MiB | Godot 4.7.2 release template (PE32+, x86-64) with the product name and version written in |
| `SandboxGore.pck` | 0.2 MiB | Scripts, the main scene and the project settings |
| `SandboxGore.console.exe` | 54 KiB | Debug exports only: wrapper that shows the log in a console |

There are no DLLs. Distribute the `.exe` and the `.pck` side by side, with the same base name.

## Jolt Physics packaging

Jolt has been an engine module since Godot 4.4. It is compiled into the editor and into every
official export template, so a build needs no plugin, no `addons/` folder and no `godot-jolt`
DLL. One line in `project.godot` selects it:

```ini
[physics]

3d/physics_engine="Jolt Physics"
```

Two things are easy to get wrong:

- **Key and value are both exact.** `physics/3d/engine = "Jolt3D"` is not a setting Godot
  reads. An unknown *value* in the real key is not reported either: with
  `3d/physics_engine="Jolt3D"`, Godot 4.7.2 starts without any warning and simulates with
  Godot Physics. The test `test_a_jolt_is_the_active_physics_engine` catches that. It probes a
  documented difference between the engines (a ray hit on a trimesh reports `face_index` -1
  under Jolt) instead of trusting the setting.
- **The Godot Jolt GDExtension is something else.** It is the older integration, now in
  maintenance mode, selected as `Jolt Physics (Extension)`. It ships native libraries under
  `addons/godot-jolt/`, which an export copies next to the executable and which then have to
  be distributed with it. This project does not use it.

The Jolt behaviour the code depends on is listed in
[ARCHITECTURE.md](ARCHITECTURE.md#jolt-specifics).

## 1. Tooling

- Godot **4.7.2 stable**, standard build. The project is GDScript only; the .NET build, with
  its own export templates, is needed only if C# scripts are added.
- Export templates of exactly the same version (next step).

Nothing else is required. Godot 4.7.2 writes the icon and version resources itself, so
neither rcedit nor Wine is involved.

## 2. Export templates

In the editor: **Editor → Manage Export Templates → Download and Install**.

From a shell (Linux shown). The archive is 1.2 GiB and covers every platform; only the
Windows x86_64 files are needed here:

```sh
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
dest="$HOME/.local/share/godot/export_templates/4.7.2.stable"
mkdir -p "$dest"
unzip -o -j Godot_v4.7.2-stable_export_templates.tpz \
    'templates/version.txt' 'templates/windows_*x86_64*' -d "$dest"
```

| Host | Template directory |
| --- | --- |
| Linux | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| Windows | `%APPDATA%\Godot\export_templates\4.7.2.stable\` |
| macOS | `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` |

The directory name has to match the editor version exactly.

## 3. The preset

`export_presets.cfg` is committed and holds one preset, **Windows Desktop**:

| Option | Value | Effect |
| --- | --- | --- |
| `binary_format/architecture` | `x86_64` | Target architecture |
| `binary_format/embed_pck` | `false` | `.pck` next to the `.exe`; `true` gives a single file |
| `export_filter`, `exclude_filter` | `all_resources`, `tests/*` | Ships `src/` and `main.tscn`, leaves the test scenes out |
| `script_export_mode` | `2` | GDScript is exported as compressed binary tokens |
| `debug/export_console_wrapper` | `1` | Console wrapper for debug exports only |
| `application/modify_resources` | `true` | Product name, description and version 0.1.0.0 in the exe |
| `codesign/enable` | `false` | The build is unsigned |

`docs/` carries a `.gdignore`, so nothing in it is imported or exported.

## 4. Export

Scripted, which is also what a CI job should call:

```sh
tools/export_windows.sh          # release build in build/windows/
tools/export_windows.sh debug    # debug build with the console wrapper
```

The script checks that the template is installed, refreshes the import cache, exports, and
fails if the `.exe` or the `.pck` was not written. `GODOT=/path/to/godot` selects the editor
binary. `GODOT_TEMPLATES=/path/to/export_templates` selects the template root, which is needed
on Windows and macOS hosts because the default is the Linux location.

By hand:

```sh
godot --headless --path . --import
godot --headless --path . --export-release "Windows Desktop" build/windows/SandboxGore.exe
```

The `--import` pass is not optional on a fresh clone. `.godot/` is not committed and holds the
`class_name` registry; without it the scripts cannot resolve each other.

From the editor: **Project → Export… → Windows Desktop → Export Project**.

## 5. Check the result

Sizes are those of the 0.1.0 build:

```console
$ ls -l build/windows
109132800 SandboxGore.exe
   217092 SandboxGore.pck
$ file build/windows/SandboxGore.exe
SandboxGore.exe: PE32+ executable (GUI) x86-64 (stripped to external PDB), for MS Windows, 12 sections
```

Before the build goes to a Windows machine, the pack can be booted with the editor binary on
the build host. That catches resources the export filter left out:

```sh
godot --headless --main-pack build/windows/SandboxGore.pck --quit-after 300
```

Expect the engine banner only, and exit status 0.

## 6. On the Windows machine

- 64-bit Windows 10 or newer.
- A GPU with Vulkan support and current drivers: the project uses the Forward+ renderer and
  Vulkan is the default driver. The templates also contain the Direct3D 12 driver, so
  `SandboxGore.exe --rendering-driver d3d12` is the first thing to try where Vulkan fails.
- No installer and no runtime to install; start `SandboxGore.exe`.
- The release build is a GUI program and prints nothing to a terminal. The log is written to
  `%APPDATA%\Godot\app_userdata\SandboxGore\logs\godot.log`; the debug export adds
  `SandboxGore.console.exe`, which shows it live.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| The export stops because a template is missing | Templates are not installed or belong to another version; the directory must be named `4.7.2.stable` |
| Scripts fail to parse when the project is run from a shell | No import cache yet, or a new `class_name` script: run `godot --headless --path . --import` |
| Ragdolls and joints behave differently in the build | Check `3d/physics_engine`, then run the tests, which fail when Jolt is not the active engine |
| SmartScreen warns on first launch | The exe is unsigned. Signing is configured under `codesign/*` in the preset and needs a certificate |
| A CI job hangs on the tests | A test script that fails to parse leaves the engine idling; wrap the run in `timeout` |

## Performance guidance

Blood and giblets create no nodes while the game runs. Every decal, particle emitter and
giblet comes from a fixed-size ring built at startup, and the oldest one is recycled when a
ring is full, so node count, memory and draw cost stay flat however long a session lasts.

| Resource | Budget | Defined in |
| --- | --- | --- |
| Blood, bullet-hole and scorch decals | 320 `Decal` nodes | `BloodFX.DECAL_CAPACITY`, `DecalRingPool` |
| Blood bursts | 40 emitters of 40 particles | `BloodFX._ready`, `ParticleRingPool` |
| Debris bursts | 16 emitters of 24 particles | `BloodFX._ready`, `ParticleRingPool` |
| Giblets | 96 rigid bodies | `GibPool.capacity` |
| Arterial spurts | 30 per second for the whole scene, 3 per heartbeat per body | `BloodFX.SPURTS_PER_SECOND`, `GoreComponent.MAX_SPURTS_PER_BEAT` |
| Bleeding wounds | 24 per body | `VitalsComponent.MAX_WOUNDS` |
| Tracers | 32 | `Ballistics.TRACER_COUNT` |
| Positional sounds | 16 players | `Sfx.PLAYERS` |

What to keep in mind when changing them:

- **Decals share a renderer budget.** Forward+ clusters at most 512 elements per view
  (`rendering/limits/cluster_builder/max_clustered_elements`), and decals, omni lights, spot
  lights and reflection probes all count. 320 decals leave room for lights; raise both numbers
  together or decals start to drop out.
- **A pool is one decal, a trail is many.** A bleeding body feeds a single decal that grows up
  to 1 m in radius. Drips, smears and splatter each take a slot, so a long drag through blood
  is what turns the ring over fastest. The HUD shows the live count (`Decals n / 320`).
- **Giblets stop simulating.** A giblet is frozen once it sleeps, has left its stains or is
  20 s old. Two things are not pooled, and both are small and bounded: a severed joint gets
  two stump caps, and a glass pane makes 14 shards that are freed after about 6 s.
- **Bodies are the physics cost.** One humanoid is 14 `PhysicalBone3D` bodies with 13 joints.
  The 11 organ volumes are areas that only ballistic rays query, so they add no contacts.
  Bodies are never removed automatically: delete them with the toolgun or restart with F5.
- **Physiology runs at 20 Hz**, not every physics tick (`VitalsComponent.tick_interval`).
- **Ballistics is ray queries only.** A shot is at most 12 surface crossings per trace. A
  shotgun shell is 9 traces, a grenade 96 fragment traces in one frame and a barrel 48.
- **The particle collision heightfield** in `Main.gd` covers 80 x 80 m at the highest
  resolution and is re-rendered every frame so props are included. It is the first thing to
  lower on a weak GPU.
- **Ship the release export.** The debug template keeps script debugging and is slower.

These are budgets, not benchmarks: see below.

## Verification status

Done for the 0.1.0 build, with Godot 4.7.2 on Linux:

- Headless release and debug exports complete without warnings or errors and produce the
  files listed above.
- The executable is a PE32+ x86-64 image and carries the product name and version.
- The exported pack boots under the 4.7.2 editor binary and runs 300 frames without errors.
- The integration tests pass against the same sources, including the Jolt check.

Not done:

- The executable has not been started on Windows. An attempt under Wine in the build sandbox
  failed inside Wine before the engine started, so it says nothing about the build.
- Frame rates have not been measured on GPU hardware; development used a software renderer.
- Code signing and the single-file (`embed_pck`) variant were not exercised.
