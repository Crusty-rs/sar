#!/bin/bash
#Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused
#         └─────┘    └───────── CPU ─────────┘ └────────── MEMORY ──────────┘
# One-liner: Copy and paste this entire command
sadf -s $(date -d "13 days ago" +%Y-%m-%d) -e $(date +%Y-%m-%d) -dU /var/log/sa/sa* -- -u -r 2>/dev/null | awk -F';' 'BEGIN{print "Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused"} NR>1{if($5=="CPU" && $4=="-1"){split($3,dt," "); cpu[$1","dt[1]","dt[2]]=$7","$9","$12","$10} if($4=="MEM"){split($3,dt," "); key=$1","dt[1]","dt[2]; if(key in cpu) print key","cpu[key]","$6","$7","$8}}' | sort -t, -k2,2 -k3,3 > metrics.csv && echo "Done: metrics.csv ($(wc -l < metrics.csv) lines)"
