/*
 * vcamd: zero-shutter-lag capture daemon for the violet cameras (rear IMX586 + DW9800 VCM, front OV13855 fixed focus).
 *
 * Keeps the RDI node streaming, runs continuous auto-exposure, keeps the newest RING raw frames (packed 10-bit) in RAM,
 * publishes a live viewfinder image, and (rear) runs contrast autofocus: small hill-climb from the current lens position
 * (tap / scene change), wide search only as a fallback. Commands arrive on a FIFO:
 *     shot <N> <path>   write the newest N stable frames (packed) to <path>
 *     shotu <N> <path>  same, unpacked to little-endian uint16 (N=0: choose from scene brightness)
 *                       -> prints "OK <path> <n> <exp> <gain> <lens>"
 *     af                focus now (local search, wide fallback)       -> "AF <lens>"
 *     wideaf            force the wide search                          -> "AF <lens>"
 *     caf on|off        continuous autofocus (default on for the rear)
 *     status            "STATUS exp=.. gain=.. lens=.. ring=.."
 *     quit
 * Replies go to <fifo>.out; the viewfinder to <fifo>.preview ("w h\n" + RGB24).
 *
 *   vcamd <video> <vcm-subdev|-> <exp-subdev> <fifo> <W> <H> <RGGB|BGGR|GBRG|GRBG> <black> <smia|ov|s5k> <max-exp> <max-gain>
 *         <preview-rot 90|270> <mirror 0|1> <imx586|ov13855|s5k5e8>
 * The media pipeline must already be linked (violet-camera.py does that).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define NBUF 4
#define RING 6
#define TARGET 150.0

static int W, H, vfd, sfd = -1, efd, stride;
static double black = 64, max_exp = 2600, max_gain = 16;
static int gain_ov;                                   /* 0: SMIA gain code, 1: OV13855 (code = 256 * x), 2: S5K5E8 (code = 32 * x) */
static char bayer[5] = "RGGB";
static int pv_rot = 90, pv_mirror;
static const double *ccm;
static void *bufp[NBUF];

struct frame { uint8_t *data; int gen; double exp, gain; unsigned seq; };
static struct frame ring[RING];
static int ring_n, ring_head, ae_gen;
static double cur_exp = 1500, cur_gain = 1.0;
static int lens = 512;
static unsigned seqno;
static int ae_hold, ae_freeze;
static FILE *g_out;
static const char *preview_path;

/* vendor Chromatix 5000 K / 4900 K CCMs (rows are normalised to sum 1 when applied) */
static const double CCM_IMX586[9] = { 1.5950, -0.5476, -0.0474, -0.2585, 1.4128, -0.1543, 0.0629, -0.6156, 1.5527 };
static const double CCM_OV13855[9] = { 1.5448, -0.7746, 0.2298, -0.1326, 1.2826, -0.1500, -0.1261, -0.6248, 1.7509 };
static const double CCM_S5K5E8[9] = { 1.0180, 0.0402, -0.0582, -0.3828, 1.4965, -0.1138, -0.1100, -0.9793, 2.0893 };

static int setctrl(int fd, unsigned id, int v)
{
	struct v4l2_control c = { .id = id, .value = v };
	return ioctl(fd, VIDIOC_S_CTRL, &c);
}

static int gain_code(double x)
{
	if (gain_ov == 1) { int c = (int)lround(x * 256.0); return c < 128 ? 128 : c > 1984 ? 1984 : c; }
	if (gain_ov == 2) { int c = (int)lround(x * 32.0); return c < 32 ? 32 : c > 512 ? 512 : c; }
	return (int)lround(1024.0 - 1024.0 / x);
}

static void apply_ae(double exp, double gain)
{
	cur_exp = exp; cur_gain = gain;
	setctrl(efd, V4L2_CID_EXPOSURE, (int)exp);
	setctrl(efd, V4L2_CID_ANALOGUE_GAIN, gain_code(gain));
	ae_gen++;
	ae_hold = 3;
}

static int qbuf(int idx)
{
	struct v4l2_plane pl[1]; struct v4l2_buffer b;
	memset(&b, 0, sizeof b); memset(pl, 0, sizeof pl);
	b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP;
	b.index = idx; b.m.planes = pl; b.length = 1;
	return ioctl(vfd, VIDIOC_QBUF, &b);
}

