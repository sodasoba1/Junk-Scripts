#!/bin/bash

echo "Checking logs for unauthorized access..."

AUTH_LOGS="/var/log/auth.log*"
SECURE_LOGS="/var/log/secure*"

# Check auth logs for failed login attempts
echo "Failed login attempts:"
grep "authentication failure" $AUTH_LOGS

# Check secure logs for failed login attempts
echo "Failed login attempts (secure logs):"
grep "Failed password" $SECURE_LOGS

# Check secure logs for any authentication failures
echo "Authentication failures (secure logs):"
grep "authentication failure" $SECURE_LOGS

# Check secure logs for any su attempts
echo "su attempts:"
grep "su: " $SECURE_LOGS

# Check secure logs for any sudo attempts
echo "sudo attempts:"
grep "sudo: " $SECURE_LOGS
