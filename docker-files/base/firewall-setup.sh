#!/bin/bash

# Docker-compatible firewall with ipset for dynamic domain handling

set -e

ALLOWED_DOMAINS_FILE="/etc/firewall-config/allowed-domains.txt"
ALLOWED_IPS_SET="allowed_ips"
LOG_FILE="/var/log/firewall.log"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Management functions
add_domain() {
  local domain="$1"
  if [ -z "$domain" ]; then
    echo "Usage: $0 add <domain>"
    return 1
  fi

  # Create domains file if it doesn't exist
  mkdir -p /etc/firewall
  touch "$ALLOWED_DOMAINS_FILE"

  # Check if domain already exists
  if grep -Fxq "$domain" "$ALLOWED_DOMAINS_FILE" 2>/dev/null; then
    echo "Domain $domain already exists"
    return 0
  fi

  echo "$domain" >>"$ALLOWED_DOMAINS_FILE"
  log "Added domain: $domain"
  update_ipset
  echo "Domain $domain added successfully"
}

remove_domain() {
  local domain="$1"
  if [ -z "$domain" ]; then
    echo "Usage: $0 remove <domain>"
    return 1
  fi

  if [ ! -f "$ALLOWED_DOMAINS_FILE" ]; then
    echo "No allowed domains file found"
    return 1
  fi

  sed -i "/^${domain}$/d" "$ALLOWED_DOMAINS_FILE"
  log "Removed domain: $domain"
  update_ipset
  echo "Domain $domain removed successfully"
}

list_domains() {
  if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
    echo "Allowed domains:"
    cat "$ALLOWED_DOMAINS_FILE"
  else
    echo "No allowed domains configured"
  fi

  echo
  echo "Current IPs in allowed set:"
  ipset list "$ALLOWED_IPS_SET" 2>/dev/null | grep -E '^[0-9]+\.' || echo "No IPs in set"
}

