#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

json=$(nix eval --json -f scripts/gen-flow.nix)

# Inject the generated JSON between the matching script tags in each doc.
# index.html renders the flow diagram (ignores the extra `options` field);
# settings.html renders the interactive settings showcase.
python3 -c "
import sys, re

json = sys.argv[1]

def inject(path, script_id):
    html = open(path).read()
    pattern = r'(<script id=\"' + script_id + r'\" type=\"application/json\">)\n.*?\n(</script>)'
    # Function replacement avoids re.sub backslash interpretation in the JSON.
    result, n = re.subn(pattern, lambda m: m.group(1) + '\n' + json + '\n' + m.group(2), html, flags=re.DOTALL)
    if n != 1:
        sys.exit(f'{path}: expected 1 {script_id} block, found {n}')
    open(path, 'w').write(result)

inject('docs/index.html', 'flow-data')
" "$json"
# inject('docs/settings.html', 'settings-data')