static int dqbuf(void)
{
	struct v4l2_plane pl[1]; struct v4l2_buffer b;
	memset(&b, 0, sizeof b); memset(pl, 0, sizeof pl);
	b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP;
	b.m.planes = pl; b.length = 1;
	if (ioctl(vfd, VIDIOC_DQBUF, &b)) return -1;
	return b.index;
}

#define PX(f, y, x) ((f)[(size_t)(y) * stride + ((x) >> 2) * 5 + ((x) & 3)])
/* full 10-bit value: the 5th byte of each 4-pixel group holds the two low bits of each pixel */
#define PX10(f, y, x) (((int)PX(f, y, x) << 2) | (((f)[(size_t)(y) * stride + ((x) >> 2) * 5 + 4] >> (2 * ((x) & 3))) & 3))

/* ---------------------------------------------------------------- auto exposure */
static void meter(const uint8_t *f, double *mean, double *hi)
{
	int hist[256] = { 0 }; long n = 0; double s = 0;
	for (int y = 8; y < H; y += 24)
		for (int x = 8; x < W; x += 24) { int v = PX(f, y, x); hist[v]++; s += v; n++; }
	*mean = s / n * 4.0 - black; if (*mean < 0.5) *mean = 0.5;
	long acc = 0; int p = 255;
	for (; p > 0; p--) { acc += hist[p]; if (acc > n / 200) break; }
	*hi = p * 4.0 - black;
}

static void ae_step(const uint8_t *f)
{
	if (ae_freeze) return;
	if (ae_hold > 0) { ae_hold--; return; }
	double mean, hi; meter(f, &mean, &hi);
	double scale = TARGET / mean;
	if (hi * scale > 900.0) scale = 900.0 / (hi > 1 ? hi : 1);
	if (scale > 0.8 && scale < 1.25) return;          /* deadband: stable exposure = usable ring */
	double total = cur_exp * cur_gain * scale, e = total, g = 1.0;
	if (e > max_exp) { g = e / max_exp; e = max_exp; }
	if (e < 8) e = 8;
	if (g > max_gain) g = max_gain;
	if (g < 1.0) g = 1.0;
	apply_ae(e, g);
}

/* ---------------------------------------------------------------- viewfinder */
static int pv_w, pv_h, pv_b;
static uint8_t *pv_rgb;
static float *pv_lin;

