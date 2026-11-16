#!/bin/bash
# Latency lab: gliff-server and the probe (rust/tests/gliff_direct.rs) in a
# private network namespace whose loopback emulates a mobile link. No root
# needed (unshare -rn); runs inside a Hyprland session.
#
#   tools/latency-lab.sh "<label>" "<netem args>" "<sysctl k=v ...>" [server] [server args]
#   tools/latency-lab.sh lte "delay 10ms 3ms distribution normal rate 30mbit" ""
#
# Prints: ping, causal move->frame (one pointer move on a still screen until
# the frame it caused has arrived), small-frame age and keyframe-after-idle
# times. Client and server share one clock, so the ages are exact.
set -euo pipefail
LABEL=$1; NETEM=$2; SYSCTLS=${3:-}; SERVER=${4:-gliff-server}; EXTRA=${5:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
(cd "$ROOT/rust" && cargo test --test gliff_direct --no-run -q 2>/dev/null)
PROBE=$(ls -t "$ROOT"/rust/target/debug/build/multiplex_core/*/out/gliff_direct-* 2>/dev/null | grep -v '\.d$' | head -1)
unshare -rn bash -s <<IN
ip link set lo up
tc qdisc add dev lo root netem $NETEM
for kv in $SYSCTLS; do sysctl -qw "\$kv"; done
$SERVER --listen 127.0.0.1:47001 --output auto $EXTRA 2>/dev/null &
SP=\$!
sleep 1.2
out=\$(MPX_GLIFF_DIRECT=127.0.0.1:47001 $PROBE --nocapture 2>&1 | grep '^LAB' || true)
kill \$SP 2>/dev/null; wait \$SP 2>/dev/null || true
printf '%-30s %s\n' "$LABEL" "\${out#LAB }"
IN
