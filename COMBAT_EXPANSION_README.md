# IDLE DREAMSTATE — Combat & Equipment Expansion

## Overview
This expansion adds **turn-based combat** and **deep equipment progression** to the existing idle/depth system. Players encounter "Dreams" (combat or puzzles) while diving, earn equipment with massive stat scaling, and progress through 8 rarity tiers with a soft cap at **Legendary Level 40** and true max at **God Tier Level 100**.

---

## Economy Changes

### Control → Dream Cloud
- **Control currency removed entirely**
- **Dream Cloud** now handles all economy functions:
  - Gear leveling
  - Combat Overclock buffs
  - Fusion costs
  - Emergency continues
  - Stat rerolls

### Cloud Sources
| Source | Cloud Amount |
|--------|-------------|
| Combat win (Depth 3) | 50-100 |
| Combat win (Depth 7) | 300-600 |
| Combat win (Depth 12) | 1,000-2,000 |
| Combat win (Depth 15) | 2,500-5,000 |
| Perfect combat bonus | +50% |
| Puzzle solve | 200-1,000 × depth |
| Daily login | 5,000 |
| Salvage gear | 10-50% of piece value |
| Event weekends | 2x-3x all gains |

---

## Equipment System

### Gear Slots (6 total)
| Slot | Primary Stat | Function |
|------|-------------|----------|
| Weapon | Attack 70% | Primary damage attacks |
| Armor | HP 70% | Defensive responses |
| Amulet | Balanced | Special abilities |
| Ring 1 | Attack 50% | Utility |
| Ring 2 | HP 50% | Utility |
| Talisman | DEF + unique | Ultimate (1/combat) |

### Rarity Tiers & Level Caps
| Tier | Max Level | Level Bonus | Visual |
|------|-----------|-------------|--------|
| Common | 10 | +2%/level (+20%) | Dull |
| Uncommon | 20 | +2%/level (+40%) | Faint glow |
| Rare | 30 | +2%/level (+60%) | Soft aura |
| Epic | 40 | +2%/level (+80%) | Bright |
| **Legendary** | **40** | **+2%/level (+80%)** | **Gold, "complete"** |
| **Mythic** | **60** | **+3%/level (+180%)** | **Prismatic** |
| **Transcendent** | **80** | **+4%/level (+320%)** | **Reality shift** |
| **God Tier** | **100** | **+5%/level (+500%)** | **Transcendent** |

**Key Rule:** Cannot level past rarity cap. Must fuse three maxed pieces to unlock next tier.

---

## Gear Score

### Formula
Gear Score = Base Score × (1 + Level Bonus) × Roll Quality × Set Bonus
plain
Copy

### Target Numbers
| Tier | Per Piece (Max) | Full Set 6pc |
|------|----------------|--------------|
| Common | 300 | 1,800 |
| Uncommon | 1,500 | 9,000 |
| Rare | 10,000 | 60,000 |
| Epic | 50,000 | 300,000 |
| **Legendary 40** | **180,000** | **~1,000,000** |
| Mythic 60 | 980,000 | ~6,000,000 |
| Transcendent 80 | 2,520,000 | ~15,000,000 |
| God Tier 100 | 6,000,000 | ~36,000,000 |

---

## Combat System: "The Lucid Duel"

### Structure
1. Encounter starts → Enemy reveals **INTENT**
2. Player selects **1 attack** from 7 options
3. Resolution (3-5 seconds)
4. Repeat for 3-5 turns

### Attack Options
| Source | Attack | Effect |
|--------|--------|--------|
| Weapon | **Slash** | 100% damage + Bleed |
| Weapon | **Pierce** | 80% damage + ignore 30% DEF |
| Weapon | **Bludgeon** | 120% damage + Stun chance |
| Armor | **Block** | -60% damage taken |
| Armor | **Dodge** | Avoid 100% (if predicted) |
| Armor | **Brace** | -30% damage + reflect 20% |
| Ring 1 | **Interrupt** | Cancel enemy intent + 40% damage |
| Ring 2 | **Feint** | Force enemy miss + counter 80% |
| Amulet | **Special** | Heal / Cleanse / Buff |
| Talisman | **Ultimate** | 300% damage (once/combat) |

### Enemy Intents
| Intent | Effect | Hard Counter |
|--------|--------|--------------|
| Strike | Standard damage | Block, Brace |
| Crush | Heavy, telegraphed | Dodge, Interrupt |
| Flurry | Multi-hit | Block |
| Lunge | High crit | Dodge, Interrupt |
| Charge | Massive next turn | Interrupt, burst |
| Weave | Dodges next attack | Feint |
| Drain | Heals from damage | Block |
| Summon | Adds minion | Kill fast, AoE |

