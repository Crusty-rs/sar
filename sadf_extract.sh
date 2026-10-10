#!/usr/bin/env bash
#
# sadf_metrics.sh — Export N days of CPU + memory metrics via sadf into CSV.
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
        h) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Usage: $0 [-d DAYS] [-o OUTPUT.csv] [-s SA_DIR]" >&2; exit 1 ;;
    esac
done

command -v sadf >/dev/null || { echo "Error: sadf not found (install sysstat)" >&2; exit 1; }

if [[ -z $SA_DIR ]]; then
    for dir in /var/log/sa /var/log/sysstat; do
        [[ -d $dir ]] && { SA_DIR=$dir; break; }
    done
fi
[[ -d ${SA_DIR:-} ]] || { echo "Error: sa directory not found (use -s)" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export LC_ALL=C

echo "Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused" > "$OUT"

for (( i = DAYS - 1; i >= 0; i-- )); do
    day=$(date -d "$i days ago" +%Y-%m-%d)
    dd=$(date -d "$i days ago" +%d)
    f="$SA_DIR/sa$dd"

    if   [[ -f $f     ]]; then :
    elif [[ -f $f.xz  ]]; then xz    -dc "$f.xz"  > "$TMP/sa$dd"; f="$TMP/sa$dd"
    elif [[ -f $f.gz  ]]; then gzip  -dc "$f.gz"  > "$TMP/sa$dd"; f="$TMP/sa$dd"
    elif [[ -f $f.bz2 ]]; then bzip2 -dc "$f.bz2" > "$TMP/sa$dd"; f="$TMP/sa$dd"
    else echo "  skip $day: no data file" >&2; continue
    fi

    sadf -dt "$f" -- -u -r 2>/dev/null | awk -F';' -v want="$day" '
        /^# hostname/ {                       # section header -> column map
            delete col
            for (k = 1; k <= NF; k++) col[$k] = k
            sect = ("CPU" in col) ? "cpu" : (("kbmemfree" in col) ? "mem" : "")
            next
        }
        /^#/ || NF < 4 { next }
        {
            split($col["timestamp"], dt, " ")
            if (dt[1] != want) next           # stale file / other day
            key = $col["# hostname"] "," dt[1] "," dt[2]
            if (sect == "cpu" && $col["CPU"] == "-1") {
                cpu[key] = $col["%user"] "," $col["%system"] "," $col["%idle"] "," $col["%iowait"]
                order[++n] = key
            } else if (sect == "mem") {
                mem[key] = $col["kbmemfree"] "," $col["kbmemused"] "," $col["%memused"]
            }
        }
        END { for (j = 1; j <= n; j++) if (order[j] in mem) print order[j] "," cpu[order[j]] "," mem[order[j]] }
    ' >> "$OUT"
done

echo "Done: $OUT ($(( $(wc -l < "$OUT") - 1 )) data rows)"
