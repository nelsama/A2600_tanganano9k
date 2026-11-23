"""run_all.py dir frames [buttons@a-b ...]: every ROM of dir in the simulator;
results in build/sim/all (txt and png)."""
import os, subprocess, sys, glob
from concurrent.futures import ThreadPoolExecutor
here = os.path.dirname(os.path.abspath(__file__)); S = os.path.join(here, '..', '..', 'build', 'sim')
O = os.path.join(S, 'all'); os.makedirs(O, exist_ok=True)
d, frames = sys.argv[1:3]
os.environ['PATH'] = r'C:\msys64\ucrt64\bin;' + os.environ['PATH']
def one(p):
    n = os.path.splitext(os.path.basename(p))[0]
    m = subprocess.check_output([os.path.join(S, 'detect.exe'), p], text=True).split()
    if m[0] == 'err': return n, 'unsupported'
    o = os.path.join(O, n + '.ppm')
    try: r = subprocess.check_output([os.path.join(S, 'sim.exe'), 'game', p, m[0], m[1], frames, o] + sys.argv[3:], text=True, timeout=1500).strip()
    except Exception as e: r = 'FAIL ' + str(e)
    subprocess.call(['ffmpeg', '-v', 'error', '-y', '-i', o, o[:-4] + '.png']); os.remove(o)
    return n, 'map %s ' % m[0] + r
L = sorted(glob.glob(os.path.join(d, '*.a26')))
with ThreadPoolExecutor(14) as ex, open(os.path.join(O, 'result.txt'), 'w') as f:
    for n, r in ex.map(one, L): f.write('%-50s %s\n' % (n, r)); f.flush()
