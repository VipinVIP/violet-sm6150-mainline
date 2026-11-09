#!/bin/sh
# usage: cpustress.sh <little_max_khz> <big_max_khz> <secs>   (run as root on the phone)
# caps both clusters, then 8 busy loops, printing cur freqs + hottest thermal zone every 5 s
echo $1 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
echo $2 > /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
for i in 1 2 3 4 5 6 7 8; do (timeout $3 sh -c "while :; do :; done" &) ; done
n=$(( $3 / 5 ))
for i in $(seq 1 $n); do sleep 5; echo "$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq) $(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq) $(cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -1)"; done
echo SURVIVED
