#!/bin/bash
# get load averages
IFS=" " read LOAD1 LOAD5 LOAD15 <<<$(cat /proc/loadavg | awk '{ print $1,$2,$3 }')
# get free memory
IFS=" " read USED FREE TOTAL <<<$(free -htm | grep "Mem" | awk {'print $3,$4,$2'})
# get processes
PROCESS=`ps -eo user=|sort|uniq -c | awk '{ print $2 " " $1 }'`
PROCESS_ALL=`echo "$PROCESS"| awk {'print $2'} | awk '{ SUM += $1} END { print SUM }'`
PROCESS_ROOT=`echo "$PROCESS"| grep root | awk {'print $2'}`
PROCESS_USER=`echo "$PROCESS"| grep -v root | awk {'print $2'} | awk '{ SUM += $1} END { print SUM }'`
# get processors
PROCESSOR_NAME=`grep "model name" /proc/cpuinfo | cut -d ' ' -f3- | awk {'print $0'} | head -1`
PROCESSOR_COUNT=`grep -ioP 'processor\t:' /proc/cpuinfo | wc -l`

DISTRIBUTION_NAME=$(lsb_release -i)
DISTRIBUTION_VERSION=$(lsb_release -r)
DISTRIBUTION_CODENAME=$(lsb_release -sc)

W="\e[0;39m"
G="\e[1;92m"
H="\e[38;5;141;48;5;233m"
B="\e[1;96m"
M="\x1B[35m"
P="\e[38;5;93;48;5;233m"
Y="\e[38;5;196;48;5;233m"

echo -e "
$W  Distro....:\t $W`cat /etc/*release | grep "PRETTY_NAME" | cut -d "=" -f 2- | sed 's/"//g'` (${DISTRIBUTION_CODENAME})
$W 󰻠 Kernel....:\t $W`uname -nrmo`
$W 󱘖 Pre login.:\t $Y $(last | head -1 | cut -c 1-9 | xargs) $W at $H $(last | head -1 | cut -c 40-55 | xargs) $W from $G $(last | head -1 | cut -c 23-39 | xargs) $W
$W 󰃰 Uptime....:\t $W`uptime -p`
$W  Load......:\t $G$LOAD1$W ⸨1m⸩, $G$LOAD5$W ⸨5m⸩, $G$LOAD15$W ⸨15m⸩
$W  Processes.:\t $W$G$PROCESS_ROOT$W ⸨root⸩, $G$PROCESS_USER$W ⸨user⸩, $G$PROCESS_ALL$W ⸨total⸩
$W  CPU.......:\t $W$PROCESSOR_NAME ⸨$G$PROCESSOR_COUNT$W vCPU⸩
$W  Memory....:\t $H $USED $W used, $H $FREE $W free, $H $TOTAL $W total$W"
