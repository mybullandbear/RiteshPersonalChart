import re

with open(r"c:\Projects\OldNSESystemforTrading-main\OldNSESystemforTrading-main\flutter_frontend\lib\main.dart", 'r', encoding='utf-8') as f:
    content = f.read()

# 🧼 Strip all strings (single, double, triple quotes) to avoid inside-string bracket triggers
content_no_str = re.sub(r'"""(.*?)"""', '""', content, flags=re.DOTALL)
content_no_str = re.sub(r'"(.*?)"', '""', content_no_str)
content_no_str = re.sub(r"'(.*?)'", "''", content_no_str)

# Split back to lines
lines = content_no_str.split('\n')

curly_stack = []

for i, line in enumerate(lines):
    if "//" in line: continue
    
    for char in line:
        if char == '{':
            curly_stack.append(i + 1)
        elif char == '}':
            if curly_stack:
                curly_stack.pop()

print("Unclosed '{' on lines:", curly_stack)

