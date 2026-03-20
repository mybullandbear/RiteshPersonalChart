import sys

file_path = 'flutter_frontend/lib/main.dart'
lines = open(file_path, encoding='utf-8').readlines()

start_idx = 949 # Line 950
end_idx = 1002  # Line 1003

replacement = """  @override
  Widget build(BuildContext context) {
    if (widget.summary == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: _Spinner(size: 24)),
      );
    }

    final sc = _sColor(widget.summary?.color);
    final String sig = widget.summary!.signal.toUpperCase();
    final bool isStrongSignal = sig.contains(RegExp(r'BUY|SELL|STRONG'));
    
    String mainWord = sig;
    if (sig.contains('(')) {
       mainWord = sig.split('(')[0].trim();
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kSurface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sc.withOpacity(0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4, height: 16,
                          decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 8),
                        Text(widget.symbol == 'BANKNIFTY' ? 'BNF' : 'NFT', style: TextStyle(color: widget.accent, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Text(mainWord, style: TextStyle(color: sc, fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    if (isStrongSignal) ...[
                      Material(
                        color: sc,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: widget.summary!.atm == null ? null : () async {
                             playAlertSound();
                             await ApiService().executeTrade(widget.symbol, sig, widget.summary!.atm!);
                          },
                          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('EXE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (widget.summary!.suggestedStrike != null) ...[
                      Text('🎯 ${widget.summary!.suggestedStrike!.toStringAsFixed(0)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                    ],
                    Text('Spot: ${NumberFormat("#,##0").format(widget.summary!.spot)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 12),
                    Text('PCR: ${widget.summary!.pcr.toStringAsFixed(2)}', style: TextStyle(color: widget.summary!.pcr > 1.0 ? kGreen : kRed, fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
"""

lines[start_idx:end_idx+1] = [replacement + '\n']

open(file_path, 'w', encoding='utf-8').writelines(lines)
print("Updated successfully")
