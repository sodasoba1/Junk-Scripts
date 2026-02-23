#!/bin/bash

# Store the result of the netstat command in a variable
result=$(netstat -tulnp)

# Use awk to extract the relevant information from the result
echo "$result" | awk '
/^tcp/ {
  printf "Protocol: TCP\n"
  printf "Local Address: %s\n",$4
  printf "Foreign Address: %s\n",$5
  printf "State: %s\n",$6
  printf "PID/Program name: %s\n\n",$7
}
/^udp/ {
  printf "Protocol: UDP\n"
  printf "Local Address: %s\n",$4
  printf "Foreign Address: %s\n",$5
  printf "State: %s\n",$6
  printf "PID/Program name: %s\n\n",$7
}'
