#!/usr/bin/env python3
"""violet still pipeline: burst of IMX586 raw frames (pRAA, 4000x3000, RGGB) -> merged, developed JPEG.

  vpipe.py burst.raw out.jpg [--frames N] [--single]    (--single: develop only the reference frame, for A/B)

Stages: unpack -> pick sharpest reference -> dense flow per frame on binned luma ->
warp each Bayer plane (sub-pixel) -> robust Wiener-style merge in raw -> demosaic ->
white balance / colour -> tone -> chroma denoise -> sharpen.
"""
import sys, os, argparse
import numpy as np, cv2

W, H, STRIDE, BLACK, WHITE = 4000, 3000, 5008, 64.0, 1023.0
# NB: OpenCV's Bayer names are offset from the sensor layout: an RGGB sensor needs COLOR_BayerBG2BGR*, a BGGR sensor COLOR_BayerRG2BGR*.
# Using the 'matching' name swaps red and blue (gold objects turn blue) - that bug sat in every JPEG until 2026-11-04 16:30.
DEMOSAIC = cv2.COLOR_BayerBG2BGR_EA
NLM_H = 0                                  # extra luma denoise strength (small noisy sensors); set by configure()
CCM_ACTIVE = None                          # set by configure(); falls back to CCM5000

# Vendor Chromatix tuning matrices (cc13 tables) per sensor
SENSORS = {
    "imx586": dict(W=4000, H=3000, black=64.0, demosaic=cv2.COLOR_BayerBG2BGR_EA,
                   ccm=[[1.5950, -0.5476, -0.0474], [-0.2585, 1.4128, -0.1543], [0.0629, -0.6156, 1.5527]]),
    "s5k5e8": dict(W=1296, H=972, black=64.0, demosaic=cv2.COLOR_BayerGB2BGR_EA, nlm=11,      # sensor layout GRBG
                   ccm=[[1.0180, 0.0402, -0.0582], [-0.3828, 1.4965, -0.1138], [-0.1100, -0.9793, 2.0893]]),
    "ov13855": dict(W=2112, H=1568, black=64.0, demosaic=cv2.COLOR_BayerRG2BGR_EA, nlm=3,
                    ccm=[[1.5448, -0.7746, 0.2298], [-0.1326, 1.2826, -0.1500], [-0.1261, -0.6248, 1.7509]]),
}


def configure(name):
    """Select the sensor the following load/merge/develop calls work on."""
    global W, H, BLACK, DEMOSAIC, CCM_ACTIVE, NLM_H
    c = SENSORS[name]
    W, H, BLACK, DEMOSAIC = c["W"], c["H"], c["black"], c["demosaic"]
    NLM_H = c.get("nlm", 0)
    CCM_ACTIVE = np.array(c["ccm"], np.float32)


def load(path, n=None, u16=False):
    if u16:
        fsz = W * H * 2
        tot = os.path.getsize(path) // fsz
        nf = min(tot, n) if n else tot
        mm = np.memmap(path, np.uint16, 'r', shape=(tot, H, W))
        return [mm[k].astype(np.float32) - BLACK for k in range(tot - nf, tot)]     # newest nf frames
    buf = np.fromfile(path, np.uint8)
    fsz = STRIDE * H
    nf = len(buf) // fsz
    nf = min(nf, n) if n else nf
    frames = []
    for k in range(nf):
        r = buf[k * fsz:(k + 1) * fsz].reshape(H, STRIDE)[:, :5000].reshape(H, 1000, 5).astype(np.uint16)
        lo = r[:, :, 4]
        p = np.stack([(r[:, :, i] << 2) | ((lo >> (2 * i)) & 3) for i in range(4)], 2).reshape(H, W)
        frames.append(p.astype(np.float32) - BLACK)
    return frames


def planes(x):               # RGGB -> 4 half-res planes
    return np.stack([x[0::2, 0::2], x[0::2, 1::2], x[1::2, 0::2], x[1::2, 1::2]])


def interleave(p):
    x = np.empty((H, W), np.float32)
    x[0::2, 0::2], x[0::2, 1::2], x[1::2, 0::2], x[1::2, 1::2] = p
    return x


