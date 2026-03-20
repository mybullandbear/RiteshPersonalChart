# Dashboard Signal Logic Breakdown

This document details the exact mathematical formulas and conditions used to generate the values, gauges, and alerts on your Trading Dashboard.

---

## 🟢 1. Top Row: Signals (e.g., `SELL PE`, `SELL CE`)
Calculated dynamically in the backend (`app.py`) using **Near-ATM Option Chain Changes in Open Interest (OI)**.

1.  **ATM Strike Location:** Determines which strike is closest to the current spot price.
2.  **Look-Back Range:** Scans **5 strikes up and 5 strikes down** from the ATM position.
3.  **Sum of Change in OI:** Adds up the total continuous *Increase or Decrease* in Put (`sum_pe_chg_oi`) and Call (`sum_ce_chg_oi`) contracts across that zone.
4.  **Signal Mapping:**
    *   **`SELL CE (Bearish)`**: Call writers are flooding in, and Put writers are inactive.
        *   *Condition:* `sum_ce_chg_oi > 0` AND (no put change OR `ce_chg > pe_chg * 1.15`)
    *   **`SELL PE (Bullish)`**: Put writers are flooding in, and Call writers are sitting quiet.
        *   *Condition:* `sum_pe_chg_oi > 0` AND (no call change OR `pe_chg > ce_chg * 1.15`)
    *   **`SELL BOTH (Range)`**: Both sides are writing heavily, forming a straddle/strangle cap layout.
    *   **`NEUTRAL`**: No major bias gap forming in that zone.

---

## 🔴 2. Triple Index Alignment (Top Card)
Calculated strictly using total absolute **PCR (Put-Call Ratio)** mapped to a 0–100 percentile scale.

1.  **Formula per Index:** `Score = (((PCR - 0.5) / 1.0) * 100).clamp(0, 100)`
    *   If PCR = `0.78`, then `0.78 - 0.5 = 0.28` -> **28% Score**.
2.  **Bubble Color:**
    *   🟢 Green if PCR exceeds `1.0` (Puts exceed Calls absolute total).
    *   🔴 Red if PCR sitting strictly below `1.0`.
3.  **Bias Title:**
    *   🟢 `BULLISH BIAS` if the Average score > 50%.
    *   🔴 `BEARISH BIAS` if the Average score < 50%.

---

## 🟡 3. Strategy Banner (e.g., `NEUTRAL (Range)`)
Determined by the **Composite Index Score** inside `main.dart`. It evaluates overall averages to avoid executing trades in Chop-Zones.

*   🟢 `SELL PUT / BUY CE` : Average Score > 65%
*   🔴 `SELL CALL / BUY PE` : Average Score < 35%
*   🟡 `NEUTRAL (Range)`      : Average Score is in the middle zone (35% to 65%).

---

## 🥊 4. ATM Battleground
Compares the raw Option Total volume currently writing at the absolute ATM Strike for Call writers vs Put writers.
*   **Scale Bar:** Red implies Call writers (resistance), Green implies Put writers (support). 
*   Displays the lead offset strictly to gauge whether Bulls or Bears are winning the absolute ATM zone right now.

---

## ⏳ 5. MTF Trend Matrix
Compares the current Spot Price to a smooth **5-period Simple Moving Average (SMA)** on four timelines (5m, 15m, 1H, Daily).
*   🟢 **Bullish** if `Spot Price > 5-SMA`
*   🔴 **Bearish** if `Spot Price < 5-SMA`
