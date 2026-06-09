# CLAUDE.md — Big Timber

Project memory for future Claude sessions in this repo. Read this first.

## What this is

A standalone Roblox logging tycoon — **separate game, separate repo** from the
Mechanical Battery tycoon in `C:\Users\ryanv\Roblox`. Never mix the two.

**Repo:** `github.com/ryanultralife/BigTimber` — push to `master`.
**Work tree:** `C:\Users\ryanv\BigTimber`.

## The vision (owner's words — this is the alignment target)

1. **"REALISM I NEED MORE 😂"** — realism is the #1 value. Real machines, real
   process chain, visible cause-and-effect. When choosing between arcade-y and
   realistic, pick realistic (but keep it kid-friendly — his sons play it).
2. **Real logging machines + progression** — "you start with a pickup truck and
   make your way up to a logging truck and same thing with feller bunchers…
   and axes and chainsaws." Tools: axe → chainsaw tiers. Rigs: pickup →
   flatbed → logging truck → feller buncher (skidder/forwarder/loader are the
   intended next additions).
3. **Logging-Inc-style world** — rolling terrain forest, dirt logging roads
   branching through it, the flat yard is the *trailhead* of the dirt network.
4. **The physical loop** — chop → logs drop on the ground → **load them on your
   truck** (park nearby) → drive the paved road → through the tunnel → unload
   at the sawmill (visible saws going **up and down** cutting logs into boards,
   conveyors) → cash. Upgrades are bought from **Big Dale**, an NPC you drive
   past the mill to talk to — NOT from a floating UI panel.
5. **Driving-Empire-style vehicles** — "you drive inside it not on top." Seat
   at driver eye level inside the cab, dashboards, steering wheels, glass.

## How to run

```powershell
.\play.bat    # rojo build + start BigTimber.rbxlx
# or, to land it in Studio's Recents explicitly:
& "$env:LOCALAPPDATA\Roblox\Versions\<current>\RobloxStudioBeta.exe" .\BigTimber.rbxlx
```

Rojo lives at `~/.local/bin/rojo.exe`. The `.rbxlx` is git-ignored. If Studio
shows an Auto-Recovery prompt, click **Ignore**.

## Architecture

```
src/shared/   GameConfig (ALL tunables), Wood (species), Tools (axe tiers),
              Rigs (vehicle tiers), Remotes (all RemoteEvents/Functions)
src/server/   init.server   boot order: World → Forest → ShopNPC → LogService
              World         terrain heightmap (surfaceAt), yard, roads, tunnel,
                            mill structure, shop building
              Forest        choppable trees, HP, physics topple, regrow
              ChopService   swing validation, damage, fell → LogService
              LogService    loose physical logs + truck-proximity loading
              RigService    vehicle spawn/physics (velocity X/Z + AlignOrientation
                            with terrain-normal pitch), per-tier builders,
                            visual log stack, getRigInfo
              MillService   load→cash drain at intake pad + ALL mill animation
                            (sash saw, debarker, carriage, green chain, edger,
                            visible log→boards pipeline)
              Shop          BuyUpgrade validation (tool/rig tracks)
              ShopNPC       Big Dale model + ProximityPrompt → OpenShop
              PlayerData    DataStore profiles (pcall fallback to in-memory)
              Net           snapshot builder + push/notice
              Loadout       held tool prop + server-side swing tween
src/client/   init.client   UI mount, T=call truck, key hints
              ToolController hold-click chop loop (camera ray, char excluded)
              UI/Hud        cash/load/tool/rig panel
              UI/Shop       Big Dale dialog modal (opens via Remotes.OpenShop)
              NoticeToast   server notices as top-centre toasts
```

## Conventions

- **Strict Luau, tabs.** File-top comment explaining the module's role.
- **Every tunable lives in `GameConfig.luau`.** No magic numbers in services.
- **Server is authoritative** — client sends intents, server validates.
- **Vehicle forward = –Z.** All rig builders put the cab at –Z, bed at +Z,
  matching VehicleSeat's default LookVector. Never rotate the seat.
- **Roblox cylinders' axis = X.** Stand upright: `CFrame.Angles(0,0,π/2)`.
  Lay along Z (truck-bed logs): `CFrame.Angles(0,π/2,0)`.
- **Animation = cached base CFrame × offset(t).** Never multiply onto the
  current CFrame each frame — it compounds and the part spins up forever.

## Gotchas (each one bit us already)

- **`part.Parent` is a property, NOT a method.** `mp({...}):Parent(model)`
  crashes at runtime ("attempt to call"). One bad builder line killed the
  whole server boot once — World.build errors abort init.server, so no
  trees/rigs/NPC spawn. Always `local p = mp({...}); p.Parent = model`.
- **Terrain grid is offset from x=0.** Cells are 16 wide centred at
  `-HalfExtent + k·16`; with HalfExtent=620 the centres near the road are
  x=-12 and x=4 — NOT 0. The tunnel corridor must be flattened with a
  half-cell margin (`|x| > RoadHW + CellSize/2` raises rock) and the tunnel
  tube parts are centred at x=-4. Touch `Terrain.HalfExtent` and you must
  re-derive TUNNEL_CX in World.buildTunnel.
- **Unload detection must be centred on the visible pad** —
  `Mill.Position + Mill.IntakePadOffset` — not on Mill.Position.
- **DataStore throws at module load** unless the place is published or
  Studio API access is on. Already pcall-wrapped; don't remove it.
- **Sounds are placeholder built-ins** (`rbxasset://sounds/snap.mp3` pitched
  down for chops/creaks). A real audio pass (chainsaw idle/rev, saw whine,
  diesel engines) is wanted — needs curated asset IDs, don't guess them.
- **WeldConstraints + anchored parts:** moving an anchored trunk does NOT
  move welded anchored leaves. Trees only move as one body once unanchored.

## Current loop (post vision-alignment pass)

Chop (hold click; swing anim + chips + knock) → tree physics-topples with a
creak → 2-9 physical logs scatter at the stump (owner-tagged, despawn 180s)
→ park your rig within 16 studs → logs hop aboard, stack visibly, HUD load
ticks up → drive south on the paved road, through the lit tunnel under the
ridge → park on the mill's green intake pad → load drains to cash while the
sash saw strokes up/down, the carriage rides logs through the blade, sawdust
bursts, boards travel the green chain → keep driving south to Big Dale's,
press E at the counter → buy the next axe/chainsaw or truck tier.

## Roadmap (vision-ordered, not started)

1. **More machines:** skidder (drags single big logs on a winch — pairs with
   making redwood logs too heavy for early trucks), forwarder, knuckleboom
   loader at the mill, delimber.
2. **Audio pass** with real assets (chainsaw, diesel, mill whine).
3. **Wheel spin + engine pitch** while driving; suspension feel.
4. **Truck shape pass** (wedge hoods, cab chamfers) once the owner reviews
   the current interiors.
5. **Growing board stacks / lumber yard economy** at the mill.
6. **Multiplayer plots** (one forest sector per kid) + DataStore for forest
   state if needed.
7. **Mini-games:** perfect-fell direction bonus, sharpen-the-saw timing.

## Owner's workflow

He playtests with his kids and reports back in casual language ("the truck is
floating", "i cant chop"). Bugs come from real play sessions — treat every
report as reproducible truth and find the mechanical cause. After changes:
rojo build, open the .rbxlx in Studio, commit, push.
