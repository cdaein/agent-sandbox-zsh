#!/bin/bash

# Simple firewall - blocks all traffic except allowed domains

set -e

# Management functions
add_domain() {
    echo "$1" >> /etc/firewall/allowed-domains.txt
    setup_firewall
}

remove_domain() {
    sed -i "/^${1}$/d" /etc/firewall/allowed-domains.txt
    setup_firewall
}

list_domains() {
    cat /etc/firewall/allowed-domains.txt
}

test_domain() {
    local domain="${1:-github.com}"
    echo "Testing connection to: $domain"
    # First test DNS resolution
    local ip=$(dig +short $domain 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    if [ -z "$ip" ]; then
        echo "FAILED: Could not resolve $domain to a valid IP"
        echo "DNS resolution output:"
        dig +short $domain 2>&1
        return 1
    fi
    echo "Resolved $domain to $ip"
    # Test HTTP connection
    curl -s --connect-timeout 5 "https://$domain" >/dev/null && echo "OK" || echo "FAILED"
}

disable_firewall() {
    echo "Disabling firewall..."
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "Firewall disabled - all traffic allowed"
}

# Setup firewall
setup_firewall() {
    echo "Setting up firewall..."
    
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Set default policies to DROP
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # Allow loopback and established connections
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow localhost/127.0.0.1 access
    iptables -A INPUT -s 127.0.0.1 -j ACCEPT
    iptables -A OUTPUT -d 127.0.0.1 -j ACCEPT

    # Allow DNS - use a more permissive approach for Docker
    # Allow all DNS traffic on port 53 (Docker needs this)
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --sport 53 -j ACCEPT

    # Allow HTTP/HTTPS to allowed domains
    if [ -f "/etc/firewall/allowed-domains.txt" ]; then
        echo "Processing allowed domains..."
        while read -r domain; do
            if [ -n "$domain" ] && [[ ! "$domain" =~ ^[[:space:]]*# ]]; then
                # Remove inline comments
                domain=$(echo "$domain" | sed 's/#.*$//' | xargs)
                if [ -n "$domain" ]; then
                    echo "Adding rules for domain: $domain"
                    for ip in $(dig +short $domain 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'); do
                        echo "  - Adding rules for IP: $ip"
                        iptables -A OUTPUT -p tcp -d "$ip" --dport 80 -j ACCEPT
                        iptables -A INPUT -p tcp -s "$ip" --sport 80 -j ACCEPT
                        iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
                        iptables -A INPUT -p tcp -s "$ip" --sport 443 -j ACCEPT
                        iptables -A OUTPUT -p tcp -d "$ip" --dport 22 -j ACCEPT
                        iptables -A INPUT -p tcp -s "$ip" --sport 22 -j ACCEPT
                    done
                fi
            fi
        done < "/etc/firewall/allowed-domains.txt"
    else
        echo "Warning: /etc/firewall/allowed-domains.txt not found"
    fi
    
    echo "Firewall setup complete"
}

# Command line interface
case "$1" in
    "add") add_domain "$2" ;;
    "remove") remove_domain "$2" ;;
    "list") list_domains ;;
    "test") test_domain "$2" ;;
    "disable") disable_firewall ;;
    *) setup_firewall ;;
esac