# Update ipset with current domain IPs
update_ipset() {
  if [ ! -f "$ALLOWED_DOMAINS_FILE" ]; then
    log "No domains file found, skipping ipset update"
    return 0
  fi

  # Create ipset if it doesn't exist
  if ! ipset list "$ALLOWED_IPS_SET" >/dev/null 2>&1; then
    ipset create "$ALLOWED_IPS_SET" hash:ip timeout 3600
    log "Created ipset: $ALLOWED_IPS_SET"
  fi

  # Clear existing entries (they'll be re-added with fresh timeout)
  ipset flush "$ALLOWED_IPS_SET" 2>/dev/null || true

  log "Updating IP set from domains..."
  while IFS= read -r domain; do
    # Skip empty lines and comments
    if [ -n "$domain" ] && [[ ! "$domain" =~ ^[[:space:]]*# ]]; then
      # Remove inline comments
      domain=$(echo "$domain" | sed 's/#.*$//' | xargs)
      if [ -n "$domain" ]; then
        log "Resolving domain: $domain"
        # Get all IPs for the domain
        local ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        if [ -n "$ips" ]; then
          while IFS= read -r ip; do
            if [ -n "$ip" ]; then
              ipset add "$ALLOWED_IPS_SET" "$ip" timeout 3600 2>/dev/null || true
              log "Added IP $ip for domain $domain"
            fi
          done <<<"$ips"
        else
          log "Warning: Could not resolve $domain"
        fi
      fi
    fi
  done <"$ALLOWED_DOMAINS_FILE"
}

test_domain() {
  local domain="${1:-github.com}"
  echo "Testing connection to: $domain"

  # Test DNS resolution
  local ips=$(dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
  if [ -z "$ips" ]; then
    echo "FAILED: Could not resolve $domain to valid IP(s)"
    echo "DNS resolution output:"
    dig "$domain" 2>&1
    return 1
  fi

  echo "Resolved $domain to:"
  echo "$ips"

  # Check if any of the IPs are in our allowed set
  local found_in_set=false
  while IFS= read -r ip; do
    if ipset test "$ALLOWED_IPS_SET" "$ip" 2>/dev/null; then
      echo "✓ IP $ip is in allowed set"
      found_in_set=true
    else
      echo "✗ IP $ip is NOT in allowed set"
    fi
  done <<<"$ips"

  if [ "$found_in_set" = false ]; then
    echo "WARNING: None of the IPs for $domain are in the allowed set"
    echo "You may need to add the domain first: $0 add $domain"
  fi

  # Test actual connection
  echo "Testing HTTPS connection..."
  if timeout 10 curl -s --connect-timeout 5 "https://$domain" >/dev/null 2>&1; then
    echo "✓ HTTPS connection successful"
  else
    echo "✗ HTTPS connection failed"
    echo "This could be due to firewall rules or network issues"
  fi
}

disable_firewall() {
  log "Disabling firewall..."

  # Remove our custom chains first
  iptables -D OUTPUT -j FIREWALL_OUT 2>/dev/null || true
  iptables -D INPUT -j FIREWALL_IN 2>/dev/null || true

  # Flush and delete our custom chains
  iptables -F FIREWALL_OUT 2>/dev/null || true
  iptables -F FIREWALL_IN 2>/dev/null || true
  iptables -X FIREWALL_OUT 2>/dev/null || true
  iptables -X FIREWALL_IN 2>/dev/null || true

  # Destroy ipset
  ipset destroy "$ALLOWED_IPS_SET" 2>/dev/null || true

  log "Firewall disabled - using default Docker networking"
  echo "Firewall disabled successfully"
}

# Setup firewall - Docker-friendly approach
setup_firewall() {
  log "Setting up Docker-compatible firewall with ipset..."

  # Ensure ipset is available
  if ! command -v ipset >/dev/null 2>&1; then
    echo "Error: ipset is not installed. Install it with:"
    echo "  apt-get update && apt-get install -y ipset"
    return 1
  fi

  # Clean up any existing setup
  disable_firewall

  # Create ipset for allowed IPs
  ipset create "$ALLOWED_IPS_SET" hash:ip timeout 3600 2>/dev/null || {
    ipset flush "$ALLOWED_IPS_SET" 2>/dev/null || true
  }

  # Create custom chains instead of modifying default policies
  iptables -N FIREWALL_OUT 2>/dev/null || true
  iptables -N FIREWALL_IN 2>/dev/null || true

  # Clear our custom chains
  iptables -F FIREWALL_OUT
  iptables -F FIREWALL_IN

  # Rules for outbound traffic
  iptables -A FIREWALL_OUT -o lo -j ACCEPT
  iptables -A FIREWALL_OUT -m state --state ESTABLISHED,RELATED -j ACCEPT

  # Allow DNS (essential for Docker)
  iptables -A FIREWALL_OUT -p udp --dport 53 -j ACCEPT
  iptables -A FIREWALL_OUT -p tcp --dport 53 -j ACCEPT

  # Allow connections to IPs in our allowed set
  iptables -A FIREWALL_OUT -m set --match-set "$ALLOWED_IPS_SET" dst -p tcp --dport 80 -j ACCEPT
  iptables -A FIREWALL_OUT -m set --match-set "$ALLOWED_IPS_SET" dst -p tcp --dport 443 -j ACCEPT
  iptables -A FIREWALL_OUT -m set --match-set "$ALLOWED_IPS_SET" dst -p tcp --dport 22 -j ACCEPT

  # Allow local Docker network communication (adjust subnet as needed)
  iptables -A FIREWALL_OUT -d 172.16.0.0/12 -j ACCEPT
  iptables -A FIREWALL_OUT -d 10.0.0.0/8 -j ACCEPT
  iptables -A FIREWALL_OUT -d 192.168.0.0/16 -j ACCEPT

  # Drop everything else
  iptables -A FIREWALL_OUT -j LOG --log-prefix "FIREWALL_DROP_OUT: " --log-level 4
  iptables -A FIREWALL_OUT -j DROP

  # Rules for inbound traffic (more permissive for Docker)
  iptables -A FIREWALL_IN -i lo -j ACCEPT
  iptables -A FIREWALL_IN -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A FIREWALL_IN -m set --match-set "$ALLOWED_IPS_SET" src -j ACCEPT

  # Allow local networks
  iptables -A FIREWALL_IN -s 172.16.0.0/12 -j ACCEPT
  iptables -A FIREWALL_IN -s 10.0.0.0/8 -j ACCEPT
  iptables -A FIREWALL_IN -s 192.168.0.0/16 -j ACCEPT

  # Insert our chains into the main chains (without changing default policies)
  iptables -I OUTPUT 1 -j FIREWALL_OUT
  iptables -I INPUT 1 -j FIREWALL_IN

  # Update ipset with current domains
  update_ipset

  log "Firewall setup complete with ipset integration"
  echo "Firewall is now active with allowed domains"
}

# Refresh ipset (useful for cron jobs)
refresh_ips() {
  log "Refreshing IP set from domains..."
  update_ipset
  echo "IP set refreshed successfully"
}

# Show firewall status
status() {
  echo "=== Firewall Status ==="
  echo

  if iptables -L FIREWALL_OUT >/dev/null 2>&1; then
    echo "✓ Firewall is ACTIVE"
  else
    echo "✗ Firewall is INACTIVE"
    return 0
  fi

  echo
  echo "Allowed domains:"
  if [ -f "$ALLOWED_DOMAINS_FILE" ]; then
    cat "$ALLOWED_DOMAINS_FILE"
  else
    echo "None configured"
  fi

  echo
  echo "Current allowed IPs:"
  if ipset list "$ALLOWED_IPS_SET" >/dev/null 2>&1; then
    ipset list "$ALLOWED_IPS_SET" | grep -E '^[0-9]+\.' | wc -l | xargs echo "Total IPs:"
    ipset list "$ALLOWED_IPS_SET" | grep -E '^[0-9]+\.' | head -10
    local total=$(ipset list "$ALLOWED_IPS_SET" | grep -E '^[0-9]+\.' | wc -l)
    if [ "$total" -gt 10 ]; then
      echo "... and $((total - 10)) more"
    fi
  else
    echo "No IP set found"
  fi

  echo
  echo "Recent log entries:"
  if [ -f "$LOG_FILE" ]; then
    tail -5 "$LOG_FILE"
  else
    echo "No log file found"
  fi
}

# Command line interface
case "$1" in
"add") add_domain "$2" ;;
"remove") remove_domain "$2" ;;
"list") list_domains ;;
"test") test_domain "$2" ;;
"disable") disable_firewall ;;
"refresh") refresh_ips ;;
"status") status ;;
"setup" | "") setup_firewall ;;
*)
  echo "Usage: $0 {add|remove|list|test|disable|refresh|status|setup}"
  echo
  echo "Commands:"
  echo "  add <domain>    - Add domain to allowed list"
  echo "  remove <domain> - Remove domain from allowed list"
  echo "  list           - Show allowed domains and current IPs"
  echo "  test <domain>  - Test domain connectivity"
  echo "  disable        - Disable firewall"
  echo "  refresh        - Refresh IP set from domains"
  echo "  status         - Show firewall status"
  echo "  setup          - Setup/restart firewall (default)"
  exit 1
  ;;
esac
