# ECHO: Sound in the Darkness

2D top-down stealth game (Godot 4.7, GL Compatibility). You see only what your sound reveals.

## Folder structure

```
autoload/    GameState.gd      Level list, restart / menu / next level
scenes/      main.tscn         Game container: loads the current level and wires systems
characters/
  player/    Player, MicInput
  enemy/     Enemy (logic), EnemyPresets (stats), EnemyVisual (drawing),
			 enemy_<type>.tscn (ready-to-drop presets)
systems/
  echo/      EchoLayer         Draws echo waves / wall dots
  sound/     SoundBus          Routes player sounds, Screamer shrieks, Listener alarms
  audio/     HeartbeatManager  Heartbeat driven by enemy threat
ui/          HUD, buttons, settings modal, menu.tscn, theme, vignette shader
levels/      level_xx.tscn     One scene per level (teammates)
audio/ assets/                 Sound files, images
```

## Adding a level
1. Create `levels/level_xx.tscn` (root `Node2D`) with walls (collision layer 1) and enemies.
2. Optional: add a `Marker2D` named `PlayerStart` for the spawn point.
3. Append the path to `LEVELS` in `autoload/GameState.gd`.

## Enemies (player: walk 190, sneak 100)

| Type | Start | Walk heard at | Speed (patrol / chase) | Special |
|---|---|---|---|---|
| Sleeper | Sleep | ~67px | 60 / 135 | Hard to wake, deaf to sneaking, wakes at 35px when you sneak |
| Patroller | Patrol | ~152px | 75 / 150 | Walks a route; only notices sneaking within ~60px |
| Chaser | Patrol | ~160px | 90 / 185 | Most sensitive, fast, 0.2s reaction, chases 5s, deaf to sneaking |
| Screamer | Sleep | ignores steps | stationary | 2nd voice (>=1s apart): shriek that pulls monsters and freezes the player 1.6s |
| Listener | Sleep | ignores steps | stationary | A shout starts listening; 5 voices (>=0.8s apart) trigger a map-wide pulse: all monsters rush to it, +25% speed for 6s |

Player: walk 190, sneak 100. Walk step radius 185, sneak 60, voice 238~436.
Tune stats in `characters/enemy/EnemyPresets.gd`. Set patrol routes with `patrol_points`
(global positions) or by moving the Marker2D children of `EnemyPath`.