static void write_preview(const uint8_t *f)
{
	if (!pv_rgb) return;
	/* where R, B and the two G sit in a 2x2 Bayer cell */
	int rp = 0, bp = 0, g1 = -1, g2 = -1;
	for (int i = 0; i < 4; i++) {
		if (bayer[i] == 'R') rp = i; else if (bayer[i] == 'B') bp = i; else if (g1 < 0) g1 = i; else g2 = i;
	}
	double sum[3] = { 0, 0, 0 };
	#pragma omp parallel for reduction(+:sum[:3]) schedule(static)
	for (int y = 0; y < pv_h; y++)
		for (int x = 0; x < pv_w; x++) {
			int x2 = pv_mirror ? pv_w - 1 - x : x, sy, sx;
			if (pv_rot == 90) { sy = H - pv_b - x2 * pv_b; sx = y * pv_b; } else { sy = x2 * pv_b; sx = W - pv_b - y * pv_b; }
			int cy = sy & ~1, cx = sx & ~1;
			if (cy > H - 4) cy = H - 4;
			if (cx > W - 4) cx = W - 4;
			double r = 0, g = 0, b = 0;
			for (int oy = 0; oy < 4; oy += 2)
				for (int ox = 0; ox < 4; ox += 2) {
					r += PX10(f, cy + oy + (rp >> 1), cx + ox + (rp & 1));
					b += PX10(f, cy + oy + (bp >> 1), cx + ox + (bp & 1));
					g += PX10(f, cy + oy + (g1 >> 1), cx + ox + (g1 & 1)) + PX10(f, cy + oy + (g2 >> 1), cx + ox + (g2 & 1));
				}
			float *l = pv_lin + ((size_t)y * pv_w + x) * 3;
			l[0] = (float)(r / 4 - black); l[1] = (float)(g / 8 - black); l[2] = (float)(b / 4 - black);
			for (int c = 0; c < 3; c++) { if (l[c] < 0) l[c] = 0; sum[c] += l[c]; }
		}
	double gr = sum[1] / (sum[0] + 1e-6), gb = sum[1] / (sum[2] + 1e-6);
	if (gr > 4) gr = 4;
	if (gb > 4) gb = 4;
	double mean = sum[1] / ((double)pv_w * pv_h) + 1e-6, k = 0.30 * 1023.0 / (mean > 4 ? mean : 4);   /* mid-grey at ~30 % */
	static uint8_t lut[4096]; static int lut_ok;
	if (!lut_ok) { for (int i = 0; i < 4096; i++) { double v = i / 4095.0; lut[i] = (uint8_t)(255.0 * pow(v > 1 ? 1 : v, 1 / 2.2)); } lut_ok = 1; }
	double gain[3] = { gr * k, k, gb * k }, M[3][3], rs[3];
	for (int r = 0; r < 3; r++) { rs[r] = ccm[3*r] + ccm[3*r+1] + ccm[3*r+2]; for (int c = 0; c < 3; c++) M[r][c] = ccm[3*r+c] / rs[r]; }
	#pragma omp parallel for schedule(static)
	for (int y = 0; y < pv_h; y++)
		for (int x = 0; x < pv_w; x++) {
			const float *l = pv_lin + ((size_t)y * pv_w + x) * 3;
			double in[3] = { l[0] * gain[0] / 1023.0, l[1] * gain[1] / 1023.0, l[2] * gain[2] / 1023.0 };
			for (int c = 0; c < 3; c++) if (in[c] > 1.0) in[c] = 1.0;          /* clipped highlights -> white, not tinted by WB gains */
			for (int r = 0; r < 3; r++) {
				double o = M[r][0] * in[0] + M[r][1] * in[1] + M[r][2] * in[2];
				if (o < 0) o = 0;
				int idx = (int)(o * 4095.0);
				pv_rgb[((size_t)y * pv_w + x) * 3 + r] = lut[idx > 4095 ? 4095 : idx];
			}
		}
	char tmp[300]; snprintf(tmp, sizeof tmp, "%s.tmp", preview_path);
	FILE *o = fopen(tmp, "wb"); if (!o) return;
	fprintf(o, "%d %d\n", pv_w, pv_h); fwrite(pv_rgb, 1, (size_t)pv_w * pv_h * 3, o); fclose(o); rename(tmp, preview_path);
}

/* ---------------------------------------------------------------- autofocus (rear only) */
#define GX 5
#define GY 4
#define NW (GX * GY)
static int *cellg, gw, gh;

static int cell(const uint8_t *f, int cy, int cx)
{
	int s = 0;
	for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++) s += PX10(f, 8 * cy + y, 8 * cx + x);
	return s;
}

/* per-window brightness-normalised Laplacian energy of 8x8-binned cells (binning beats low-light noise) */
static void af_windows(const uint8_t *f, double *ws)
{
	#pragma omp parallel for schedule(static)
	for (int cy = 0; cy < gh; cy++)
		for (int cx = 0; cx < gw; cx++) cellg[cy * gw + cx] = cell(f, cy, cx);
	int wh = gh / GY, ww = gw / GX;
	for (int wy = 0; wy < GY; wy++)
		for (int wx = 0; wx < GX; wx++) {
			double s = 0, m = 0; long n = 0;
			for (int y = wy * wh + 1; y < (wy + 1) * wh - 1; y++)
				for (int x = wx * ww + 1; x < (wx + 1) * ww - 1; x++) {
					int *g = cellg + y * gw + x;
					int l = 4 * g[0] - g[-gw] - g[gw] - g[-1] - g[1];
					s += (double)l * l; m += g[0]; n++;
				}
			m /= n; if (m < 1) m = 1;
			ws[wy * GX + wx] = s / n / (m * m) * 1e3;
		}
}

/* move the lens in small steps: big jumps ring the VCM spring and click audibly */
#define LENS_STEP 20
static void set_lens(int pos)
{
	if (sfd < 0) return;
	if (pos < 0) pos = 0;
	if (pos > 1023) pos = 1023;
	while (lens != pos) {
		int d = pos - lens;
		lens += d > LENS_STEP ? LENS_STEP : d < -LENS_STEP ? -LENS_STEP : d;
		setctrl(sfd, V4L2_CID_FOCUS_ABSOLUTE, lens);
		if (lens != pos) usleep(1500);
	}
	setctrl(sfd, V4L2_CID_FOCUS_ABSOLUTE, lens);
}

