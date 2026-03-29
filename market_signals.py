from datetime import datetime, timedelta
import pandas as pd

def calculate_signal(session, symbol, timestamp, OptionChainData):
    """
    Calculates the trading signal for a given symbol and timestamp.
    Logic duplicated from app.py to ensure consistency without importing app.py.
    """
    try:
        # Find the closest record within a +/- 60 second window
        time_window = timedelta(seconds=60)
        
        records = session.query(OptionChainData)\
            .filter(
                OptionChainData.symbol == symbol, 
                OptionChainData.timestamp >= timestamp - time_window,
                OptionChainData.timestamp <= timestamp + time_window
            )\
            .all()
        
        if not records:
            return {'signal': 'No Data', 'color': 'gray', 'spot': 0, 'atm': 0}
        
        unique_timestamps = list(set([r.timestamp for r in records]))
        closest_ts = min(unique_timestamps, key=lambda t: abs(t - timestamp))
        
        # Now filter records for ONLY that closest timestamp
        symbol_records = [r for r in records if r.timestamp == closest_ts]
        
        if not symbol_records:
             return {'signal': 'No Data', 'color': 'gray', 'spot': 0, 'atm': 0}

        spot_price = symbol_records[0].underlying_price
        spot_price = symbol_records[0].underlying_price
        atm_record = min(symbol_records, key=lambda x: abs(x.strike_price - spot_price))
        
        # Get Expiry Date (Assuming all records in this batch have same expiry, or take from ATM)
        expiry_date = atm_record.expiry_date
        
        # 🚀 Aggregated Multi-Strike Option Chain Sentiment
        # Instead of 1 contract, we sum up nearest 5 strikes above and 5 below SPOT price.
        sorted_records = sorted(symbol_records, key=lambda x: x.strike_price)
        atm_index = sorted_records.index(atm_record)
        
        start_idx = max(0, atm_index - 5)
        end_idx = min(len(sorted_records), atm_index + 6)
        near_strikes = sorted_records[start_idx:end_idx]
        
        sum_ce_chg_oi = sum(r.ce_change_oi or 0 for r in near_strikes)
        sum_pe_chg_oi = sum(r.pe_change_oi or 0 for r in near_strikes)
        
        # Determine Dynamic Ratios from Config
        signal_ratio = 1.15
        try:
            import json
            if os.path.exists("config.json"):
                with open("config.json", 'r') as f:
                    signal_ratio = json.load(f).get("SIGNAL_RATIO", 1.5)
        except: pass

        # Identify dominant market writing action
        ce_signal = ""
        if sum_ce_chg_oi > 0 and (sum_pe_chg_oi <= 0 or sum_ce_chg_oi > sum_pe_chg_oi * signal_ratio):
             ce_signal = "SELL CALL" # Bearish Sentiment
             
        pe_signal = ""
        if sum_pe_chg_oi > 0 and (sum_ce_chg_oi <= 0 or sum_pe_chg_oi > sum_ce_chg_oi * signal_ratio):
             pe_signal = "SELL PUT" # Bullish Sentiment
            
        # Conflict Resolution / Priority
        final_signal = "WAIT"
        color = "gray"
        
        if ce_signal and not pe_signal:
            final_signal = "SELL CE (Bearish)"
            color = "red" # Market going down
        elif pe_signal and not ce_signal:
            final_signal = "SELL PE (Bullish)"
            color = "green" # Market going up
        elif ce_signal and pe_signal:
            final_signal = "SELL BOTH (Range)"
            color = "orange"
        else:
            # Secondary Logic: Long Buildup (Green in table)
            # CE Long Buildup: Price > 0, OI > 0 -> BUY CE (Bullish)
            # PE Long Buildup: Price > 0, OI > 0 -> BUY PE (Bearish)
            
            is_ce_long = atm_record.ce_change > 0 and atm_record.ce_change_oi > 0
            is_pe_long = atm_record.pe_change > 0 and atm_record.pe_change_oi > 0
            
            if is_ce_long and not is_pe_long:
                final_signal = "BUY CE (Bullish)"
                color = "green"
            elif is_pe_long and not is_ce_long:
                final_signal = "BUY PE (Bearish)"
                color = "red"
            else:
                final_signal = "NEUTRAL"
                color = "#94a3b8"

        # Determine relevant option price for display
        atm_option_price = 0
        signal_type = "NONE"
        
        if "CE" in final_signal or "CALL" in final_signal:
            atm_option_price = atm_record.ce_last_price
            signal_type = "CE"
        elif "PE" in final_signal or "PUT" in final_signal:
            atm_option_price = atm_record.pe_last_price
            signal_type = "PE"

        # --- Advanced Metrics: PCR & Max Pain ---
        # Need all records for this timestamp to calculate accurately
        pcr = 0
        max_pain = 0
        total_ce_oi = 0
        total_pe_oi = 0

        try:
            current_time_records = [r for r in records if r.timestamp == closest_ts]
            
            total_ce_oi = sum(r.ce_oi for r in current_time_records if r.ce_oi)
            total_pe_oi = sum(r.pe_oi for r in current_time_records if r.pe_oi)
            
            if total_ce_oi > 0:
                pcr = round(total_pe_oi / total_ce_oi, 2)
            
            # Max Pain Calculation
            strikes = [r.strike_price for r in current_time_records]
            min_loss = float('inf')
            
            # Optimization: Only calculate if reasonable number of records
            if len(strikes) > 0:
                for expiry_price in strikes:
                    total_loss = 0
                    for r in current_time_records:
                        if expiry_price > r.strike_price:
                                total_loss += (expiry_price - r.strike_price) * (r.ce_oi or 0)
                        elif expiry_price < r.strike_price:
                                total_loss += (r.strike_price - expiry_price) * (r.pe_oi or 0)
                    
                    if total_loss < min_loss:
                        min_loss = total_loss
                        max_pain = expiry_price

        except Exception as metric_err:
            print(f"Error calculating metrics: {metric_err}")

        return {
            'signal': final_signal,
            'color': color,
            'spot': spot_price,
            'atm': atm_record.strike_price,
            'atm_option_price': atm_option_price,
            'signal_type': signal_type,
            'ce_ltp': atm_record.ce_last_price,
            'pe_ltp': atm_record.pe_last_price,
            'pcr': pcr,
            'max_pain': max_pain,
            'total_ce_oi': total_ce_oi,
            'total_ce_oi': total_ce_oi,
            'total_pe_oi': total_pe_oi,
            'expiry_date': expiry_date
        }

    except Exception as e:
        print(f"Error calculating signal for {symbol}: {e}")
        return {
            'signal': 'Error', 
            'color': 'gray', 
            'spot': 0, 
            'atm': 0, 
            'atm_option_price': 0, 
            'signal_type': 'NONE',
            'pcr': 0,
            'pcr': 0,
            'max_pain': 0,
            'expiry_date': None
        }
