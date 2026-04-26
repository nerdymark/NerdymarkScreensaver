# Nerdymark Demoscene ScreenSaver

A native macOS screensaver bundling **52 generative scenes** — plasma fields, cellular automata, demoscene effects, fractals, particle systems, agent simulations, optical illusions, and auto-playing classic games. All scenes are pure Swift + Core Graphics; no JavaScript, no WebView, no Metal shaders required.

Built as a `.saver` bundle that hosts a `ScreenSaverView` subclass with a modular scene protocol and a programmatic configure sheet for tuning every scene's individual parameters.

## What's in the bundle

A non-exhaustive sampling:

- **Plasma family** — classic, spiral, diamond, ripple variants
- **Demoscene** — copper bars, raster bars, sine scroller, glenz vectors, Mode 7 floor, rotozoomer, vector balls, hypercube, tunnel, C64 demo composite
- **Cellular & generative** — Game of Life, Reaction-Diffusion (Gray-Scott), Voronoi cells, Truchet tiles, Mandelbrot zoom, recursive maze
- **Particle / agent sims** — flocking fish, bug swarm, slime mold (Physarum), vector field flow, falling sand, blizzard, bubbles, lava lamp
- **Optical illusions** — Scintillating Grid, Simultaneous Contrast, Afterimage
- **Throwbacks** — Win95-style 3D Pipes, bouncing DVD logo, screensaver Snake (A* pathfinding), Tetris auto-play, search light, lens flare, Rubik's cube
- **Auto-playing games** — Pong AI vs AI, Tron light cycles
- **Eye candy** — Synthwave grid, Aurora Borealis, fractal trees, parallax mountains, constellation maker, ripple tank, Celtic braid, flag wave (Pride / Trans / USA / Palestine / Ukraine)

Every scene exposes its own knobs through the standard macOS Screen Saver "Options" sheet. Several scenes (Bouncing Logo, Sine Scroller, C64 Demoscene, Search Light) accept custom text. Pick a single scene or set "Random" to rotate through all of them.

## Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon or Intel (universal binary, signed + notarized)

## Installation (users)

1. Download `NerdymarkScreenSaver.dmg` from <https://nerdymark.com/screensavers>
2. Open the DMG, double-click `NerdymarkScreenSaver.saver`
3. System Settings prompts to install → "Install"
4. System Settings → Screen Saver → pick "Nerdymark Demoscene"
5. Click "Options…" to choose a specific scene and tune its parameters

## Adding a scene (developers)

Implementing a new scene is a single file plus one line in the registry:

1. Create `Sources/NerdymarkScreenSaver/Scenes/MyScene.swift` conforming to `DemoScene`:

   ```swift
   final class MyScene: DemoScene {
       static let identifier = "my_scene"
       static let displayName = "My Scene"
       static let options: [SceneOption] = [
           .slider(key: "speed", label: "Speed", min: 0.1, max: 5.0, defaultValue: 1.0, format: "%.1f"),
       ]
       init(size: CGSize, settings: SceneSettings) { /* ... */ }
       func resize(_ newSize: CGSize) { /* ... */ }
       func tick(dt: TimeInterval) { /* ... */ }
       func draw(in ctx: CGContext, size: CGSize) { /* ... */ }
   }
   ```

2. Add `MyScene.self` to the `allScenes` array in `Sources/NerdymarkScreenSaver/Scenes/SceneRegistry.swift`.

That's it. The configure sheet, persistence, and "Random" rotator pick it up automatically.

`SceneOption` cases: `.slider`, `.toggle`, `.choice`, `.text`. Settings are persisted per-scene in `ScreenSaverDefaults` namespaced by the bundle identifier and scene id, so two scenes can use the same option key without collision.

## Building

### One-time setup

```bash
brew install xcodegen create-dmg

# Notary credentials in keychain (one-time per machine).
xcrun notarytool store-credentials "nerdymark-notary" \
    --apple-id "your-apple-id@example.com" \
    --team-id "YOURTEAMID" \
    --password "your-app-specific-password"
# Create app-specific passwords at https://appleid.apple.com
```

Create `.env` in this directory (gitignored):

```bash
DEVELOPMENT_TEAM=YOURTEAMID
SIGNING_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)"
NOTARY_PROFILE=nerdymark-notary
```

Find your signing identity:

```bash
security find-identity -v -p codesigning
```

### Build commands

```bash
./build.sh                   # full: compile → sign → notarize → DMG
./build.sh --no-notarize     # skip notarization for local testing
./build.sh --clean           # wipe build/ and dist/ first
```

Output lands in `~/Library/Developer/Xcode/DerivedData/NerdymarkScreenSaver/dist/NerdymarkScreenSaver.dmg`. Build artifacts live outside iCloud Drive because iCloud auto-applies xattrs that codesign rejects.

Total build time: ~2 minutes (notarization is usually 30–90s).

### Installing your local build

```bash
open "$HOME/Library/Developer/Xcode/DerivedData/NerdymarkScreenSaver/dist/NerdymarkScreenSaver.saver"
```

## Project layout

```
screensavers/
├── project.yml                              xcodegen spec → generates .xcodeproj
├── build.sh                                 sign / notarize / DMG pipeline
├── SCENES_PLAN.md                           porting plan from the LED matrix project
├── Sources/NerdymarkScreenSaver/
│   ├── NerdymarkScreenSaverView.swift       ScreenSaverView host + scene rotator
│   ├── ConfigureSheetController.swift       programmatic NSWindow configure UI
│   ├── SettingsStore.swift                  ScreenSaverDefaults wrapper
│   ├── Info.plist
│   └── Scenes/
│       ├── DemoScene.swift                  protocol + SceneOption enum
│       ├── SceneRegistry.swift              source of truth for registered scenes
│       ├── PlasmaUtil.swift                 shared palette + bitmap helper
│       ├── BoidsCore.swift                  shared boids simulation
│       └── *.swift                          one file per scene
```

## Distribution

Distributed as a notarized DMG from <https://nerdymark.com/screensavers>. Not on the Mac App Store (Apple employees' personal projects ship from their own sites by policy).

## License

MIT.
