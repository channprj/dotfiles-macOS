#!/bin/sh
set -eu
/sbin/pfctl -E >/dev/null 2>&1 || true
/sbin/pfctl -nf /etc/pf.conf
/sbin/pfctl -f /etc/pf.conf
