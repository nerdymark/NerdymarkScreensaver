# Scenes Port Plan

Porting matrix_modules from the magic-frame Python repo into native Swift
scenes for NerdymarkScreenSaver. Each scene is its own file in
`Sources/NerdymarkScreenSaver/Scenes/`, registered in `SceneRegistry.swift`.

Conventions:
- 60–250 lines of Swift each, no external dependencies
- Core Graphics rendering only (no SpriteKit/Metal)
- 24–30 fps target, <8% CPU on Apple Silicon
- 1/2 to 1/4 internal resolution where pixel effects are involved
- Each declares `SceneOption`s so users can tune in the configure sheet

Legend: ✅ done · 🛠️ in progress · ⏳ planned · ❌ skip

---

## Done (baseline)
- [x] **plasma** — CPU-palette plasma at 1/4 res
- [x] **snake** — A* pathfinding with flood-fill survival fallback

## Batch 1 — Quick wins, max visual variety
- [x] ✅ **the_matrix** — Falling green kana streams
- [x] ✅ **starfield** — 3D point cloud, depth-projected
- [x] ✅ **fire** — DOOM-style palette burn (bottom-up propagation)
- [x] ✅ **game_of_life** — Conway's CA, hypnotic auto-evolution
- [x] ✅ **dvd** — Bouncing nerdymark text logo, color shift on bounce
- [x] ✅ **metaballs** — Marching-square-ish blobs

## Batch 2 — Particle systems
- [x] ✅ **blizzard** — Falling snow with parallax depth
- [x] ✅ **bubbles** — Rising bubbles with shimmer
- [x] ✅ **shadebobs** — Color-cycling bobs leaving palette trails

## Batch 3 — Math curves & illusions
- [x] ✅ **lissajous** — Parametric curve drawer with phase shift
- [x] ✅ **moire** — Two grids interfering, slow rotation
- [x] ✅ **scintillating_grid** — Hermann grid optical illusion
- [x] ✅ **dna_helix** — Two intertwined sine wave strands

## Batch 4 — Plasma family (variant of existing)
- [x] ✅ **spiral_plasma** — Angular sin terms instead of XY
- [x] ✅ **diamond_plasma** — Manhattan-distance metric
- [x] ✅ **ripple_plasma** — Distance from random "drop" points
- (also added: shared `PlasmaUtil.swift` with palette + low-res bitmap helper)

## Batch 4.5 — User-requested optical / Apple
- [x] ✅ **apple_event** — Unicode  logo center, liquid-glass refraction over rainbow palette
- [x] ✅ **simultaneous_contrast** — Identical gray patches on shifting backgrounds
- [x] ✅ **afterimage** — Negative-color shapes shown for 5s then white reveal

## Batch 5 — 3D classics (medium)
- [x] ✅ **tunnel** — Precomputed angle/depth lookup, palette scroll
- [x] ✅ **rotozoomer** — Affine-transformed bitmap (logo as source)
- [x] ✅ **mode7** — SNES-style perspective floor with checkerboard
- [x] ✅ **vector_balls** — Lattice of shaded spheres rotating
- [x] ✅ **hypercube_4d** — 4D rotation → 3D → 2D projection

## Batch 6 — Demoscene staples
- [x] ✅ **copper_bars** — Amiga gradient bars with sin motion
- [x] ✅ **raster_bars** — Horizontal palette stripes
- [x] ✅ **sine_scrollers** — Greetz-style wavy text scroll
- [x] ✅ **glenz_vectors** — Depth-sorted translucent polyhedra
- [x] ✅ **c64_demoscene** — Multi-effect composite (border bars + scroller + sprites)

## Batch 7 — Flocking & life
- [x] ✅ **fish_schooling** — Boids algorithm, orange/teal palette
- [x] ✅ **bug_swarm** — Boids variant, darker palette, longer trails
- ❌ **fishtank** — Removed; needs sprite-based art to look right
- [x] ✅ **lava_lamp** — Slow blob morph (variant of metaballs)

## Batch 8 — Fractals & special
- [x] ✅ **mandelbrot_julia** — Mandelbrot with auto-zoom into pretty regions
- [x] ✅ **maze** — Recursive backtracking generation + auto-solve
- [x] ✅ **falling_blocks** — Tetris auto-play
- [x] ✅ **search_light** — Moving spotlight over hidden image
- [x] ✅ **lens_flare** — Streaks tracking a moving "sun"
- [x] ✅ **flag_wave** — Pride / Trans / USA / Palestine / Ukraine flag distortion
- [x] ✅ **parallax_scroller** — Multi-depth horizontal scroll
- [x] ✅ **rubiks_cube** — Tumbling 3D cube with random shuffles

## Batch 9 — Original generative / pattern
- [x] ✅ **truchet_tiles** — Random-orientation tiles (curves/triangles) form flowing patterns
- [x] ✅ **reaction_diffusion** — Gray-Scott Turing patterns: spots/stripes/mazes emerge
- [x] ✅ **voronoi** — Animated Voronoi cells with moving sites
- [x] ✅ **dla_snowflake** — Diffusion-limited aggregation grows coral/snowflake

## Batch 10 — Agent-based / sim
- [x] ✅ **slime_mold** — Physarum agents leave fading trails forming organic networks
- [x] ✅ **vector_field** — Particles trace mutating vector fields, leaving ribbons
- [x] ✅ **falling_sand** — Pixel physics with sand/water/oil colors interacting
- [x] ✅ **l_system_tree** — Fractal tree grows, drops leaves, restarts seasonally

## Batch 11 — Demoscene / 80s
- [x] ✅ **synthwave_grid** — Perspective floor grid scrolling toward retrowave sun
- [x] ✅ **aurora_borealis** — Sin-driven curtain of greens/purples shimmering
- [x] ✅ **knot_weave** — Animated over/under Celtic braids

## Batch 12 — Auto-play games / utility
- [x] ✅ **pong_ai** — Two paddles auto-play forever with slight imperfection
- [x] ✅ **tron_cycles** — Two trail-cycles build until one boxes the other in
- [x] ✅ **constellation_maker** — Drifting stars get connected by fading lines
- [x] ✅ **ripple_tank** — Random droplets interfere as waves propagate

## Batch 13 — Throwbacks
- [x] ✅ **pipes_3d** — Win95-style 3D pipes growing & turning in a rotating cube

## Skip list (not screensaver-appropriate)
- ❌ `__init__.py`, `constants.py`, `utils.py` — Python infrastructure
- ❌ `qr_renderer.py` — Utility, not generative
- ❌ `shading_demo.py` — Internal test, not visual
- ❌ `strategic_snake.py` — Variant of existing snake
- ❌ `plasma_two.py` — Variant (covered by Batch 4)
- (✓ moved to Batch 4.5: apple_event, simultaneous_contrast, afterimage)