/* take a live frame after dropping `skip` frames; returns buffer index (caller requeues) */
static int live_frame(int skip)
{
	int i = -1;
	for (int k = 0; k < skip + 1; k++) { i = dqbuf(); if (i < 0) return -1; if (k < skip) qbuf(i); }
	return i;
}

static int dark_scene(void) { return cur_gain * cur_exp / 2600.0 > 8.0; }

/* window scores at lens position `pos` (viewfinder stays alive); dark scenes average two frames */
static int af_eval(int pos, double *ws)
{
	set_lens(pos);
	int i = live_frame(2); if (i < 0) return -1;
	af_windows(bufp[i], ws); write_preview(bufp[i]); qbuf(i);
	if (dark_scene()) {
		double w2[NW]; i = live_frame(0); if (i < 0) return -1;
		af_windows(bufp[i], w2); qbuf(i);
		for (int k = 0; k < NW; k++) ws[k] = 0.5 * (ws[k] + w2[k]);
	}
	return 0;
}

static double ref_[NW], wt_[NW], af_base;                /* wide-search window references / weights; baseline for CAF */
static double af_combined(const double *ws)
{
	double c = 0, w = 0;
	for (int i = 0; i < NW; i++) if (wt_[i] > 0) { c += wt_[i] * ws[i] / ref_[i]; w += wt_[i]; }
	return w > 0 ? c / w : 0;
}

/* total detail energy: used to notice that the scene went soft or changed */
static double af_energy(const double *ws) { double s = 0; for (int i = 0; i < NW; i++) s += ws[i]; return s; }

/* wide search: 11 positions over the whole travel, then two refinements. Visible as a focus "pump": fallback only. */
static int run_wide_af(void)
{
	if (sfd < 0) return lens;
	enum { NC = 11 };
	double all[NC][NW]; int pos[NC], n = 0;
	for (int p = 200; p <= 1030 && n < NC; p += 82, n++) { pos[n] = p > 1023 ? 1023 : p; if (af_eval(pos[n], all[n])) return lens; }
	int usable = 0;
	for (int w = 0; w < NW; w++) {
		double mx = 0, v[NC], tmp;
		for (int k = 0; k < n; k++) { v[k] = all[k][w]; if (v[k] > mx) mx = v[k]; }
		for (int i = 1; i < n; i++) for (int j = i; j > 0 && v[j-1] > v[j]; j--) { tmp = v[j]; v[j] = v[j-1]; v[j-1] = tmp; }
		ref_[w] = v[n / 2] > 1e-9 ? v[n / 2] : 1e-9;
		wt_[w] = (mx / ref_[w] > 1.4) ? 1.0 : 0.0;       /* real focus peak vs noise wobble */
		usable += wt_[w] > 0;
	}
	int best = lens; double bs = -1;
	for (int k = 0; k < n; k++) {
		double c = af_combined(all[k]);
		if (g_out) fprintf(g_out, "AFSCORE %d %.3f usable=%d exp=%.0f gain=%.2f\n", pos[k], c, usable, cur_exp, cur_gain);
		if (c > bs) { bs = c; best = pos[k]; }
	}
	if (usable == 0 || bs < 1.12) {                                 /* no confident peak (plain/dark scene): mid-distance default */
		set_lens(420);
		double ws[NW]; if (!af_eval(420, ws)) af_base = af_energy(ws);
		return 420;
	}
	for (int step = 32; step >= 16; step /= 2) {
		int c0 = best;
		for (int d = -1; d <= 1; d += 2) {
			int p = c0 + d * step; if (p < 150 || p > 1023) continue;
			double ws[NW]; if (af_eval(p, ws)) break;
			double c = af_combined(ws); if (c > bs) { bs = c; best = p; }
		}
	}
	set_lens(best);
	double ws[NW]; if (!af_eval(best, ws)) af_base = af_energy(ws);
	return best;
}

/* Does lens position B show more detail than A? Weighted vote over the windows whose change exceeds the frame-to-frame noise. */
static double af_vote(const double *a, const double *b, const double *noise, int *nsig)
{
	double v = 0; *nsig = 0;
	for (int w = 0; w < NW; w++) {
		double d = (b[w] - a[w]) / noise[w];
		if (fabs(d) > 2.0) { v += d > 6 ? 6 : d < -6 ? -6 : d; (*nsig)++; }
	}
	return v;
}

