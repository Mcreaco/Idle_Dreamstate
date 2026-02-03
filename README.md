# 🧠 Abyssal Descent (Working Title)

A Godot 4 idle / incremental game about descending through layers of the mind, managing instability, and building permanent meta progression through multiple prestige systems. You dive deeper into a conceptual abyss, earn resources, and unlock permanent upgrades that persist across runs.

---
## 🎮 Core Gameplay Loop
1. Passively gain **Thoughts** and **Control**.
2. **Dive** to increase Depth (more rewards, faster Instability growth).
3. Use **Overclock** to burst Thoughts at the cost of Control and Instability.
4. If Instability reaches 100%, the run fails.
5. **Wake** to prestige: reset the run and gain Memories plus a depth currency based on your deepest depth.
---
## 🧩 Resources
| Resource        | Description                              |
|-----------------|------------------------------------------|
| Thoughts        | Main idle production resource            |
| Control         | Spent on Overclock                       |
| Instability     | Loss condition at 100%                   |
| Memories        | Prestige currency for permanent perks    |
| Depth Crystals  | One currency per depth (Amethyst → Quartz) |

Depth ranges from **1–15**. Each depth has its own currency and upgrade panel; depth upgrades are global and permanent, keeping earlier depths relevant.
---
## 🧠 Depth Meta Upgrades
Typical depth upgrades:
- Stabilise Instability (global instability reduction)
- Global Thoughts bonus
- Global Control bonus
- Idle instability reduction
- Unlock next depth
Later depths add:
- Dive cooldown reduction
- Offline gain boosts
- Corruption resistance
- Wake bonus multipliers
- Multi-currency upgrades (2–4 currencies, including later-depth costs)
---
## 🔁 Prestige Layers
**Wake (Run Reset)**  
Converts run performance into Memories and depth currency.
**Perm Perks (Memory Shop)**  
- Memory Engine → +Thoughts  
- Calm Mind → -Instability  
- Focused Will → +Control  
- Starting Insight → start with Thoughts  
- Stability Buffer → start with lower Instability  
- Offline Echo → stronger offline gains  
**Abyss Perks (Late Game)**  
Unlocked at Depth 15; offer start-depth boosts, instability reduction, and further Control/Thoughts scaling.
---
## ⚙ Automation
- Auto Dive
- Auto Overclock
- Guarded by instability safety checks
---
## 🗂 Major Systems
| Script                | Purpose                               |
|-----------------------|---------------------------------------|
| GameManager.gd        | Core loop, resources, depth flow      |
| DepthMetaSystem.gd    | Depth currencies & upgrades           |
| UpgradeManager.gd     | Run upgrades (resets each run)        |
| PermPerkSystem.gd     | Permanent perks (Memories)            |
| MetaPanelController.gd| Meta UI (Perm/Depth/Abyss tabs)       |
| DepthUpgradeRow.gd    | UI row for depth upgrades             |
| PrestigePanel.gd      | Wake/prestige screen                  |
| AutomationSystem.gd   | Auto-play (dive/overclock)            |
| OverclockSystem.gd    | Burst production & instability cost   |
| RiskSystem.gd         | Instability logic                     |
---
## 🎯 Design Goals
- Depth behaves like a skill tree; earlier depths stay relevant.
- Multiple interacting prestige layers.
- Slow, readable exponential growth.
- Clear UI and long-term progression clarity.
---
## 🛠 Engine
Godot 4.x (GDScript).
---
## 🚀 Status
Implemented: depth currencies, global depth upgrades, multi-currency costs, perm perks, abyss unlock, offline progress, automation.  
Focus: balancing, visual polish, content expansion.
