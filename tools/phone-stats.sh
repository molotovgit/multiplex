#!/bin/bash
# phone-stats.sh SECONDS LABEL: with the remote desktop open on the phone (debug
# build), collects its per-second stats from logcat and prints medians.
# Passive: nothing is sent to the computer.
A=~/Android/Sdk/platform-tools/adb; secs=${1:-60}; label=${2:-run}
$A logcat -c
sleep "$secs"
$A logcat -d -s flutter:I 2>/dev/null | grep -o "mpxstats .*" > /tmp/mpxstats-$label.txt
python3 - "$label" <<'PY'
import re,sys,statistics as st
label=sys.argv[1]; rows=[]
for l in open(f'/tmp/mpxstats-{label}.txt'):
    d=dict(re.findall(r'(\w+)=([-\d.]+)', l))
    try: rows.append({k: float(v) for k,v in d.items() if v not in ('-',)})
    except ValueError: pass
rows=[r for r in rows if r.get('fps',0)>0]
if not rows: print(label, 'no samples'); sys.exit()
def med(k):
    v=[r[k] for r in rows if k in r and r[k]>0]
    return (st.median(v), st.mean(v), len(v)) if v else (float('nan'),float('nan'),0)
over=[r['rtt']-r['net'] for r in rows if 'net' in r and r.get('rtt',0)>0]
print(f"{label}: {len(rows)} s | fps med {med('fps')[0]:.0f} | decode med {med('decode')[0]:.2f} mean {med('decode')[1]:.2f} ms | stream ping med {med('rtt')[0]:.1f} | net ping med {med('net')[0]:.1f} | ping above net: med {st.median(over) if over else float('nan'):.1f} mean {st.mean(over) if over else float('nan'):.1f} (n={len(over)}) | picture delay med {med('age')[0]:.1f} ms")
PY
