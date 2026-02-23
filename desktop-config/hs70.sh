#!/bin/sh
#
# hs70 status for py3status
# requires headsetcontrol https://github.com/Sapd/HeadsetControl
#

HS=$(headsetcontrol -b | grep Battery | tr -d ' ' | cut -d ':' -f1)

if [ "$HS" = "Battery" ]; then
  headsetcontrol -b | grep % | tr -d ' ' | cut -d ':' -f2
else
   printf ""
fi



#HS=$(headsetcontrol -b | grep Battery | tr -d ' ' | cut -d ':' -f1)

#if [ "$HS" = "Unavailable" ]; then
#  headsetcontrol -b | grep Unavailable | tr -d ' ' | cut -d ':' -f2
#else #[ "$HS" = "Battery" ];
#  headsetcontrol -b | grep Battery | tr -d ' ' | cut -d ':' -f2
#else
#   printf ""
#fi
