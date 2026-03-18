# Idle Dreamstate (Abyssal Descent)

[![Godot Engine](https://img.shields.io/badge/Godot-4.3-blue.svg)](https://godotengine.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-v0.1.0-orange.svg)](CHANGELOG.md)

> *"The deeper you dive, the more you lose yourself. But what you find... might be worth the price."*

A cosmic horror-themed idle/incremental game built in Godot 4. Descend through 15 layers of dreams and consciousness, manage your mind's resources, and battle rising instability to reach The Abyss. 

**v0.1.0 "The Second Playtest" is here!** Now featuring turn-based combat, a deep equipment progression system, and a visual skill tree overhaul.

---

## 🌌 Core Features

- **15 Unique Depths** - Each with distinct mechanics, challenges, and atmospheric shifts.
- **⚔️ Turn-Based Combat** - Encounter "Dreams" (fighting or puzzles) while diving. Counter enemy intents and master the "Lucid Duel."
- **🛡️ Deep Equipment System** - 6 gear slots, 8 rarity tiers (Common to God-Tier), and massive stat scaling.
- **🔮 Visual Skill Tree** - A true hierarchical progression graph with glowing connections and iconic power-ups.
- **Dual Resource System** - Manage **Thoughts** (production) andfight **Instability** while earning **Dream Clouds** for combat upgrades.
- **Meta Progression** - 16 permanent upgrades, 15 depth-specific trees, and late-game Abyssal Perks.
- **Procedural Audio** - Immersive dreamlike soundscapes and dynamic combat SFX.

---

## 🛠️ Installation

### Requirements
- **Godot Engine 4.3** or later
- **OS**: Windows, macOS, Linux (Android/iOS builds available)

### Running from Source
1. Clone the repository: `git clone https://github.com/Mcreaco/Idle_Dreamstate.git`
2. Open the project in Godot 4.
3. Press **F5** to start your descent.

---

## 🎮 How to Play

### Core Gameplay Loop
1. **Generate** - Thoughts and Dream Clouds accumulate automatically.
2. **Upgrade** - Spend Thoughts on run speed and stability; spend Memories on permanent bonuses.
3. **Equip & Forge** - Collect drops from combat. Fuse three maxed items to reach the next rarity tier.
4. **Skills** - Unlock powerful nodes in the visual skill tree to boost your combat effectiveness.
5. **Dive** - Max out the "Stabilize" upgrade in the Meta Panel (Depth tab) to descend.
6. **Wake** - Prestige to convert your progress into permanent **Memories** and **Crystals**.

### Controls
| Action | Description |
|--------|-------------|
| **Combat** | Select attacks (Bludgeon, Slash, Block, etc.) to counter enemy intents. |
| **Meta** | Access permanent (Memories) and depth-specific (Crystals) upgrades. |
| **Forge** | Power up, fuse, and dismantle your equipment. |
| **Skills** | Purchase combat and economy perks in the visual tree. |

---

## ⚔️ Combat System: "The Lucid Duel"

Combat occurs during dives or as random encounters. 
- **Intents**: Enemies reveal their actions (Strike, Crush, Drain) beforehand.
- **Counters**: Use specific gear-based attacks (Block, Dodge, Interrupt) to mitigate damage.
- **Dream Clouds**: Earned from victories and used to dismantle or fuse gear.

---

## 📂 Architecture

- `GameManager.gd`: Main game loop and save/load management.
- `DreamsPanel.gd`: Orchestrates combat, skill tree, and equipment UI.
- `EquipmentManager.gd`: Handles inventory, stat calculations, and rarity logic.
- `DepthRunController.gd`: Manages the 15-depth progression and instability.
- `SoundSystem.gd`: Procedural and atmospheric audio engine.

---

## 📜 Links & Contributing

- **Changelog**: See [CHANGELOG.md](CHANGELOG.md) for full history.
- **Reporting Bugs**: Please use the [GitHub Issues](https://github.com/Mcreaco/Idle_Dreamstate/issues) page.
- **License**: MIT License.

---

> *"In dreams, we descend. In descent, we find truth. In truth... we wake."*
