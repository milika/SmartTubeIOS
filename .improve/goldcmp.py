import sys, os, numpy as np
from PIL import Image
a, b = sys.argv[1], sys.argv[2]; tol = int(sys.argv[3]) if len(sys.argv) > 3 else 0
fa, fb = sorted(os.listdir(a)), sorted(os.listdir(b))
bad = 0
if fa != fb: print("FILE SETS DIFFER", set(fa) ^ set(fb)); bad += 1
worst = 0
for f in sorted(set(fa) & set(fb)):
    x = np.asarray(Image.open(os.path.join(a, f)).convert("RGB")).astype(int)
    y = np.asarray(Image.open(os.path.join(b, f)).convert("RGB")).astype(int)
    if x.shape != y.shape: print("SIZE", f, x.shape, y.shape); bad += 1; continue
    d = np.abs(x - y).max(); worst = max(worst, d)
    if d > tol: print(f"DIFF {f}: max {d}, {int((np.abs(x-y).sum(2) > tol).sum())} px"); bad += 1
print(f"{len(fa)} images, worst channel diff {worst}, {bad} over tolerance {tol}")
sys.exit(1 if bad else 0)
