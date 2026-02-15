# Idle Dreamstate (Abyssal Descent)

[![Godot Engine](https://img.shields.io/badge/Godot-4.5.1-blue.svg)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> *"The deeper you dive, the more you lose yourself. But what you find... might be worth the price."*

A cosmic horror-themed idle/incremental game built in Godot 4. Descend through 15 layers of dreams and consciousness, manage your mind's resources, and battle rising instability to reach The Abyss.

![Game Screenshot](docs/screenshot.png)

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [How to Play](#how-to-play)
- [Game Mechanics](#game-mechanics)
- [The 15 Depths](#the-15-depths)
- [Meta Progression](#meta-progression)
- [Tips & Strategy](#tips--strategy)
- [Technical Details](#technical-details)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **15 Unique Depths** - Each with distinct mechanics, challenges, and atmosphere
- **Dual Resource System** - Manage Thoughts (production) and Control (boosts) while fighting Instability
- **Deep Meta Progression** - 16 permanent upgrades, 15 depth-specific upgrade trees, and late-game Abyssal Perks
- **Offline Progress** - Earn resources while away (up to 1 hour)
- **Risk/Reward Gameplay** - Push your luck for bigger rewards or play it safe
- **Cosmic Horror Aesthetic** - Atmospheric visuals and unsettling depth mechanics

---

## Installation

### Requirements
- **Godot Engine 4.5.1** or later
- **OS**: Windows, macOS, Linux, Android, or iOS

### Running from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/Mcreaco/Idle_Dreamstate.git
   cd Idle_Dreamstate
   ```

2. Open the project in Godot:
   - Launch Godot Engine
   - Click "Import"
   - Select the `project.godot` file

3. Press **F5** or click the Play button to run

### Exporting

To export for your platform:
1. Go to **Project > Export**
2. Select your target platform
3. Click "Export Project"

---

## How to Play

### Core Gameplay Loop

1. **Generate** - Thoughts and Control generate automatically every second
2. **Upgrade** - Spend Thoughts on run upgrades (speed, stability, memory gain)
3. **Monitor** - Watch your Instability (starts at Depth 2, rises constantly)
4. **Dive** - Fill the progress bar to unlock the next depth
5. **Wake** - Prestige to convert progress into permanent Memories and Crystals
6. **Repeat** - Descend deeper with permanent bonuses

### Controls

| Action | Description |
|--------|-------------|
| **Overclock** | Spend Control for temporary production boost |
| **Dive** | Descend to next depth (when progress bar full) |
| **Wake** | End run and collect Memories/Crystals |
| **Meta** | Open permanent upgrade panel |

---

## Game Mechanics

### Resources

#### During a Run

| Resource | Description | Risk |
|----------|-------------|------|
| **Thoughts** | Primary currency. Generated passively. Spend on upgrades. | None |
| **Control** | Secondary resource. Spend on Overclock boosts. | None |
| **Instability** | Risk meter (0-100%). Rises constantly at Depth 2+. | **FAIL at 100%** |

#### Permanent

| Resource | How to Earn | Use |
|----------|-------------|-----|
| **Memories** | Wake bonus based on Thoughts + Time + Depth | Buy permanent upgrades |
| **Crystals** | Earned per depth reached (15 types) | Buy depth-specific upgrades |

### Instability System

- **Hidden at Depth 1** - Safe tutorial zone
- **Activates at Depth 2** - Starts at 0%, rises ~0.4/sec
- **Time Until Fail** - Shows seconds until 100% Instability
- **FAIL State** - Forced Wake at 100% with 0.60x penalty (vs 1.35x for voluntary Wake)

### Overclock

- **Cost**: Control (base cost × upgrade multipliers)
- **Duration**: 10 seconds (× duration upgrades)
- **Effects**: 
  - +Thoughts generation
  - ×Duration multiplier
- **Risk**: Increased Instability gain while active

---

## The 15 Depths

| # | Depth Name | Mechanic | Unlock Requirement |
|---|------------|----------|-------------------|
| 1 | **The Shallows** | Tutorial. No instability. | Starting depth |
| 2 | **Descent** | First instability (0.4/sec). | Max "Stabilize" upgrade |
| 3 | **Pressure** | High instability slows progress. | Complete Depth 2 |
| 4 | **Murk** | Hidden rewards until Wake. | Complete Depth 3 |
| 5 | **Rift** | Choice events every 30s. | Complete Depth 4 |
| 6 | **Hollow** | Frozen depth bonuses stack. | Complete Depth 5 |
| 7 | **Dread** | Fake threat events. | Complete Depth 6 |
| 8 | **Chasm** | +10% speed per frozen depth. | Complete Depth 7 |
| 9 | **Silence** | Blind mode (numbers hidden). Buy "Inner Eye" to see. | Complete Depth 8 |
| 10 | **Veil** | Random outcomes on choices. | Complete Depth 9 |
| 11 | **Ruin** | Can lose frozen bonuses. | Complete Depth 10 |
| 12 | **Eclipse** | Shadow clone mirrors actions. | Complete Depth 11 |
| 13 | **Voidline** | 1% chance/sec to lose progress. | Complete Depth 12 |
| 14 | **Blackwater** | Crystal carryover mechanic. | Complete Depth 13 |
| 15 | **The Abyss** | Final test. All mechanics combined. | Complete Depth 14 |

### Depth Currencies

| Depth | Currency | Color |
|-------|----------|-------|
| 1 | Amethyst | Purple |
| 2 | Ruby | Red |
| 3 | Emerald | Green |
| 4 | Sapphire | Blue |
| 5 | Diamond | White |
| 6 | Topaz | Yellow |
| 7 | Garnet | Dark Red |
| 8 | Opal | Iridescent |
| 9 | Aquamarine | Cyan |
| 10 | Onyx | Black |
| 11 | Jade | Teal |
| 12 | Moonstone | Silver |
| 13 | Obsidian | Dark Grey |
| 14 | Citrine | Orange |
| 15 | Quartz | Clear |

---

## Meta Progression

### Permanent Upgrades (Memories)

Spend Memories on permanent bonuses for ALL future runs:

| Upgrade | Effect | Max Level |
|---------|--------|-----------|
| **Memory Engine** | +5% Thoughts per level | 25 |
| **Calm Mind** | -4% Instability gain per level | 25 |
| **Focused Will** | +6% Control per level | 25 |
| **Starting Insight** | Start with +25 Thoughts per level | 25 |
| **Stability Buffer** | Start with -2 Instability per level | 25 |
| **Offline Echo** | +8% Offline gains per level | 25 |
| **Recursive Memory** | +5% Memories gain per level | 25 |
| **Lucid Dreaming** | +10% Overclock duration per level | 25 |
| **Deep Sleeper** | +2% Thoughts per depth level per level | 25 |
| **Night Owl** | +8% Idle Thoughts per level | 25 |
| **Dream Catcher** | +3% chance to not consume Control on Overclock | 25 |
| **Subconscious Miner** | +0.5 passive Thoughts/sec even while offline | 25 |
| **Void Walker** | +5 Instability cap per level (can exceed 100%) | 25 |
| **Rapid Eye** | -3% Dive cooldown per level | 25 |
| **Sleep Paralysis** | +1s frozen Instability after Wake/Fail per level | 25 |
| **Oneiromancy** | +1 depth preview per level | 25 |

### Depth Upgrades (Crystals)

Each depth has unique upgrades purchased with its specific crystal:

- **Progress Speed** - Fill dive bar faster (all depths)
- **Memories Gain** - More memories from this depth (all depths)
- **Crystals Gain** - More crystals from this depth (all depths)
- **Stabilize** - Reduce Instability (Depth 2 only)
- **Inner Eye** - See numbers in Silence (Depth 9 only)
- And more depth-specific upgrades...

### Abyssal Perks (Late Game)

Unlocked after reaching Depth 15:

| Perk | Effect |
|------|--------|
| **Echoed Descent** | Start new runs with bonus based on previous run |
| **Abyssal Focus** | Reduced Instability at high depths |
| **Dark Insight** | See hidden information |
| **Abyss Veil** | Protection from random events |

---

## Tips & Strategy

### Early Game (Depths 1-3)

1. **Prioritize Thoughts Speed** - Generate currency faster
2. **Max Stabilize at Depth 2** - Required to unlock Dive
3. **Keep Instability < 50%** - Don't risk failing early
4. **Wake Early & Often** - Build up Memories for permanent upgrades
5. **Buy Calm Mind ASAP** - Reduces Instability permanently

### Mid Game (Depths 4-9)

1. **Balance Speed & Stability** - Don't ignore Instability management
2. **Save Control for Emergencies** - Use Overclock when safe
3. **Watch Depth Mechanics**:
   - **Rift (5)**: Choose wisely - some options boost, some hurt
   - **Silence (9)**: Buy Inner Eye or fly blind
4. **Build Offline Echo** - Helps when you can't play actively

### Late Game (Depths 10-15)

1. **Void Walker is Key** - Lets you push past 100% temporarily
2. **Frozen Bonuses Stack** - Hollow (6) bonuses compound
3. **Save Crystals for Blackwater (14)** - Carryover mechanic is powerful
4. **The Abyss (15)** - All mechanics active. Be prepared.

### Formula Reference

- **Memories on Wake**: √(Total Thoughts) × (1 + Max Instability/100) × Time Mult × Depth Mult × 1.35 (voluntary)
- **Crystals on Wake**: √(Total Thoughts) × (1 + Depth × 0.15) × 0.05 × Depth Mult
- **Instability Gain**: Base Rate × Depth Mult × Upgrade Reductions

---

## Technical Details

### Built With

- **Godot Engine 4.5.1** - Game engine
- **GDScript** - Primary scripting language
- **Vulkan** - Rendering backend

### Architecture

```
GameManager.gd           - Main game loop, save/load coordinator
DepthRunController.gd    - 15-depth run system (progress, depth switching)
DepthMetaSystem.gd       - Permanent progression (currencies, upgrades)
MetaPanelController.gd   - UI for meta upgrades (3 tabs)
RiskSystem.gd            - Instability calculation
OverclockSystem.gd       - Temporary boost mechanic
SaveSystem.gd            - JSON save/load
```

### Save Data Location

- **Windows**: `%APPDATA%/Godot/app_userdata/Idle Dreamstate/savegame.json`
- **macOS**: `~/Library/Application Support/Godot/app_userdata/Idle Dreamstate/savegame.json`
- **Linux**: `~/.local/share/godot/app_userdata/Idle Dreamstate/savegame.json`

### Offline Progress

- Calculates up to **1 hour** of progress while away
- Gains: Thoughts, Control, Instability, Depth Progress
- Multiplier: Base rate × Offline Echo upgrade level
- Depth-specific: Only active depth gains progress/memories/crystals

---

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Reporting Bugs

Please include:
- Godot version
- OS and version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Inspired by classic idle games like Cookie Clicker and Clicker Heroes
- Cosmic horror themes influenced by Lovecraftian fiction
- Built with the amazing [Godot Engine](https://godotengine.org)

---

## Links

- **Repository**: https://github.com/Mcreaco/Idle_Dreamstate
- **Issues**: https://github.com/Mcreaco/Idle_Dreamstate/issues
- **Godot Engine**: https://godotengine.org

---

> *"In dreams, we descend. In descent, we find truth. In truth... we wake."*
