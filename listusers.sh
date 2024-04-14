#!/bin/bash

echo "Current users and their privileges:"

for user in $(who | awk '{print $1}'); do
  if [ "$user" == "root" ]; then
    echo "$user (root)"
  else
    if sudo -l -U "$user" | grep -q "ALL"; then
      echo "$user (sudo)"
    else
      echo "$user"
    fi
  fi
done
