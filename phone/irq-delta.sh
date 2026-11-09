#!/bin/sh
# top interrupt movers every ~0.5 s: "HH:MM:SS  count  irq-name"
snap() { awk 'NR>1{s=0; for(i=2;i<=9;i++) if($i ~ /^[0-9]+$/) s+=$i; n=$1; sub(":","",n); name=$NF; print n, s, name}' /proc/interrupts; }
snap > /tmp/irq.a
while :; do
  sleep 0.5; snap > /tmp/irq.b
  echo "$(date +%T) $(awk 'NR==FNR{a[$1]=$2; next} {d=$2-a[$1]; if(d>200) printf "%s:%d:%s ", $1,d,$3}' /tmp/irq.a /tmp/irq.b)"
  mv /tmp/irq.b /tmp/irq.a
done
