#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

json=$(nix eval --json -f scripts/gen-flow.nix)

# Replace the @@FLOW_DATA@@ placeholder (or existing JSON) between the flow-data script tags
python3 -c "
import sys, re

html = open('docs/index.html').read()
pattern = r'(<script id=\"flow-data\" type=\"application/json\">)\n.*?\n(</script>)'
replacement = r'\1\n' + sys.argv[1] + r'\n\2'
result = re.sub(pattern, replacement, html, flags=re.DOTALL)
open('docs/index.html', 'w').write(result)
" "$json"
