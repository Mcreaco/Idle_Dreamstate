# Idle Dreamstate - F2P Monetization & Balance Overhaul

## Project Overview
Transform the existing 15-depth idle game into an ethical, high-retention F2P title targeting **$0.15-0.25 ARPDAU** with infinite Abyss progression post-Depth 15. 

**Core Constraint**: 100% ethical monetization - convenience and cosmetics only, zero pay-to-win mechanics.

---

## Target Metrics

| Metric | Target | Industry Comparison |
|--------|--------|-------------------|
| **Time to Depth 15** | 250-300 hours | Deep progression |
| **ARPDAU** | $0.15-0.25 | Top 10% idle games |
| **D30 Retention** | >12% | High for fair monetization |
| **Conversion Rate** | 5-8% | Higher due to ethical model |
| **Daily Play Session** | 15-30 min micro + 1hr deep | Healthy mix |

---

## Core Philosophy: Ethical Monetization

### Allowed (Convenience)
- Auto-clickers (save manual input, not time)
- Ad removal (quality of life)
- Cosmetic skins (status flexing)
- Time warps (capped daily - F2P gets same via ads)

### Forbidden (P2W)
- Exclusive multipliers > F2P caps
- Paywalled upgrades or depth access
- "VIP" status with gameplay bonuses
- Energy systems blocking play
- Gacha for power items

---

## Technical Architecture Changes

### 1. Progression Rebalance

#### Cost Formula Update
Replace polynomial scaling with exponential:

