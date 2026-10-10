#!/usr/bin/env bash
#
# sar_metrics_loop.sh — Export N days of CPU + memory metrics from sar into CSV.
#
# Output columns:
#   Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused

set -euo pipefail

DAYS=14
OUT="metrics_$(date +%Y%m%d).csv"
SA_DIR=""

while getopts ":d:o:s:h" opt; do
    case $opt in
        d) DAYS=$OPTARG ;;
        o) OUT=$OPTARG ;;
        s) SA_DIR=$OPTARG ;;
        h) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Usage: $0 [-d DAYS] [-o OUTPUT.csv] [-s SA_DIR]" >&2; exit 1 ;;
    esac
done

command -v sar >/dev/null || { echo "Error: sar not found (install sysstat)" >&2; exit 1; }

if [[ -z $SA_DIR ]]; then
    for dir in /var/log/sa /var/log/sysstat; do
        [[ -d $dir ]] && { SA_DIR=$dir; break; }
    done
fi
[[ -d ${SA_DIR:-} ]] || { echo "Error: sa directory not found (use -s)" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export LC_ALL=C S_TIME_FORMAT=ISO

# Return a readable sa file path for a day number, decompressing if needed.
resolve_file() {
    local base="$SA_DIR/sa$1"
    if   [[ -f $base     ]]; then echo "$base"
    elif [[ -f $base.xz  ]]; then xz    -dc "$base.xz"  > "$TMP/sa$1" && echo "$TMP/sa$1"
    elif [[ -f $base.gz  ]]; then gzip  -dc "$base.gz"  > "$TMP/sa$1" && echo "$TMP/sa$1"
    elif [[ -f $base.bz2 ]]; then bzip2 -dc "$base.bz2" > "$TMP/sa$1" && echo "$TMP/sa$1"
    fi
}

echo "Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused" > "$OUT"

for (( i = DAYS - 1; i >= 0; i-- )); do          # oldest day first
    day=$(date -d "$i days ago" +%Y-%m-%d)
    f=$(resolve_file "$(date -d "$i days ago" +%d)")
    [[ -n $f ]] || { echo "  skip $day: no data file" >&2; continue; }

    # Merge CPU + memory in one awk pass. Each section starts with a header
    # line whose second field is "CPU" (sar -u) or "kbmemfree" (sar -r).
    { sar -u -f "$f"; sar -r -f "$f"; } 2>/dev/null | awk -v want="$day" '
        NR == 1 || /^Linux/ {
            if (match($0, /\(([^)]+)\)/)) host = substr($0, RSTART + 1, RLENGTH - 2)
            for (k = 1; k <= NF; k++) if ($k ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) fdate = $k
            next
        }
        /^Average|^$|RESTART/ { next }
        $2 == "CPU" || $2 == "kbmemfree" {
            sect = ($2 == "CPU") ? "cpu" : "mem"
            delete col
            for (k = 2; k <= NF; k++) col[$k] = k
            next
        }
        $1 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ {
            if (fdate != "" && fdate != want) exit   # stale file from last month
            t = $1
            if (sect == "cpu" && $2 == "all") {
                cpu[t] = $col["%user"] "," $col["%system"] "," $col["%idle"] "," $col["%iowait"]
                order[++n] = t
            } else if (sect == "mem") {
                mem[t] = $col["kbmemfree"] "," $col["kbmemused"] "," $col["%memused"]
            }
        }
        END {
            for (j = 1; j <= n; j++)
                if (order[j] in mem)
                    print host "," want "," order[j] "," cpu[order[j]] "," mem[order[j]]
        }' >> "$OUT"
done

echo "Done: $OUT ($(( $(wc -l < "$OUT") - 1 )) data rows)"
