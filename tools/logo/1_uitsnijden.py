import sys, numpy as np, cv2
img = cv2.imread('src/origineel.png')
H, W = img.shape[:2]
hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
L = img.mean(2)

def grab(rect, thr_fg, thr_bg, name):
    x0, y0, x1, y1 = rect
    mask = np.full((H, W), cv2.GC_BGD, np.uint8)
    sub = L[y0:y1, x0:x1]
    m = np.full(sub.shape, cv2.GC_PR_BGD, np.uint8)
    m[sub > thr_bg] = cv2.GC_PR_FGD
    m[sub > thr_fg] = cv2.GC_FGD
    mask[y0:y1, x0:x1] = m
    bgd = np.zeros((1, 65), np.float64); fgd = np.zeros((1, 65), np.float64)
    cv2.grabCut(img, mask, None, bgd, fgd, 6, cv2.GC_INIT_WITH_MASK)
    fg = ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)).astype(np.uint8)
    # grootste componenten houden (veinen weg)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(fg, 8)
    keep = np.zeros_like(fg)
    areas = stats[1:, cv2.CC_STAT_AREA]
    big = areas.max()
    for i, a in enumerate(areas, 1):
        if a > big * float(sys.argv[1] if len(sys.argv) > 1 else 0.02): keep[lab == i] = 1
    # zachte rand
    alpha = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), 0.8)
    rgba = np.dstack([img, (alpha * 255).astype(np.uint8)])
    cv2.imwrite(f'{name}.png', rgba[y0:y1, x0:x1])
    print(name, n - 1, 'componenten', int(keep.sum()))
    return keep

grab((320, 225, 990, 830), 150, 95, 'k_raw')
grab((150, 860, 1110, 1010), 160, 110, 'tekst_raw')