def luma(p):                 # half-res luma from planes (G weighted)
    return (p[0] + p[1] + p[2] + p[3]) * 0.25


def sharpness(l):
    return float(cv2.Laplacian(cv2.GaussianBlur(l, (0, 0), 1.0), cv2.CV_32F).var())


def to8(l):
    return np.clip(l / max(np.percentile(l, 99.5), 1) * 255, 0, 255).astype(np.uint8)


def noise_model(ref_p):
    """Fit sigma^2 = a*mean + b on flat, low-variance blocks of the reference planes."""
    g = (ref_p[1] + ref_p[2]) * 0.5
    hp = g - cv2.GaussianBlur(g, (0, 0), 1.5)
    bs = 16
    h2, w2 = (g.shape[0] // bs) * bs, (g.shape[1] // bs) * bs
    m = g[:h2, :w2].reshape(h2 // bs, bs, w2 // bs, bs).mean((1, 3)).ravel()
    v = (hp[:h2, :w2] ** 2).reshape(h2 // bs, bs, w2 // bs, bs).mean((1, 3)).ravel() * 1.35
    edges = np.percentile(m, np.linspace(0, 100, 9))
    xs, ys = [], []
    for i in range(8):
        sel = (m >= edges[i]) & (m <= edges[i + 1])
        if sel.sum() < 20:
            continue
        xs.append(m[sel].mean()); ys.append(np.percentile(v[sel], 20))
    a, b = np.polyfit(xs, ys, 1)
    return max(a, 1e-4), max(b, 0.25)


def merge(frames, log=print):
    """Align every frame to the sharpest one and merge in the raw Bayer-plane domain.
    Flow is estimated on a quarter-size luma and upsampled; the four Bayer planes are warped in one remap call."""
    P = [np.ascontiguousarray(planes(f).transpose(1, 2, 0)) for f in frames]     # HxWx4 half-res planes
    L = [p.mean(2) for p in P]
    scores = [sharpness(l) for l in L]
    r = int(np.argmax(scores))
    log(f"reference frame {r}, sharpness {['%.1f' % s for s in scores]}")
    ref = P[r]
    a, b = noise_model(ref.transpose(2, 0, 1))
    log(f"noise model sigma^2 = {a:.3f}*signal + {b:.3f}")
    hh, ww = ref.shape[:2]
    qs = (ww // 2, hh // 2)
    scale_to8 = max(np.percentile(L[r], 99.5), 1) / 255.0
    q8 = lambda l: cv2.resize(np.clip(l / scale_to8, 0, 255).astype(np.uint8), qs, interpolation=cv2.INTER_AREA)
    refq = q8(L[r])
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_FAST)
    acc, wsum = ref.copy(), np.ones((hh, ww), np.float32)
    sig2 = cv2.GaussianBlur((a * np.maximum(ref.mean(2), 0) + b).astype(np.float32), (0, 0), 1.2) * 0.5
    sig2 = np.maximum(sig2, 1e-3)
    gy, gx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    for k, p in enumerate(P):
        if k == r:
            continue
        fq = dis.calc(refq, q8(L[k]), None) * 2.0                       # quarter-res flow -> half-res pixels
        flow = cv2.resize(fq, (ww, hh), interpolation=cv2.INTER_LINEAR)
        warp = cv2.remap(p, gx + flow[..., 0], gy + flow[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
        d = cv2.GaussianBlur((warp - ref).mean(2), (0, 0), 1.2)
        w = 1.0 / (1.0 + (d * d) / (6.0 * sig2))
        w = cv2.GaussianBlur(w, (0, 0), 1.5)
        acc += warp * w[..., None]
        wsum += w
        mag = np.hypot(fq[..., 0], fq[..., 1]) / 1.0
        log(f"frame {k}: median shift {np.median(mag):.2f}px, mean weight {w.mean():.2f}")
    out = acc / wsum[..., None]
    return interleave(out.transpose(2, 0, 1)), scores, r


# Vendor Chromatix cc13 CCM, 5000 K set (tuned_ofilm_imx586.bin) - maps WB-neutralised sensor RGB -> linear sRGB.
CCM5000 = np.array([[1.5950, -0.5476, -0.0474], [-0.2585, 1.4128, -0.1543], [0.0629, -0.6156, 1.5527]], np.float32)


def estimate_wb(rgb):
    """rgb: small linear RGB (H,W,3), 1.0 = sensor white. Two stages: grey-world on valid (non-clipped, non-black) pixels as a
    starting point, then iterate on the pixels that are near-neutral under the current gains. Foliage / coloured subjects drop out
    of the second stage, which is what keeps a green garden (or a red wall) from dragging the white balance."""
    lum = rgb.mean(2)
    unclipped = rgb.max(2) < 0.95
    ref = float(np.percentile(lum[unclipped], 95)) if unclipped.sum() > 100 else float(np.percentile(lum, 95))
    valid = unclipped & (lum > max(0.12 * ref, 0.002))        # relative floor: works in a dim room and in daylight
    if valid.sum() < 50:
        valid = lum > 0.0
    mid = valid & (lum < 0.7)
    base = rgb[mid].mean(0) if mid.any() else rgb[valid].mean(0)
    g = base[1] / np.maximum(base, 1e-6)
    for _ in range(6):
        c = rgb * g
        G = c[..., 1] + 1e-6
        neutral = valid & (np.abs(c[..., 0] / G - 1) < 0.30) & (np.abs(c[..., 2] / G - 1) < 0.30)
        if neutral.mean() < 0.004:
            break
        m = rgb[neutral].mean(0)
        g = 0.5 * g + 0.5 * (m[1] / np.maximum(m, 1e-6))
    g = g / g[1]
    return np.clip(g, [0.9, 1, 0.9], [4.0, 1, 4.0])


_TONE_LUT = {}
HEADROOM = 8.0          # tone curve domain: 0 .. 8x "white"; highlights up to 3 stops over white still roll off instead of clipping


def tone_lut(knee=0.55):
    """65536-entry linear (0..HEADROOM) -> sRGB 8-bit table with a highlight shoulder."""
    if knee not in _TONE_LUT:
        v = np.linspace(0, HEADROOM, 65536, dtype=np.float32)
        over = np.maximum(v - knee, 0)
        v = np.where(v > knee, knee + (1 - knee) * (1 - np.exp(-over / (1 - knee))), v)
        s = np.where(v <= 0.0031308, 12.92 * v, 1.055 * np.power(np.maximum(v, 1e-8), 1 / 2.4) - 0.055)
        _TONE_LUT[knee] = np.clip(s * 255.0 + 0.5, 0, 255).astype(np.uint8)
    return _TONE_LUT[knee]


def develop(x, log=print, tone_strength=1.0):
    """x: merged/black-subtracted Bayer (float32 H x W) -> BGR uint8. All heavy steps are OpenCV SIMD ops."""
    x = np.clip(x, 0, WHITE - BLACK)
    img16 = (x * (65535.0 / (WHITE - BLACK))).astype(np.uint16)
    bgr16 = cv2.cvtColor(img16, DEMOSAIC)
    small = cv2.resize(bgr16, (bgr16.shape[1] // 8, bgr16.shape[0] // 8), interpolation=cv2.INTER_AREA).astype(np.float32) / 65535.0
    rgb_s = small[..., ::-1]
    g = estimate_wb(rgb_s)                                    # R,G,B gains
    base_ccm = CCM_ACTIVE if CCM_ACTIVE is not None else CCM5000
    ccm = base_ccm / base_ccm.sum(1, keepdims=True)
    Mrgb = ccm * g[None, :]                                   # applies WB first, then CCM
    srgb_small = np.clip(rgb_s @ Mrgb.T, 0, None)
    lum_s = 0.2126 * srgb_small[..., 0] + 0.7152 * srgb_small[..., 1] + 0.0722 * srgb_small[..., 2]
    sat_s = small.max(2)                                      # raw saturation per pixel (1.0 = clipped)
    ok = sat_s < 0.95
    med = float(np.median(lum_s[ok])) if ok.sum() > 100 else float(np.median(lum_s))
    # Exposure from the mid-tones (median -> 0.18 linear = mid grey), not from the brightest pixels: a bright sky must not darken
    # the subject. Limited so that the 99th percentile stays inside the tone curve's headroom, and capped against noise.
    scale = min(0.18 / max(med, 1e-4), HEADROOM / max(float(np.percentile(lum_s, 99.0)), 1e-4), 40.0)
    log(f"WB gains R,G,B = {g}  median {med:.4f}  exposure scale {scale:.2f}")
    Mrgb = Mrgb * scale
    lum_t = lum_s * scale
    base = cv2.GaussianBlur(np.minimum(lum_t, 1.0).astype(np.float32), (0, 0), 6)
    lift = np.clip((0.30 / np.maximum(base, 0.02)) ** (0.45 * tone_strength), 1.0, 2.8).astype(np.float32)   # open the shadows
    lift = cv2.resize(lift, (bgr16.shape[1], bgr16.shape[0]), interpolation=cv2.INTER_LINEAR)
    Mbgr = Mrgb[::-1, ::-1].astype(np.float32)                # BGR in -> BGR out
    f = cv2.transform(bgr16.astype(np.float32), Mbgr * (1.0 / 65535.0))
    f = cv2.multiply(f, cv2.merge([lift, lift, lift]))
    # clipped highlights: the sensor saturated, so any hue there is an artefact of WB gains / CCM -> fade them to neutral
    s_small = np.clip((sat_s - 0.88) / 0.11, 0, 1)
    if s_small.max() > 0.01:
        s_full = cv2.resize(cv2.GaussianBlur(s_small.astype(np.float32), (0, 0), 1.0), (bgr16.shape[1], bgr16.shape[0]),
                            interpolation=cv2.INTER_LINEAR)
        lum_f = cv2.transform(f, np.array([[0.0722, 0.7152, 0.2126]], np.float32))
        if lum_f.ndim == 3:
            lum_f = lum_f[..., 0]
        d = (lum_f - 0) * s_full
        f = f * cv2.merge([1 - s_full] * 3) + cv2.merge([d, d, d])
    idx = np.clip(f * (65535.0 / HEADROOM), 0, 65535).astype(np.uint16)
    y8 = tone_lut()[idx]
    ycc = cv2.cvtColor(y8, cv2.COLOR_BGR2YCrCb)
    for c in (1, 2):
        h = cv2.resize(ycc[..., c], (ycc.shape[1] // 2, ycc.shape[0] // 2), interpolation=cv2.INTER_AREA)
        h = cv2.bilateralFilter(h, 7, 10, 4)
        ycc[..., c] = cv2.resize(h, (ycc.shape[1], ycc.shape[0]), interpolation=cv2.INTER_LINEAR)
    yl = ycc[..., 0]
    if NLM_H:
        yl = cv2.fastNlMeansDenoising(yl, None, NLM_H, 5, 15)        # small noisy sensors: real denoise before sharpening
    ycc[..., 0] = cv2.addWeighted(yl, 1.7, cv2.GaussianBlur(yl, (0, 0), 1.4), -0.7, 0)
    return cv2.cvtColor(ycc, cv2.COLOR_YCrCb2BGR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("burst"); ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=None)
    ap.add_argument("--single", action="store_true")
    ap.add_argument("--sensor", default="imx586")
    ap.add_argument("--u16", action="store_true", help="input is unpacked uint16 frames (vcamd shotu)")
    ap.add_argument("--rotate", type=int, default=0, help="degrees clockwise: 0/90/180/270")
    a = ap.parse_args()
    configure(a.sensor)
    frames = load(a.burst, a.frames, a.u16)
    print(f"{len(frames)} frames")
    if a.single:
        P = [planes(f) for f in frames]
        r = int(np.argmax([sharpness(luma(p)) for p in P]))
        x = frames[r]
    else:
        x, _, _ = merge(frames)
    out = develop(x)
    out = {0: out, 90: cv2.rotate(out, cv2.ROTATE_90_CLOCKWISE), 180: cv2.rotate(out, cv2.ROTATE_180),
           270: cv2.rotate(out, cv2.ROTATE_90_COUNTERCLOCKWISE)}[a.rotate]
    cv2.imwrite(a.out, out, [cv2.IMWRITE_JPEG_QUALITY, 95])
    print("wrote", a.out)


if __name__ == "__main__":
    main()
