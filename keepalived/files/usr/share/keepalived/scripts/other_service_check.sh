#!/bin/sh
# other_service_check.sh

echo "Running other_service_check.sh at $(date)"
logger "Running other_service_check.sh at $(date)"

# Check if natmap is installed
check_natmap_installed() {
    if ! [ -x "/etc/init.d/natmap" ]; then
        echo "natmap service is not installed, skipping natmap control"
        logger "natmap service is not installed, skipping natmap control"
        return 1
    fi
    return 0
}

# Reload odhcpd if necessary
reload_odhcpd_if_needed() {
    if [ "$1" = true ]; then
        echo "Reloading odhcpd service"
        logger "Reloading odhcpd service"
        /etc/init.d/odhcpd reload
    fi
}

# Reload natmap if necessary
reload_natmap_if_needed() {
    if [ "$1" = true ]; then
        if check_natmap_installed; then
            echo "Reloading natmap service"
            logger "Reloading natmap service"
            /etc/init.d/natmap reload
        else
            echo "Cannot reload natmap: service not installed"
            logger "Cannot reload natmap: service not installed"
        fi
    fi
}

# Check and update UCI settings
check_and_update() {
    local config_key=$1
    local target_value=$2
    local current_value
    current_value=$(uci get "$config_key" 2>/dev/null)

    if [ "$current_value" = "$target_value" ]; then
        echo "$config_key is already set to $target_value, skipping"
        logger "$config_key is already set to $target_value, skipping"
        return 1
    else
        echo "Updating $config_key from $current_value to $target_value"
        logger "Updating $config_key from $current_value to $target_value"
        uci set "$config_key=$target_value"
        uci commit "${config_key%%.*}"
        return 0
    fi
}

# Update services based on Keepalived state
update_services() {
    local state="$1"
    echo "Detected Keepalived state: $state"
    logger "Detected Keepalived state: $state"

    reload_odhcpd=false
    reload_natmap=false

    if [ "$state" = "MASTER" ]; then
        echo "Keepalived state is MASTER, enabling services"
        logger "Keepalived state is MASTER, enabling services"

        # Enable natmap if not already enabled
        check_and_update "natmap.@global[0].enable" "1" && reload_natmap=true

        # Enable DHCPv6 settings
        check_and_update "dhcp.lan.dhcpv6" "server" && reload_odhcpd=true
        check_and_update "dhcp.lan.ra" "server" && reload_odhcpd=true
        check_and_update "dhcp.lan.ndp" "relay" && reload_odhcpd=true

    elif [ "$state" = "BACKUP" ]; then
        echo "Keepalived state is BACKUP, disabling services"
        logger "Keepalived state is BACKUP, disabling services"

        # Disable natmap if not already disabled
        check_and_update "natmap.@global[0].enable" "0" && reload_natmap=true

        # Disable DHCPv6 settings
        check_and_update "dhcp.lan.dhcpv6" "disabled" && reload_odhcpd=true
        check_and_update "dhcp.lan.ra" "disabled" && reload_odhcpd=true
        check_and_update "dhcp.lan.ndp" "disabled" && reload_odhcpd=true
    else
        echo "Unknown Keepalived state: $state, skipping service adjustments"
        logger "Unknown Keepalived state: $state, skipping service adjustments"
    fi

    # Apply necessary actions
    reload_odhcpd_if_needed "$reload_odhcpd"
    reload_natmap_if_needed "$reload_natmap"
}

# Main script execution
update_services "$1"