```gdscript
# OLD (DepthBarRow.gd & DepthMetaSystem.gd)
var depth_multiplier := pow(float(depth_index), 2.5) * 3.0

# NEW - Gentler exponential curve
const DEPTH_GROWTH := 2.8
var depth_multiplier := pow(DEPTH_GROWTH, depth_index - 1) * 3.0
Depth Cap Scaling
Increase run length per depth:
gdscript
Copy
# DepthRunController.gd
func get_depth_progress_cap(depth: int) -> float:
    return 1000.0 * pow(3.0, float(depth - 1))  # Was 2.5
Unlock Requirements
Depth N requires:
Meta upgrade "Stabilize" level 10 in current depth
Meta upgrade "Unlock" purchased (currency cost)
gdscript
Copy
# DepthRunController.gd
func can_dive() -> bool:
    var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
    
    # Check permanent unlock
    if not meta.is_next_depth_unlocked(active_depth):
        return false
    
    # Check stabilize requirement (depth 2+)
    if active_depth >= 2:
        var stab_level = meta.get_level(active_depth, "stab")
        if stab_level < 10:
            return false
    
    return true
2. Abyss System (Post-Depth 15)
Infinite prestige loop with compounding multipliers:
gdscript
Copy
# GameManager.gd
var abyss_tier: int = 0
var abyss_points: float = 0.0

func transcend():
    if not can_transcend():  # Must be at D15, 100% progress
        return
    
    # Calculate Abyss Points (AP)
    var ap_gained: float = sqrt(memories) * (1.0 + abyss_tier * 0.1)
    abyss_points += ap_gained
    abyss_tier += 1
    
    # Reset to D1, keep all meta progress
    reset_to_depth_one()
    
    # Apply compounding 50% multiplier
    apply_abyss_bonuses()

func get_abyss_multiplier() -> float:
    return pow(1.5, abyss_tier)  # 50% per tier
3. Ethical Daily Caps
Prevent pay-to-win speedrunning:
gdscript
Copy
# GameManager.gd
const MAX_PURCHASED_TIME_PER_DAY: float = 4.0  # Hours
const DAILY_AD_CAP: int = 10

var purchased_time_today: float = 0.0
var ads_watched_today: int = 0

func buy_time_warp(hours: float) -> bool:
    if purchased_time_today + hours > MAX_PURCHASED_TIME_PER_DAY:
        return false  # Hard cap
    
    purchased_time_today += hours
    apply_offline_earnings(hours * 3600)
    return true
4. Piggy Bank System
Primary conversion driver ($4.99 break):
gdscript
Copy
# PiggyBank.gd (Auto-load Singleton)
const PIGGY_CAP := 500.0
const ACCUMULATION_RATE := 0.1  # 10% of thoughts

var current_amount: float = 0.0

func add_thoughts(amount: float):
    current_amount = minf(
        current_amount + (amount * ACCUMULATION_RATE), 
        PIGGY_CAP
    )

func break_bank():
    # Called after $4.99 IAP
    var payout = current_amount
    current_amount = 0.0
    return payout
Implementation Guide
Phase 1: Core Balance (Week 1)
Files to Modify:
DepthMetaSystem.gd
gdscript
Copy
# Update cost formulas for 250-300h target
func unlock_cost(depth: int) -> float:
    return 100.0 * pow(3.5, depth - 1)  # Exponential

func cost_for(depth_i: int, def: Dictionary) -> float:
    var d := clampi(depth_i, 1, MAX_DEPTH)
    var lvl := get_level(d, def.get("id", ""))
    var base := 80.0 + (d - 1) * 20.0  # Higher base costs
    
    match def.get("kind", ""):
        "stab":
            return base * pow(1.45, float(lvl))
        "unlock":
            return unlock_cost(d)
        # ... other cases
DepthBarRow.gd
Update cost display calculation:
gdscript
Copy
# In _update_upgrade_row_ui()
var depth_multiplier := pow(2.8, depth_index - 1) * 3.0
var cost := base_cost * depth_multiplier * pow(upgrade_growth, level)
GameManager.gd
Add ethical monetization state:
gdscript
Copy
# Add to top of class
var piggy_bank: float = 0.0
var purchased_time_today: float = 0.0
var abyss_tier: int = 0
var has_supporter_pack: bool = false  # $9.99 ad removal

# Modify get_thoughts_per_sec to include Abyss
func get_thoughts_per_sec() -> float:
    var base = calculate_base_rate()
    base *= get_abyss_multiplier()  # Earned, not bought
    return base
Phase 2: Monetization UI (Week 2)
New Scenes to Create:
PiggyBankPanel.tscn
Visual piggy bank (fills up with thoughts)
"$4.99 Break Bank" button (appears when >=100 thoughts)
Shake animation when full
TranscendencePanel.tscn
Appears at D15 100% progress
Explains Abyss reset (+50% multiplier)
"Transcend" button (resets to D1)
Shows current Abyss Tier
EthicalShop.tscn
Tab: "Convenience" (Auto-buyers, no power)
Tab: "Cosmetics" (Skins, titles, effects)
Currency: Abyss Points (earned) + Shards (premium)
DailyLimitsPanel.tscn
Transparent display: "4/4 hours available today"
Shows ad cap: "7/10 ads watched"
Builds trust by showing F2P get same daily benefits
Phase 3: Ad Integration (Week 3)
Rewarded Ad Placements (Max 10/day):
gdscript
Copy
# AdService.gd
enum AdType {
    SAVE_FROM_DEATH,    # Rewind 30s, avoid fail
    DOUBLE_OFFLINE,     # 8h -> 16h offline earnings
    PIGGY_BOOST,        # +50% to piggy bank instantly
    SHARD_BONUS         # +50 Shards (cosmetic currency)
}

func show_rewarded_ad(type: AdType) -> bool:
    if GameManager.ads_watched_today >= 10:
        return false
    
    # Show Unity/AdMob rewarded ad...
    GameManager.ads_watched_today += 1
    grant_reward(type)
    return true
Critical: On PC (Steam), replace with:
"Watch Trailer" for same rewards
Or Supporter Pack ($14.99) auto-grants daily ad rewards without watching
Phase 4: Abyss Content (Week 4)
AbyssShop.gd:
gdscript
Copy
extends Control

var items = [
    {
        "id": "auto_dive",
        "name": "Auto-Dive Module",
        "cost": 499,  # Shards (premium)
        "type": "convenience",
        "desc": "Auto-click dive button at 100%"
    },
    {
        "id": "void_theme",
        "name": "Void UI Theme", 
        "cost": 1000,
        "type": "cosmetic",
        "desc": "Dark matter aesthetic"
    }
]

func buy_item(id: String):
    if has_enough_shards(item.cost):
        deduct_shards(item.cost)
        unlock_item(item)
        GameManager.save_game()
Economy Balance Verification
Early Game (Tutorial)
Depth 1: 7 runs × 25 min = 3 hours total
Unlock D2 Cost: 350 Amethyst (requires ~5 runs)
2-Hour Checkpoint: Player has done 4 runs, needs 1 more to unlock D2
Mid Game (First Wall)
Depth 2: 35 runs × 30 min = 17 hours
Stabilize Level 10: Requires ~3,000 Ruby total
Player Experience: Learning instability management while grinding currency
Late Game (Abyss)
First D15: ~280 hours
Transcendence: Reset to D1 with 1.5x speed
D15 Again: ~180 hours (faster with multipliers)
Abyss Tier 10: ~50 hours to D15 (veteran speed)
Daily Engagement
F2P Player: 4 hours offline earnings (via 4 ads) + active play
Payer: 4 hours instant (same amount, convenience tax)
Piggy Bank: Breaks at ~500 thoughts = $4.99 worth
Monetization Products
Table
Copy
Product	Price	Description	Ethics Check
Supporter Pack	$9.99	Remove ads, auto-collect daily rewards, badge	✅ No power advantage
Time Warp	$0.99/hr	Skip 1-4 hours instantly (daily cap 4h)	✅ F2P gets same via ads
Piggy Bank Break	$4.99	Claim accumulated thoughts (10% of earnings)	✅ Visual progress system
Auto-Buyer Bundle	$19.99	Auto-dive, auto-overclock, auto-wake	✅ Saves clicks, not time
Season Pass	$8.99	Cosmetics only, 2x Abyss Points (cosmetic currency)	✅ No gameplay stats
Shard Pack	$4.99	500 Shards (cosmetic shop currency)	✅ Skins only
Anti-Cheat & Server Validation
Critical: Track daily caps server-side to prevent hacking.
gdscript
Copy
# EthicalMonetization.gd (Server-side)
func validate_purchase(user_id: String, hours: float) -> bool:
    var data = get_user_data(user_id)
    if data.purchased_today + hours > 4.0:
        return false  # Reject transaction
    
    data.purchased_today += hours
    save_user_data(user_id, data)
    return true
Sanity Checks:
Abyss Tier cannot be set directly (must calculate from D15 completions)
Daily purchased time resets at midnight UTC
Ad watch count validated against impression IDs
Revenue Projections
Conservative Scenario (10k DAU)
Month 6: $3k-8k/month
Year 1: $60k-100k
Platform: 60% Mobile ads, 40% Steam DLC
Target Scenario (40k DAU)
Month 6: $15k-25k/month
Year 1: $200k-300k
Breakdown: 50% Ad Removal, 30% Passes, 20% Cosmetics
Success Scenario (200k DAU)
Month 6: $80k-150k/month
Year 1: $1.2M-2.5M
Requires: Feature by Apple/Google or viral TikTok moment
Post-Launch LiveOps
Content Calendar
Month 2: Season 1 Pass (Void Theme)
Month 4: Abyss Tier expansion (new Corruption mechanics)
Month 6: Steam launch (premium pricing)
Month 8: Guilds/Collectives (social features)
Month 12: Season 4 + Mobile-PC cross-save
Events (Weekly Rotation)
Ruby Rush: Double Ruby crystals weekend
Stabilization: -50% instability gain (easier pushing)
Abyssal Surge: Double Abyss Points (transcend now)
Red Lines (Do Not Implement)
❌ Energy systems preventing play
❌ Gacha boxes with power items
❌ "VIP Level" with exclusive multipliers
❌ Pay-only upgrades (Depth access)
❌ Leaderboards that mix F2P and P2W scores
❌ Unlimited time warps (must have daily cap)
❌ Exclusive auto-buyers (F2P must earn via Abyss Points)
Success Checklist
Pre-Launch:
[ ] Cost formula updated (2.8^depth)
[ ] Piggy Bank implemented
[ ] Daily 4-hour cap enforced
[ ] Transcendence loop working
[ ] Supporter Pack ($9.99) configured
[ ] Ad placements at death/wake (max 10/day)
[ ] Separate leaderboards (Skill vs Collection)
Soft Launch Metrics (Target):
[ ] D1 Retention >40%
[ ] D7 Retention >15%
[ ] D30 Retention >8%
[ ] Conversion Rate >4%
[ ] ARPDAU >$0.10
Full Launch:
[ ] Steam version ready ($14.99 Supporter)
[ ] Season Pass infrastructure
[ ] Analytics tracking (Unity/GameAnalytics)
[ ] Community Discord/Reddit presence
Conclusion
This overhaul transforms Idle Dreamstate into an ethical money-maker by:
Respecting player time (no energy systems)
Capping advantages (4h daily limit)
Selling convenience (not power)
Infinite progression (Abyss tiers)