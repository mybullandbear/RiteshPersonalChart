import json
import os
from datetime import datetime

TRADING_STATE_FILE = "data/trading_state.json"

def log_message(msg):
    """Appends live status stream to bot_log.txt"""
    try:
        from datetime import datetime
        timestamp = datetime.now().strftime('%H:%M:%S')
        with open('data/bot_log.txt', 'a') as f:
            f.write(f"[{timestamp}] {msg}\n")
    except: pass

class PaperTrader:
    def __init__(self):
        self.config_file = "config.json"
        
    def load_trading_state(self):
        default_state = {
            "trading_enabled": True,
            "paper_trading": True, # Force reality
            "positions": {
                "NIFTY": None,
                "BANKNIFTY": None,
                "FINNIFTY": None
            }
        }
        if not os.path.exists(TRADING_STATE_FILE):
            return default_state
        try:
            with open(TRADING_STATE_FILE, 'r') as f:
                state = json.load(f)
                state['paper_trading'] = True
                return state
        except:
            return default_state

    def save_trading_state(self, state):
        try:
            with open(TRADING_STATE_FILE, 'w') as f:
                json.dump(state, f, indent=4)
        except Exception as e:
            print(f"Error saving trading state: {e}")

    def get_trading_status(self):
        state = self.load_trading_state()
        return state.get("trading_enabled", False)

    def set_trading_status(self, enabled):
        state = self.load_trading_state()
        state["trading_enabled"] = enabled
        self.save_trading_state(state)

    def execute_trade(self, signal_data, symbol, expiry_date, reason="Auto Signal"):
        """Paper Execution Logic."""
        state = self.load_trading_state()
        
        # Check Active Position
        if state.get("positions", {}).get(symbol):
            return

        signal = signal_data.get('signal', '')
        atm_strike = signal_data.get('atm', 0)
        option_price = signal_data.get('atm_option_price', 0)
        
        if not atm_strike or atm_strike == 0:
            return
            
        action = None
        if "SELL CALL" in signal or "BUY PUT" in signal or "Bearish" in signal:
            action = "SELL_CE"
        elif "SELL PUT" in signal or "BUY CALL" in signal or "Bullish" in signal:
            action = "SELL_PE"
        elif "SELL BOTH" in signal or "WAIT" in signal or "NEUTRAL" in signal:
            return

        if not action:
            return

        option_type = "CE" if action == "SELL_CE" else "PE"
        
        # 🚀 Dynamic Sizing and Risk Values
        nifty_lot = 65
        banknifty_lot = 30
        finnifty_lot = 40
        try:
            with open("config.json", 'r') as f:
                c = json.load(f)
                nifty_lot = c.get("NIFTY_LOT", 65)
                banknifty_lot = c.get("BANKNIFTY_LOT", 30)
                finnifty_lot = c.get("FINNIFTY_LOT", 40)
        except: pass
        
        if symbol == "NIFTY": quantity = nifty_lot
        elif symbol == "BANKNIFTY": quantity = banknifty_lot
        else: quantity = finnifty_lot
        
        # Record paper trade
        if "positions" not in state: state["positions"] = {}
        state["positions"][symbol] = {
            "type": option_type,
            "strike": atm_strike,
            "trading_symbol": f"PAPER_{symbol}_{atm_strike}_{option_type}",
            "entry_price": option_price,
            "quantity": quantity,
            "highest_profit": 0,
            "current_profit": 0,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "snapshot_timestamp": signal_data.get('ts_of_row', "N/A"),
            "entry_reason": reason
        }
        self.save_trading_state(state)
        log_message(f"🚀 {symbol} Entry: SELL {option_type} {atm_strike} @ {option_price} (Reason: {reason})")
        print(f"[{symbol}] Paper Entry: SELL {option_type} {atm_strike} @ {option_price}")
        
    def update_pnl(self, symbol, current_ltp):
        """Calculates P&L for Paper Trade."""
        state = self.load_trading_state()
        pos = state.get("positions", {}).get(symbol)
        if not pos: return
        
        entry_price = pos["entry_price"]
        quantity = pos["quantity"]
        
        # We are SELLING options. Profit = (Entry - Current) * Qty
        current_profit = (entry_price - current_ltp) * quantity
        
        highest_profit = pos.get("highest_profit", 0)
        if current_profit > highest_profit:
            highest_profit = current_profit
            
        pos["current_profit"] = current_profit
        pos["highest_profit"] = highest_profit
        self.save_trading_state(state)
        
        # 🚀 Risk Management Overrides
        stop_loss_limit = 1500 # Absolute value
        try:
            with open("config.json", 'r') as f:
                stop_loss_limit = json.load(f).get("STOP_LOSS", 1500)
        except: pass

        # 1. Hard Stop-Loss Guard (Loss limit hit)
        if current_profit <= -abs(stop_loss_limit):
            print(f"[{symbol}] HARD STOP LOSS HIT (₹{current_profit:,.2f})! Exiting Position...")
            self.exit_position(symbol, reason=f"Hard Stop-Loss (₹{stop_loss_limit})")
            return

        # 2. Existing Trailing SL 
        if highest_profit >= 3000 and current_profit <= 2000:
            print(f"[{symbol}] Trailing SL Hit in Paper Trade! Exiting...")
            self.exit_position(symbol, reason="Trailing SL (Peak ₹3000 -> Pullback ₹2000)")
            
    def log_trade_history(self, pos, exit_price, exit_reason):
        """Saves trade to trade_history.json"""
        history_file = "data/trade_history.json"
        history = []
        if os.path.exists(history_file):
            try:
                with open(history_file, 'r') as f: history = json.load(f)
            except: pass
            
        trade_entry = {
            "symbol": pos.get("trading_symbol", ""),
            "type": pos.get("type", ""),
            "strike": pos.get("strike", 0),
            "quantity": pos.get("quantity", 0),
            "entry_price": pos.get("entry_price", 0),
            "exit_price": round(exit_price, 2),
            "profit": round((pos.get("entry_price", 0) - exit_price) * pos.get("quantity", 0), 2),
            "highest_profit": pos.get("highest_profit", 0),
            "entry_time": pos.get("timestamp", ""),
            "exit_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "entry_reason": pos.get("entry_reason", "Auto Signal"),
            "exit_reason": exit_reason,
            "snapshot_timestamp": pos.get("snapshot_timestamp", "N/A")
        }
        history.append(trade_entry)
        try:
            with open(history_file, 'w') as f: json.dump(history, f, indent=4)
        except: pass

    def exit_position(self, symbol, reason="Manual Close"):
        """Exits the paper position."""
        state = self.load_trading_state()
        pos = state.get("positions", {}).get(symbol)
        if pos:
            try:
                # current_profit = (entry - current) * qty  =>  current = entry - (profit / qty)
                current_ltp = pos.get("entry_price", 0) - (pos.get("current_profit", 0) / pos.get("quantity", 1))
                self.log_trade_history(pos, current_ltp, reason)
            except: pass
            
            state["positions"][symbol] = None
            self.save_trading_state(state)
            log_message(f"🛑 {symbol} Position Closed: {reason}")
            print(f"[{symbol}] Paper Position Closed: {reason}")
            


trader = PaperTrader()
