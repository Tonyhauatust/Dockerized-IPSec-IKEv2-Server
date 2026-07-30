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

syt='/sbin/sysctl -e -q -w'
$syt kernel.msgmnb=65536 2>/dev/null
$syt kernel.msgmax=65536 2>/dev/null
$syt net.ipv4.conf.all.accept_redirects=0 2>/dev/null
$syt net.ipv4.conf.all.send_redirects=0 2>/dev/null
$syt net.ipv4.conf.all.rp_filter=0 2>/dev/null
$syt net.ipv4.conf.default.accept_redirects=0 2>/dev/null
$syt net.ipv4.conf.default.send_redirects=0 2>/dev/null
$syt net.ipv4.conf.default.rp_filter=0 2>/dev/null
$syt net.ipv4.tcp_rmem="4096 87380 16777216" 2>/dev/null
$syt net.ipv4.tcp_wmem="4096 87380 16777216" 2>/dev/null