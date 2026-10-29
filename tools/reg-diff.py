import re, collections

def parse(path, mainline=False):
    rails = {}
    for line in open(path, errors='replace'):
        line = line.rstrip('\n')
        if not line.strip() or 'use  open' in line or line.lstrip().startswith('-'):
            continue
        if line.startswith(' ' * 20) or line.startswith('\t'):
            continue  # consumer line
        parts = line.split()
        if len(parts) < 7:
            continue
        name = parts[0]
        if mainline:
            # name use open bypass opmode voltage current min max
            if len(parts) < 9 or parts[4] not in ('normal', 'fast', 'idle', 'unknown'):
                continue
            use = parts[1]
            volt = parts[5]
        else:
            # name use open bypass voltage current min max
            use = parts[1]
            volt = parts[4]
        if use == 'open':   # consumer-ish
            continue
        try:
            u = int(use)
        except ValueError:
            continue
        m = re.match(r'(\d+)mV', volt)
        if not m:
            continue
        rails[name] = (u, int(m.group(1)))
    return rails

r10 = parse('$PROJECT/reg-r10.txt')
ml  = parse('$PROJECT/reg-mainline2.txt', mainline=True)

print("r10 rails:", len(r10), " mainline rails:", len(ml))

ml_on = collections.Counter(v for (u, v) in ml.values() if u > 0)
ml_all = collections.Counter(v for (u, v) in ml.values())

print("\n=== enabled on r10 (use>0), 0mV skipped ===")
only_r10 = []
for name, (u, v) in sorted(r10.items()):
    if u > 0 and v > 0:
        here = ml_on.get(v, 0)
        flag = "  <-- NO ENABLED MATCH ON MAINLINE" if here == 0 else ""
        if here == 0:
            only_r10.append((name, u, v))
        print(f"  {name:<22} use={u}  {v}mV   mainline enabled@{v}mV: {here}{flag}")

print("\n=== candidate rails: on in r10, not enabled at that voltage on mainline ===")
for name, u, v in only_r10:
    present = ml_all.get(v, 0)
    print(f"  {name:<22} {v}mV  (mainline has {present} rail(s) at this voltage, none enabled)")

print("\n=== rails present in mainline but never enabled (any voltage) ===")
for name, (u, v) in sorted(ml.items()):
    if u == 0 and v > 0:
        inr10 = [n for n, (uu, vv) in r10.items() if vv == v and uu > 0]
        if inr10:
            print(f"  mainline {name:<8} {v}mV disabled  <- r10 has {', '.join(inr10)} enabled")
