#!/bin/bash

# Extract two weeks CPU/Memory metrics from sar

out="metrics_$(date +%Y%m%d).csv"
echo "Hostname,Date,Time,%usr,%sys,%idle,%iowait,kbmemfree,kbmemused,%memused" > $out

# Process each day
for i in {0..13}; do
    d=$(date -d "$i days ago" +%Y-%m-%d)
    f="/var/log/sa/sa$(date -d "$i days ago" +%d)"
    
    # Check compressed
    [[ -f "$f.xz" ]] && f="$f.xz"
    [[ ! -f "$f" ]] && continue
    
    # Extract CPU (columns: time AM/PM cpu %usr %nice %sys %iowait %steal %idle)
    sar -u -f "$f" 2>/dev/null | grep '^[0-9][0-9]:' | grep -v Average | \
    while read line; do
        # Handle 12h/24h format
        cols=($line)
        if [[ ${cols[1]} =~ ^(AM|PM)$ ]]; then
            # 12-hour: 00:00:00 AM 0.00 0.50 0.75 1.00 0.00 97.75
            time=${cols[0]}
            usr=${cols[3]}
            sys=${cols[5]}
            iowait=${cols[6]}
            idle=${cols[8]}
        else
            # 24-hour: 00:00:00 0.00 0.50 0.75 1.00 0.00 97.75
            time=${cols[0]}
            usr=${cols[2]}
            sys=${cols[4]}
            iowait=${cols[5]}
            idle=${cols[7]}
        fi
        
        # Get memory for same timestamp
        mem=$(sar -r -f "$f" 2>/dev/null | grep "^$time" | grep -v Average | head -1)
        if [[ -n "$mem" ]]; then
            memfree=$(echo "$mem" | awk '{print $2}')
            memused=$(echo "$mem" | awk '{print $3}')
            mempct=$(echo "$mem" | awk '{print $4}')
            
            echo "$(hostname),$d,$time,$usr,$sys,$idle,$iowait,$memfree,$memused,$mempct" >> $out
        fi
    done
done

echo "Done: $out ($(wc -l < $out) lines)"
