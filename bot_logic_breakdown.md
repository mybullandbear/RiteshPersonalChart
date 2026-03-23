# 🤖 COMPLETE TRADING BOT LOGIC BREAKDOWN

This document outlines **how the bot calculates signals** and **how it executes paper trades** under the hood. 

---

## 📊 PHASE 1: SIGNAL GENERATION (`app.py`)
Signals inside your dashboard are calculated using **Near-ATM Option Chain Changes in Open Interest (OI)**.

1.  **Locate ATM Strike:** Finds the strike closest to the current spot price.
2.  **Zone Scanning Range:** Inspects **5 strikes above and 5 strikes below** the ATM position (Total 11 strikes scanned).
3.  **Summing Active Flow:** Adds up the absolute continuous *Increase or Decrease* in Put (`sum_pe_chg_oi`) and Call (`sum_ce_chg_oi`) contracts across that zone.
4.  **Signal Mapping Rules:**
    *   🔴 **`SELL CE (Bearish)`**: Call writers are flooding in, capping the roof.
        *   *Condition:* `sum_ce_chg_oi > 0` AND (no put change OR `ce_chg > pe_chg * 1.15`)
    *   🟢 **`SELL PE (Bullish)`**: Put writers are flooding in, supporting the floor.
        *   *Condition:* `sum_pe_chg_oi > 0` AND (no call change OR `pe_chg > ce_chg * 1.15`)
    *   🟡 **`SELL BOTH (Range)`**: Heavy overlapping accumulation on both sides.
    *   ⚪ **`NEUTRAL`**: Absolute noise or weak inactivity in that 10-zone range.

---

## 📐 PHASE 2: CONFLUENCE SCORING (`app.py`)
Confluence weights the current Signal against broader absolute volumes as a safety barrier (0-100%). It starts at a baseline of **65 points**:

*   **Bullish Scenario (`SELL PE`):**
    *   `+15 points` if total PCR is strictly greater than `1.1`
    *   `+5 points` if total PCR is greater than `0.9`
    *   `+20 points` if the 5-minute spot trend is going Up (`Spot Price > Past Spot`).
*   **Bearish Scenario (`SELL CE`):**
    *   `+15 points` if total PCR is strictly lower than `0.8`
    *   `+5 points` if total PCR is lower than `1.0`
    *   `+20 points` if the 5-minute spot trend is dipping Down (`Spot Price < Past Spot`).

---

## ⚡ PHASE 3: AUTOMATIC EXECUTION (`app.py` & `zerodha_trader.py`)
The bot triggers automatically if **Auto-Trading is enabled** and your constraints align perfectly.

1.  **Check Interval Loop:** Every ticks loop triggers an auto-trade check.
2.  **Trigger Limits Threshold:**
    *   Position must **Not already be held** for that index.
    *   Signal must be directionally absolute (`SELL CE` or `SELL PE`).
    *   **Rule Barrier:** **`Confluence >= 70%`** (Prevents entering false breakouts inside Chop ranges).
3.  **Order Placement sizing:**
    *   Bot pulls lot sizing configurations from `config.json` (e.g., NIFTY = 65, BANKNIFTY = 30).
4.  **Sells the ATM Option Structure:**
    *   If Bearish signal -> SELLS Call Option (`SELL_CE`) locking the premium credit.
    *   If Bullish signal -> SELLS Put Option (`SELL_PE`) locking the premium credit.

---

## 🛡️ PHASE 4: RISK MANAGEMENT & EXIT CONDITIONS (`zerodha_trader.py`)
Once a trade is live, the bot continuously updates unrealized P&L and guards your equity.

*   **P&L Calculation (Sell orders):** `(Entry Price - Current LTP) * Quantity`
*   **Safety Guards triggers:**
    1.  **Hard Stop Loss Exits:** Closely monitors absolute losses against a fixed risk trigger inside `config.json` (e.g. `₹1500` maximum risk tolerance limit). If hit, triggers direct execution Close immediately!
    2.  **Trailing Profit Protections:** Breaks layout if peak profits begin dragging excessively backwards to lock in green cycles (Trailing limit parameters).
    3.  **Absolute Trend Reversal Exits:** If the dashboard issues an `exit_alert` (e.g., a bullish loop receives a abrupt -10 point flush), the bot forcefully exits to neutralize risk securely.

---

*(All files updated to Git continuously aligned to these rules!)*
