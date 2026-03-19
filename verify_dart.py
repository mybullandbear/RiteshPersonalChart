import re

with open(r"c:\Projects\OldNSESystemforTrading-main\OldNSESystemforTrading-main\flutter_frontend\lib\main.dart", 'r', encoding='utf-8') as f:
    content = f.read()

# 🧼 Strip all strings (single, double, triple quotes) to avoid inside-string bracket triggers
content_no_str = re.sub(r'"""(.*?)"""', '""', content, flags=re.DOTALL)
content_no_str = re.sub(r'"(.*?)"', '""', content_no_str)
content_no_str = re.sub(r"'(.*?)'", "''", content_no_str)

# Split back to lines
lines = content_no_str.split('\n')

current_paren = 0
for i, line in enumerate(lines):
    if "//" in line:
        continue
    o_p = line.count('(')
    c_p = line.count(')')
    current_paren += (o_p - c_p)
    
    if current_paren < 0:
         print(f"🔴 UNDERFLOW AT LINE {i+1}: Paren level = {current_paren} | Content: {line.strip()}")
    elif current_paren > 0 and i > 500 and i < 650:
         print(f"Line {i+1}: Paren level = {current_paren} | Content: {line.strip()}")

print(f"Final Paren Balance = {current_paren}")

