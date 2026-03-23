import os
import json
from datetime import datetime, time
from sqlalchemy import create_with_driver
from sqlalchemy.orm import sessionmaker

# Import models from app.py
from app import OptionChainData, get_db_engine

def run_backtest(symbol="NIFTY", lookback_days=5):
    """
    Simulates trades on historical option chain snapshots.
    """
    stats = {
        "total_trades": 0,
        "wins": 0,
        "losses": 0,
        "total_pnl": 0.0,
        "trades": []
    }

    # 1. Gather relevant date databases
    data_dir = "data"
    if not os.path.exists(data_dir): return stats

    date_files = [f for f in os.listdir(data_dir) if f.startswith("option_chain_") and f.endswith(".db")]
    if not date_files: return stats
    
    date_files.sort(reverse=True) # newest first
    date_files = date_files[:lookback_days]
    date_files.sort() # replay oldest to newest

    active_position = None
    max_loss_allowed = 0
    highest_profit = 0

    for db_file in date_files:
        db_path = os.path.join(data_dir, db_file)
        # Dynamic engine
        engine = get_db_engine(db_file.replace("option_chain_","").replace(".db",""))
        Session = sessionmaker(bind=engine)
        session = Session()

        try:
            # Load snapshots ordered forwards
            timestamps = session.query(OptionChainData.timestamp).filter(
                OptionChainData.symbol == symbol
            ).distinct().order_by(OptionChainData.timestamp.asc()).all()

            for ts_row in timestamps:
                ts = ts_row[0]
                rows = session.query(OptionChainData).filter(
                    OptionChainData.symbol == symbol,
                    OptionChainData.timestamp == ts
                ).all()

                if not rows: continue

                # --- 🧮 1. Calculate Signal & Confluence (Simplified version of app.py) ---
                spot = rows[0].underlying_price
                atm = min(rows, key=lambda x: abs(x.strike_price - spot), default=None)
                if not atm: continue

                sorted_rows = sorted(rows, key=lambda x: x.strike_price)
                atm_index = sorted_rows.index(atm)
                near_rows = sorted_rows[max(0, atm_index-5):min(len(rows), atm_index+6)]

                pe_chg = sum(r.pe_change_oi or 0 for r in near_rows)
                ce_chg = sum(r.ce_change_oi or 0 for r in near_rows)

                signal = 'NEUTRAL'
                if pe_chg > 0 and (ce_chg <= 0 or pe_chg > ce_chg * 1.15): signal = 'SELL PE'
                elif ce_chg > 0 and (pe_chg <= 0 or ce_chg > pe_chg * 1.15): signal = 'SELL CE'

                total_ce = sum(r.ce_oi or 0 for r in rows)
                total_pe = sum(r.pe_oi or 0 for r in rows)
                pcr = total_pe / total_ce if total_ce > 0 else 0

                confluence = 65
                if signal == 'SELL PE':
                    if pcr > 0.9: confluence += 5
                elif signal == 'SELL CE':
                    if pcr < 1.0: confluence += 5

                # --- 🛡️ 2. Manage Risk (Exit Conditions) ---
                if active_position:
                    # Fetch current price of held strike
                    held_strike = active_position['strike']
                    curr_row = next((r for r in rows if r.strike_price == held_strike), None)
                    current_price = 0
                    if curr_row:
                        current_price = curr_row.ce_last_price if active_position['type'] == 'CE' else curr_row.pe_last_price
                    
                    if current_price > 0:
                        entry = active_position['entry_price']
                        qty = active_position['qty']
                        pnl = (entry - current_price) * qty
                        highest_profit = max(highest_profit, pnl)

                        # SL Check
                        if pnl <= -active_position['max_loss']:
                            stats['losses'] += 1
                            stats['total_pnl'] += pnl
                            stats['trades'].append({**active_position, "exit_price": current_price, "pnl": pnl, "exit": "SL"})
                            active_position = None
                        # Break-even check
                        elif highest_profit >= (entry * qty * 0.3) and pnl <= 0:
                            stats['wins'] += 1 if pnl >= 0 else 0 # though strictly near zero
                            stats['total_pnl'] += pnl
                            stats['trades'].append({**active_position, "exit_price": current_price, "pnl": pnl, "exit": "BE"})
                            active_position = None
                
                # --- ⚡ 3. Auto Entry Logic ---
                if not active_position and confluence >= 70 and signal != 'NEUTRAL':
                    if signal == 'SELL PE':
                        entry_price = atm.pe_last_price or 0
                        type = 'PE'
                    elif signal == 'SELL CE':
                        entry_price = atm.ce_last_price or 0
                        type = 'CE'

                    if entry_price > 0:
                        active_position = {
                            "symbol": symbol, "type": type, "strike": atm.strike_price,
                            "entry_price": entry_price, "qty": 50,
                            "max_loss": entry_price * 50 * 0.5, "entry_time": ts.strftime('%m-%d %H:%M')
                        }
                        highest_profit = 0
                        stats['total_trades'] += 1

        except Exception as e:
            print(f"Error simulation on {db_file}: {e}")
        finally:
            session.close()

    total_pnl = sum(t['pnl'] for t in stats['trades'])
    stats['total_pnl'] = round(total_pnl, 2)
    if stats['total_trades'] > 0:
        stats['win_rate'] = round((stats['wins'] / stats['total_trades']) * 100, 1) if stats['wins'] > 0 else 0
    else: stats['win_rate'] = 0

    return stats
