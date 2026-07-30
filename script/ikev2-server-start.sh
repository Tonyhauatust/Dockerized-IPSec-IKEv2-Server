#!/bin/bash

# IPSec-IKEv2-Server - A Dockerised IKEv2/IPSec VPN server with L2TP support.
# Copyright (C) 2026  Tony HAU
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

cp /run/secrets/ipsec-server-secrets /etc/ipsec.secrets
cp /run/secrets/ipsec-server-cert /etc/ipsec.d/certs/myvpnservercert.crt
cp /run/secrets/ipsec-server-private-key /etc/ipsec.d/private/myvpnprivatekey.pem

# ─── kernel network tuning ───────────────────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1

# net.core.rmem_max / wmem_max / netdev_max_backlog are host-level (non-namespaced)
# sysctls and cannot be set inside a container. Set them on the host via
# /etc/sysctl.d/99-vpn-performance.conf instead.

# ─── iptables ────────────────────────────────────────────────────────────────

# NAT: masquerade VPN client traffic so it leaves the container with the
# container's own IP (192.168.81.2). Docker then masquerades that further to
# the host's public IP. Without this, packets from 172.20.x.x / 172.22.x.x
# would have non-routable source addresses and 8.8.8.8 would never respond.
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# ── inter-subnet isolation ────────────────────────────────────────────────────
# Blocks cross-subnet traffic between the four VPN subnets.  Covers all 6
# bidirectional pairs (12 rules).  These fire in the FORWARD chain, which sees
# the decrypted inner packets after strongSwan's XFRM processing – so they
# correctly isolate clients even though the VPN itself is on a single server.
iptables -t filter -A FORWARD -s 172.20.1.0/24 -d 172.20.0.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.2.0/24 -d 172.20.0.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.22.0.0/24 -d 172.20.0.0/24 -j DROP

iptables -t filter -A FORWARD -s 172.20.0.0/24 -d 172.20.1.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.2.0/24 -d 172.20.1.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.22.0.0/24 -d 172.20.1.0/24 -j DROP

iptables -t filter -A FORWARD -s 172.20.1.0/24 -d 172.20.2.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.0.0/24 -d 172.20.2.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.22.0.0/24 -d 172.20.2.0/24 -j DROP

iptables -t filter -A FORWARD -s 172.20.0.0/24 -d 172.22.0.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.1.0/24 -d 172.22.0.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.2.0/24 -d 172.22.0.0/24 -j DROP

# ── VPC subnet protection ─────────────────────────────────────────────────────
# Prevents VPN clients from reaching the AWS VPC (10.0.0.0/16).
# These FORWARD rules fire *before* POSTROUTING MASQUERADE, so the source is
# still the VPN client's virtual IP (172.20.x.x / 172.22.x.x) when checked –
# they correctly block the traffic before it can be NATted and forwarded.
iptables -t filter -A FORWARD -s 172.20.0.0/24 -d 10.0.0.0/16 -j DROP
iptables -t filter -A FORWARD -s 172.20.1.0/24 -d 10.0.0.0/16 -j DROP
iptables -t filter -A FORWARD -s 172.20.2.0/24 -d 10.0.0.0/16 -j DROP
iptables -t filter -A FORWARD -s 172.22.0.0/24 -d 10.0.0.0/16 -j DROP

# ── server self-protection ────────────────────────────────────────────────────
# Drops any inner-tunnel packet addressed *to this container* from a VPN client.
# This prevents VPN clients from probing or connecting to services running
# inside the container.  It does NOT break the VPN: IKE/ESP keepalive packets
# use the client's *public* IP as the source, not the 172.x.x.x virtual IP,
# so they are never matched by these rules and continue to work normally.
iptables -t filter -A INPUT -s 172.20.0.0/24 -j DROP
iptables -t filter -A INPUT -s 172.20.1.0/24 -j DROP
iptables -t filter -A INPUT -s 172.20.2.0/24 -j DROP
iptables -t filter -A INPUT -s 172.22.0.0/24 -j DROP

# ── Docker bridge protection ──────────────────────────────────────────────────
# Stops VPN clients from reaching other containers on the ipsec-server-network
# bridge (192.168.81.0/24), e.g. the L2TP server or any future containers.
iptables -t filter -A FORWARD -s 172.20.0.0/24 -d 192.168.81.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.1.0/24 -d 192.168.81.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.20.2.0/24 -d 192.168.81.0/24 -j DROP
iptables -t filter -A FORWARD -s 172.22.0.0/24 -d 192.168.81.0/24 -j DROP

# Clamp TCP MSS to the path MTU on all forwarded connections.
# Without this, TCP segments larger than the tunnel MTU are fragmented,
# causing retransmissions that appear as poor throughput.
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN \
    -j TCPMSS --clamp-mss-to-pmtu

# ─── start strongSwan ────────────────────────────────────────────────────────
exec ipsec start --nofork
