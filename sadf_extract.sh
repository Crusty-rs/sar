#!/bin/bash

# Extract sar data using sadf - handles all formats

out="metrics_$(date +%Y%m%d).csv"

# Extract and format
sadf -s $(date -d "13 days ago" +%Y-%m-%d) -e $(date +%Y-%m-%d) -dU /var/log/sa/sa* -- -u -r 2>/dev/null | \
awk -F';' '
    BEGIN {
        print "Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused"
    }
    NR > 1 {
        if ($5 == "CPU" && $4 == "-1") {
            split($3, dt, " ")
            key = $1 "," dt[1] "," dt[2]
            cpu[key] = $7 "," $9 "," $12 "," $10
        }
        if ($4 == "MEM") {
            split($3, dt, " ")
            key = $1 "," dt[1] "," dt[2]
            mem[key] = $6 "," $7 "," $8
        }
    }
    END {
        for (k in cpu) if (k in mem) print k "," cpu[k] "," mem[k]
    }
' | sort -t, -k2,2 -k3,3 > $out

echo "Done: $out ($(wc -l < $out) lines)"