### Depth Complexity
| Depth | New Mechanic |
|-------|-------------|
| 3-4 | Single intent, 3-turn combat |
| 5-6 | **Dual intent** — enemy picks one of two |
| 7-8 | **Intent chains** — conditional patterns |
| 9-10 | **Phase shift** — 50% HP transforms |
| 11-12 | **Player tracking** — counters your last attack |
| 13-14 | **Compressed** — 2 turns only |
| 15 | **The Dreamstate** — poetic, memorized intents |

### Instability Effects
| Instability | Combat Effect |
|-------------|---------------|
| 0-25% | +10% damage |
| 26-50% | Normal |
| 51-75% | 1 attack option hidden |
| 76-90% | Intent info 30% wrong |
| 91-100% | Auto-combat at 60% win rate |

---

## S-Rank Gear

Named unique pieces with **quest-based upgrade paths**. Drop at Epic, upgrade to God Tier through achievements.

### Example: *The Insomniac's Blade*
| Stage | Requirement | Unlock |
|-------|-------------|--------|
| Epic | Drop in Depth 7 | **Recur**: 80% dmg, refresh Talisman on kill |
| Legendary | Defeat 100 with Slash | Damage 80% → 100% |
| Mythic | Win 10 at <10% HP | Add +Bleed 20%/3 turns |
| God Tier | Depth 15 boss with only Slash | **Recur executes twice** |

---

## Set Bonuses

| Set | 2-Piece | 4-Piece | 6-Piece |
|-----|---------|---------|---------|
| **The Flicker** | +20% Dodge | See next intent | Swap 1 attack/turn |
| **The Drowned** | Bleed +1 turn | Bleed stacks 3x | Heal 10% on bleed |
| **The Mirror** | Reflect 15% | Copy enemy intent | Ultimate refreshes |
| **The Immortal** | +30% HP | Survive fatal 1/combat | Regen 5%/turn |
| **The Destroyer** | +30% ATK | Crits refresh Talisman | Crits deal 300% |
| **The Awakened** | +20% all | +35% all, see intents | +50% all, ignore instability |

---

## Fusion System
3× Piece (max level) + Dream Cloud = 1× Higher tier (level 1)
plain
Copy

| Fusion | Cloud Cost |
|--------|-----------|
| Common 10 → Uncommon 1 | 500 |
| Uncommon 20 → Rare 1 | 2,500 |
| Rare 30 → Epic 1 | 10,000 |
| Epic 40 → Legendary 1 | 50,000 |
| Legendary 40 → Mythic 1 | 200,000 |

---

## Progression Gates

| Content | Recommended GS | Min GS (penalty) |
|---------|---------------|------------------|
| Depth 5 | 25,000 | 10,000 |
| Depth 10 | 350,000 | 200,000 |
| Depth 12 | 600,000 | 400,000 |
| Depth 15 | 1,200,000 | 800,000 |
| Nightmare Mode | 3,500,000 | 2,000,000 |

**Under-geared penalty:** Enemies +50% stats, -25% rewards.

---

## Implementation Checklist

### Data Structures
- [ ] `EquipmentItem` (id, rarity, level, stats, sub-stats, special attack)
- [ ] `EnemyData` (hp, atk, intent patterns, depth range)
- [ ] `DreamEncounter` (type, enemy/puzzle, rewards)
- [ ] `SetBonus` database

### Systems
- [ ] `EquipmentManager` (inventory, equipping, leveling, fusion)
- [ ] `CombatEngine` (turn resolution, intent logic, damage calc)
- [ ] `DreamEncounterController` (spawning, progress pausing)
- [ ] `GearScoreCalculator`
- [ ] `CloudEconomy`

### UI Screens
- [ ] Combat encounter modal
- [ ] Equipment inventory with leveling
- [ ] Fusion/forge screen
- [ ] Character stats with Gear Score
- [ ] Enemy intent display

### Integration
- [ ] Hook into `DepthRunController` checkpoints
- [ ] Replace Control with Cloud
- [ ] Add equipment drops
- [ ] Update save/load

---

## Design Pillars

| Pillar | Implementation |
|--------|---------------|
| **Active Idle** | One decision per turn, watch resolution |
| **Meaningful Progression** | 20 levels/rarity, big jumps post-Legendary |
| **Build Expression** | Same GS, different stat distributions |
| **Readable Challenge** | Intents shown, counter-play available |
| **Long Chase** | God Tier 100 as multi-year goal |
| **Unified Economy** | Dream Cloud for all sinks |

---

## Repository

https://github.com/Mcreaco/Idle_Dreamstate/tree/main/idle-dreamstate-v-3