/* Hill-climb from the current lens position in steps of 32 -> 8 codes: a small, hardly visible focus wobble.
 * Returns 1 when it settled, 0 when there is no usable gradient (plain / very blurred scene) -> caller may go wide. */
static int run_local_af(void)
{
	if (sfd < 0) return 1;
	double cur[NW], a2[NW], nxt[NW], noise[NW];
	if (af_eval(lens, cur)) return 0;
	{ int i = live_frame(0); if (i < 0) return 0; af_windows(bufp[i], a2); qbuf(i); }
	for (int w = 0; w < NW; w++) { noise[w] = fabs(cur[w] - a2[w]) * 0.9 + 0.03 * cur[w] + 1e-3; }
	int step = 48, dir = 1, evals = 0, settled = 0, improved = 0, any_gradient = 0, bounced = 0;
	/* Accelerating hill-climb: while the picture keeps improving the step doubles (up to 128 codes) so a far-away peak is reached
	 * in a handful of frames; once the peak is bracketed (an improvement followed by a worse probe) it halves down to 8 codes. Not
	 * bracketing it within the eval budget means the peak is far away or absent -> report failure so the caller does the wide search. */
	while (step >= 8 && evals < 24) {
		int pos = lens + dir * step;
		if (pos < 150 || pos > 1023) { if (++bounced > 3) break; dir = -dir; step /= 2; settled = improved; continue; }
		if (af_eval(pos, nxt)) return 0;
		evals++;
		int nsig; double v = af_vote(cur, nxt, noise, &nsig);
		if (nsig >= 2) any_gradient = 1;
		if (v > 0) { memcpy(cur, nxt, sizeof cur); improved = 1; if (!settled && step < 128) step *= 2; }   /* better: keep going, faster */
		else { set_lens(lens - dir * step); dir = -dir; step /= 2; if (improved) settled = 1; }          /* worse: back, reverse; bracketed once we had improved */
	}
	if (!any_gradient || !settled) return 0;
	af_base = af_energy(cur);
	return 1;
}

static int run_af(void)
{
	if (sfd < 0) return lens;
	if (!run_local_af()) run_wide_af();
	return lens;
}

/* ---------------------------------------------------------------- ring buffer and shots */
static void store(int idx)
{
	struct frame *fr = &ring[ring_head];
	if (!fr->data) fr->data = malloc((size_t)stride * H);
	memcpy(fr->data, bufp[idx], (size_t)stride * H);
	fr->gen = ae_gen; fr->exp = cur_exp; fr->gain = cur_gain; fr->seq = seqno;
	ring_head = (ring_head + 1) % RING;
	if (ring_n < RING) ring_n++;
}

static void reply(FILE *out, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt); vfprintf(out, fmt, ap); va_end(ap); fflush(out);
}

static int auto_frames(void)
{
	double d = cur_gain * cur_exp / (max_gain * max_exp);   /* 1.0 = AE pinned at this sensor's limits */
	return d < 0.094 ? 1 : d < 0.25 ? 2 : d < 0.625 ? 3 : d < 0.875 ? 4 : 6;     /* darker = more frames to average the noise away */
}

