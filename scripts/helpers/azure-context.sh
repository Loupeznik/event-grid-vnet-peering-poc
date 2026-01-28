#!/bin/bash

ORIGINAL_SUBSCRIPTION=""
SUBSCRIPTION_STACK=()

init_context() {
    ORIGINAL_SUBSCRIPTION=$(az account show --query id -o tsv 2>/dev/null)
    if [ -z "$ORIGINAL_SUBSCRIPTION" ]; then
        echo "Error: Not logged into Azure. Please run 'az login' first."
        exit 1
    fi

    trap restore_original EXIT
}

push_subscription() {
    local sub_id="$1"
    local current_sub=$(az account show --query id -o tsv 2>/dev/null)
    SUBSCRIPTION_STACK+=("$current_sub")

    if [ "$current_sub" != "$sub_id" ]; then
        az account set --subscription "$sub_id" >/dev/null
    fi
}

pop_subscription() {
    if [ ${#SUBSCRIPTION_STACK[@]} -gt 0 ]; then
        local last_idx=$((${#SUBSCRIPTION_STACK[@]} - 1))
        local prev_sub="${SUBSCRIPTION_STACK[$last_idx]}"
        unset "SUBSCRIPTION_STACK[$last_idx]"
        az account set --subscription "$prev_sub" >/dev/null
    fi
}

restore_original() {
    if [ -n "$ORIGINAL_SUBSCRIPTION" ]; then
        az account set --subscription "$ORIGINAL_SUBSCRIPTION" >/dev/null 2>&1
    fi
}

verify_subscription_access() {
    local sub_id="$1"

    if ! az account show --subscription "$sub_id" >/dev/null 2>&1; then
        echo "Error: Cannot access subscription $sub_id"
        echo "Please ensure you have access and are logged in with 'az login'"
        return 1
    fi
    return 0
}
