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
    curl -s --connect-timeout 5 "https://${1:-github.com}" >/dev/null && echo "OK" || echo "FAILED"
}

disable_firewall() {
    iptables -F
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
}

# Setup firewall
setup_firewall() {
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

    # Allow DNS
    iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -j ACCEPT

    # Allow HTTP/HTTPS to allowed domains
    if [ -f "/etc/firewall/allowed-domains.txt" ]; then
        while read -r domain; do
            if [ -n "$domain" ] && [[ ! "$domain" =~ ^[[:space:]]*# ]]; then
                for ip in $(dig +short $domain 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'); do
                    iptables -A OUTPUT -p tcp -d "$ip" --dport 80 -j ACCEPT
                    iptables -A INPUT -p tcp -s "$ip" --sport 80 -j ACCEPT
                    iptables -A OUTPUT -p tcp -d "$ip" --dport 443 -j ACCEPT
                    iptables -A INPUT -p tcp -s "$ip" --sport 443 -j ACCEPT
                    iptables -A OUTPUT -p tcp -d "$ip" --dport 22 -j ACCEPT
                    iptables -A INPUT -p tcp -s "$ip" --sport 22 -j ACCEPT
                done
            fi
        done < "/etc/firewall/allowed-domains.txt"
    fi
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
