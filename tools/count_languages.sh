#!/usr/bin/env bash
# tools/count_languages.sh - Language composition counter for OCamlOS

set -e

count_lines() {
    ext=$1
    find . -type f -name "*.$ext" -not -path "*/build/*" -not -path "*/.git/*" | xargs wc -l 2>/dev/null | tail -n 1 | awk '{print $1}'
}

ml_lines=$(count_lines "ml" || echo 0)
s_lines=$(count_lines "S" || echo 0)
c_lines=$(count_lines "c" || echo 0)

ml_lines=${ml_lines:-0}
s_lines=${s_lines:-0}
c_lines=${c_lines:-0}

total_lines=$((ml_lines + s_lines + c_lines))

if [ "$total_lines" -eq 0 ]; then
    echo "No source code found."
    exit 1
fi

ml_pct=$(awk "BEGIN {printf \"%.2f\", ($ml_lines / $total_lines) * 100}")
s_pct=$(awk "BEGIN {printf \"%.2f\", ($s_lines / $total_lines) * 100}")
c_pct=$(awk "BEGIN {printf \"%.2f\", ($c_lines / $total_lines) * 100}")

echo "========================================================"
echo "           OCamlOS Language Composition Audit           "
echo "========================================================"
printf "OCaml (.ml):    %6d lines (%6s%%)\n" "$ml_lines" "$ml_pct"
printf "Assembly (.S):  %6d lines (%6s%%)\n" "$s_lines" "$s_pct"
printf "C (.c):         %6d lines (%6s%%)\n" "$c_lines" "$c_pct"
echo "--------------------------------------------------------"
printf "Total Source:   %6d lines (100.00%%)\n" "$total_lines"
echo "========================================================"
