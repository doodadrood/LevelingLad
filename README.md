# Leveling Lad (LL) — World of Warcraft TradeSkill Leveling Optimizer

**Leveling Lad** is a World of Warcraft (Classic Era / WoW: Forever, Interface `16001`) profession-leveling optimizer built on the proven architecture of **Profitable (PF)**. It calculates the absolute lowest net gold path to level professions from **1 to 300**, guards against material over-buying, enforces NPC vendor pricing on vendor reagents, walks live Auction House order books, and automatically alerts/halts crafting when target skill ranks are reached.

---

## Features

- **Top 5 Cheapest Leveling Plays (Docked AH Side Window)**: Evaluates known and trainer-learnable recipes and ranks them by lowest **Net Cost per Skill Point (CPSP)**.
- **Dynamic Skillup Probability & Over-Buy Prevention**:
  - Models exact Orange (`100%`), Yellow (`max(0.50, (gray - S)/(gray - yellow))`), Green (`max(0.10, (gray - S)/(2*(gray - yellow)))`), and Gray (`0%`) curves.
  - Strictly enforces a **Hard Gray Cutoff** (0 crafts allowed once a recipe turns Gray).
  - **Trainer Lookahead ("The Green/Yellow Trap")**: Automatically caps recipes right at transition points when a trainer unlocks a cheaper Orange recipe.
- **NPC Vendor Reagent Protection**: Built-in `Data/VendorDatabase.lua` guarantees items like *Coarse Thread, Weak Flux, Leaded Vial, Mild Spices, Coal,* and *Salt* are always priced at NPC vendor rates (updated dynamically on `MERCHANT_SHOW`), never at inflated AH prices.
- **Stepped Order-Book AH Verification & Dynamic Circuit Breaker**: Walks live AH price tiers unit-by-unit and automatically alerts/pivots if deeper price tiers spike CPSP above the #2 candidate play.
- **Multi-Step Milestone Roadmap**: Chains optimal recipes from your current skill to the next bracket (`75 / 150 / 225 / 300`) or custom target while enforcing your gold budget cap.
- **Persistent Shopping & Crafting Tracker**:
  - Detachable window tracking `Need | Bags | Mail | Buy` across bags, bank, and mailbox.
  - 1-Click **Search AH** button per reagent and clear `[AH]` vs `[Vendor]` badges.
  - Taint-free **Open Recipe** & **Craft All** buttons with live `CHAT_MSG_SKILL` tracking and **Smart Abort** alerts when lucky skillups hit your target early.
- **Embedded PriceCheckerForever (PCF)**: Bundles PCF via `.pkgmeta` externals and isolates globals cleanly when standalone PCF, TSM, or Auctionator is already installed.

---

## Supported Professions (1–300)

- Blacksmithing (`164`)
- Tailoring (`197`)
- Leatherworking (`165`)
- Alchemy (`171`)
- Engineering (`202`)
- Cooking (`185`)
- Enchanting (`333`)
- First Aid (`129`)
- Mining / Smelting (`186`)

---

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/ll` or `/levelinglad` | Toggle the Leveling Lad AH side window |
| `/ll run` | Calculate and display the Top 5 cheapest leveling plays |
| `/ll roadmap [target]` | Plan a chained multi-step milestone roadmap (e.g. `/ll roadmap 150`) |
| `/ll detail N` | Open the persistent shopping & crafting tracker for play `#1`–`#5` |
| `/ll budget <amount\|auto>` | Set max spending budget (e.g. `/ll budget 25g` or `/ll budget auto`) |
| `/ll target <+5\|+10\|milestone\|N>` | Set leveling target goal |
| `/ll recovery <vendor\|ah\|none>` | Set output resale recovery strategy (default: `vendor`) |
| `/ll prof <name>` | Select the profession to optimize |
| `/ll scan` | Start a PCF AH scan (when at AH) or recalculate plays |

---

## Headless Testing (LuaJIT)

Run the complete test suite without launching World of Warcraft:

```bash
luajit Tests/Test_Suite.lua
```
