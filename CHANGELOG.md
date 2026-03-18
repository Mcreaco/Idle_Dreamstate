# Changelog

All notable changes to **Idle Dreamstate** will be documented in this file.

## [v0.1.0] - "The Second Playtest" - 2026-03-18

### Added
- **Visual Skill Tree Overhaul**: Completely redesigned the skill tree from a simple list into a hierarchical graph with tier-based circular nodes and glowing prerequisite connections.
- **Premium Equipment Icons**: Integrated 640x640 premium assets for high-tier weapons and armor, including:
  - **S-Tier**: Voidreever, Soul Eye, Abyssal Garb, Void Gaze, Eternal Loop, and Heart of Dreams.
  - **Standard**: Sharp Dagger, Heavy Mace, Gold Ring, Great Helm, Steel Plate Armor, and more.
- **Bulk Dismantle System**: Added a new panel to dismantle multiple pieces of equipment at once, calculating rewards and updating the Dream Cloud balance instantly.
- **Advanced Inventory Sorting**: Implemented alphabetical and rarity-based sorting for both the Inventory and the Forge/Blacksmith views.
- **Procedural & Atmospheric Audio**: 
  - Added "Dreamsmusic.mp3" for deep, dreamlike atmosphere.
  - Implemented high-quality procedural combat SFX for hits and enemy deaths.
- **Expanded Equipment Documentation**: Created a comprehensive [equipment_list.md](file:///C:/Users/david/.gemini/antigravity\brain\407c4577-2d2e-4874-934e-37ab090ce6b4/equipment_list.md) for future asset planning.
- **Combat Tuning**: Renerted early waves (W1S1) and boosted late-game scaling to provide a smoother difficulty curve.

### Fixed
- **Skill Tree Compilation Error**: Resolved a variable redeclaration bug that caused the game to crash when opening the skills panel.
- **Forge Scroll Reset**: Fixed an issue where the Forge inventory would reset to the top whenever an item was upgraded.
- **Fusion Logic**: Addressed a bug where fusion could result in incorrect item types across rarity tiers.
- **Tooltip Stat Scaling**: Tooltips now correctly display final calculated stats (including level bonuses) rather than base stats.
- **ScrollContainer Method Errors**: Fixed `set_scroll_vertical` method errors in various UI panels.
- **Dismantle/Power-Up Logic**: Resolved several variable shadowing and argument count errors in `DreamsPanel.gd`.
- **Enemy Presentation**: Increased the size of `EnemySprite` for a better visual impact in combat.

## [v0.0.27] - "First Playtest" - 2026-03-13
- Initial release with basic 15 depths and meta-progression.
- Core 3D engine and atmospheric world.
