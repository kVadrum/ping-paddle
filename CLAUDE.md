# Ping Paddle

## Stack
- Godot 4.5 (GDScript only, no C#, no plugins)
- Pure procedural rendering via `_draw()` — no sprites or textures
- Procedural audio via `AudioStreamWAV` — no sound files
- Zero external dependencies

## Structure
```
scenes/
  Main.tscn          — root scene, HUD, controls bar
  TitleScreen.tscn    — title/splash screen overlay
scripts/
  Main.gd            — HUD logic, input routing, theme, window management
  Game.gd            — game loop, physics, rendering, AI, sound
  TitleScreen.gd     — title screen dismiss logic
```

## Conventions
- All rendering is procedural (`_draw()` in Game.gd) — no sprite assets
- All audio is procedural (sine wave beeps generated at runtime)
- Theme colors (dark/light) are managed in Main.gd and pushed to Game.gd
- Game.gd owns gameplay state; Main.gd owns UI state
- Game.gd communicates to Main.gd via signals (`score_changed`, `banner_changed`)
- Main.gd pushes settings to Game.gd via setter methods
- Pause state is centralized in Main.gd via PauseReason enum
- Window management (fullscreen/windowed/minimize) handled in Main.gd

## Running
```bash
godot --path . 		# run from project root
```

## Key bindings
- W/S: Player 1
- O/L: Player 2
- P: Pause, G: Go (unpause), R: Reset match
- T: Toggle dark/light theme
- Esc: Quit