static int do_shot(int n, const char *path, FILE *out, int unpack)
{
	if (n <= 0) n = auto_frames();
	int tries = 0;
	for (;;) {
		int i = dqbuf(); if (i < 0) return -1;
		seqno++; store(i); qbuf(i);
		if (ae_hold > 0) ae_hold--;
		int newest = (ring_head + RING - 1) % RING, ok = (ring_n >= n && ae_hold == 0);
		for (int k = 0; ok && k < n; k++)
			if (ring[(newest - k + RING) % RING].gen != ring[newest].gen) ok = 0;
		if (ok) break;
		if (++tries > 40) break;
	}
	int avail = ring_n < n ? ring_n : n, newest = (ring_head + RING - 1) % RING;
	FILE *f = fopen(path, "wb");
	if (!f) { reply(out, "ERR open %s\n", path); return -1; }
	int written = 0;
	uint16_t *row = malloc(sizeof(uint16_t) * W);
	for (int k = avail - 1; k >= 0; k--) {
		struct frame *fr = &ring[(newest - k + RING) % RING];
		if (fr->gen != ring[newest].gen) continue;
		if (!unpack) fwrite(fr->data, 1, (size_t)stride * H, f);
		else {
			for (int y = 0; y < H; y++) {
				const uint8_t *p = fr->data + (size_t)y * stride;
				for (int x = 0; x < W; x += 4, p += 5)
					for (int k2 = 0; k2 < 4; k2++) row[x + k2] = (uint16_t)(p[k2] << 2 | ((p[4] >> (2 * k2)) & 3));
				fwrite(row, sizeof row[0], W, f);
			}
		}
		written++;
	}
	free(row);
	fclose(f);
	reply(out, "OK %s %d %.0f %.2f %d\n", path, written, ring[newest].exp, ring[newest].gain, lens);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 15) {
		fprintf(stderr, "usage: vcamd <video> <vcm|-> <exp-sd> <fifo> <W> <H> <bayer> <black> <smia|ov|s5k> <max-exp> <max-gain> <rot> <mirror> <sensor>\n");
		return 2;
	}
	setenv("OMP_NUM_THREADS", "3", 0);                 /* focus scoring must not starve the compositor */
	vfd = open(argv[1], O_RDWR);
	if (strcmp(argv[2], "-")) sfd = open(argv[2], O_RDWR);
	efd = open(argv[3], O_RDWR);
	if (vfd < 0 || efd < 0 || (strcmp(argv[2], "-") && sfd < 0)) { perror("open"); return 1; }
	const char *fifo = argv[4];
	W = atoi(argv[5]); H = atoi(argv[6]); snprintf(bayer, sizeof bayer, "%s", argv[7]);
	black = atof(argv[8]); gain_ov = !strcmp(argv[9], "ov") ? 1 : !strcmp(argv[9], "s5k") ? 2 : 0; max_exp = atof(argv[10]); max_gain = atof(argv[11]);
	pv_rot = atoi(argv[12]); pv_mirror = atoi(argv[13]); ccm = !strcmp(argv[14], "ov13855") ? CCM_OV13855 : !strcmp(argv[14], "s5k5e8") ? CCM_S5K5E8 : CCM_IMX586;
	gw = W / 8; gh = H / 8; cellg = malloc(sizeof(int) * gw * gh);
	{ int longest = W > H ? W : H; pv_b = (longest + 1099) / 1100; if (pv_b < 2) pv_b = 2;
	  pv_w = H / pv_b; pv_h = W / pv_b; pv_rgb = malloc((size_t)pv_w * pv_h * 3); pv_lin = malloc(sizeof(float) * pv_w * pv_h * 3); }
	static char pvp[300]; snprintf(pvp, sizeof pvp, "%s.preview", fifo); preview_path = pvp;
	char outp[300]; snprintf(outp, sizeof outp, "%s.out", fifo);
	unlink(fifo); if (mkfifo(fifo, 0666)) { perror("mkfifo"); return 1; }
	int cfd = open(fifo, O_RDWR | O_NONBLOCK);
	FILE *out = fopen(outp, "a"); if (!out) { perror("out"); return 1; }
	g_out = out; setvbuf(out, NULL, _IOLBF, 0);

	unsigned pixfmt = !strcmp(bayer, "BGGR") ? V4L2_PIX_FMT_SBGGR10P : !strcmp(bayer, "GBRG") ? V4L2_PIX_FMT_SGBRG10P :
			  !strcmp(bayer, "GRBG") ? V4L2_PIX_FMT_SGRBG10P : V4L2_PIX_FMT_SRGGB10P;
	struct v4l2_format fmt = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE };
	fmt.fmt.pix_mp.width = W; fmt.fmt.pix_mp.height = H; fmt.fmt.pix_mp.num_planes = 1;
	fmt.fmt.pix_mp.pixelformat = pixfmt; fmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
	if (ioctl(vfd, VIDIOC_S_FMT, &fmt)) perror("s_fmt");
	stride = fmt.fmt.pix_mp.plane_fmt[0].bytesperline;
	struct v4l2_requestbuffers rb = { .count = NBUF, .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE, .memory = V4L2_MEMORY_MMAP };
	if (ioctl(vfd, VIDIOC_REQBUFS, &rb)) { perror("reqbufs"); return 1; }
	for (unsigned i = 0; i < rb.count; i++) {
		struct v4l2_plane pl[1]; struct v4l2_buffer b;
		memset(&b, 0, sizeof b); memset(pl, 0, sizeof pl);
		b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP;
		b.index = i; b.m.planes = pl; b.length = 1;
		ioctl(vfd, VIDIOC_QUERYBUF, &b);
		bufp[i] = mmap(0, pl[0].length, PROT_READ, MAP_SHARED, vfd, pl[0].m.mem_offset);
		qbuf(i);
	}
	apply_ae(cur_exp, cur_gain);
	if (sfd >= 0) { lens = 420; setctrl(sfd, V4L2_CID_FOCUS_ABSOLUTE, lens); }
	int t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (ioctl(vfd, VIDIOC_STREAMON, &t)) { perror("streamon"); return 1; }
	signal(SIGPIPE, SIG_IGN);

	char line[512]; int ll = 0, af_done = sfd < 0, warm = 0, caf = sfd >= 0, caf_bad = 0, since_af = 0, announced = 0;
	for (;;) {
		struct pollfd pf[2] = { { vfd, POLLIN, 0 }, { cfd, POLLIN, 0 } };
		if (poll(pf, 2, 1000) <= 0) continue;
		if (pf[0].revents & POLLIN) {
			int i = dqbuf();
			if (i >= 0) {
				seqno++;
				ae_step(bufp[i]);
				if (seqno % 4 == 0) write_preview(bufp[i]);
				store(i);
				/* continuous AF: watch the detail energy; refocus (locally) when it keeps changing */
				if (caf && af_done && ae_hold == 0 && ++since_af > 12 && seqno % 8 == 0) {
					double ws[NW]; af_windows(bufp[i], ws);
					double e = af_energy(ws), r = af_base > 1e-9 ? e / af_base : 1.0;
					caf_bad = (r < 0.65 || r > 1.55) ? caf_bad + 1 : 0;
					if (caf_bad >= 3) { qbuf(i); i = -1; ae_freeze = 1; run_af(); ae_freeze = 0; caf_bad = 0; since_af = -60; }
				}
				if (i >= 0) qbuf(i);
				if (!af_done && ++warm > 25 && ae_hold == 0) { ae_freeze = 1; run_wide_af(); ae_freeze = 0; af_done = 1; since_af = 0; reply(out, "AF %d\n", lens); }
				if (af_done && !announced) { announced = 1; reply(out, "READY stride=%d\n", stride); }
			}
		}
		if (pf[1].revents & POLLIN) {
			char c;
			while (read(cfd, &c, 1) == 1) {
				if (c != '\n' && ll < (int)sizeof line - 1) { line[ll++] = c; continue; }
				line[ll] = 0; ll = 0;
				int n; char path[300];
				if (sscanf(line, "shotu %d %299s", &n, path) == 2) {
					ae_freeze = 1; do_shot(n > RING ? RING : n, path, out, 1); ae_freeze = 0;
				} else if (sscanf(line, "shot %d %299s", &n, path) == 2) {
					ae_freeze = 1; do_shot(n > RING ? RING : n, path, out, 0); ae_freeze = 0;
				} else if (!strcmp(line, "af") || !strcmp(line, "wideaf")) {
					if (sfd < 0) { reply(out, "AF none\n"); continue; }
					ae_freeze = 1; if (line[0] == 'w') run_wide_af(); else run_af(); ae_freeze = 0;
					since_af = 0; caf_bad = 0; reply(out, "AF %d\n", lens);
				} else if (sscanf(line, "lens %d", &n) == 1) {                     /* debug: park the lens */
					set_lens(n); reply(out, "LENS %d\n", lens);
				} else if (!strncmp(line, "caf", 3)) {
					caf = sfd >= 0 && strstr(line, "on") != NULL; reply(out, "CAF %d\n", caf);
				} else if (!strcmp(line, "status")) {
					reply(out, "STATUS exp=%.0f gain=%.2f lens=%d ring=%d\n", cur_exp, cur_gain, sfd >= 0 ? lens : -1, ring_n);
				} else if (!strcmp(line, "quit")) {
					ioctl(vfd, VIDIOC_STREAMOFF, &t); return 0;
				}
			}
		}
	}
}
