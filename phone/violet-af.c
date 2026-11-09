/*
 * violet-af: contrast autofocus for the rear IMX586 + DW9800.
 * Streams raw (pRAA) from the RDI node, steps the VCM, scores a central ROI and
 * does coarse-to-fine search. Pipeline must already be linked (see cap.sh).
 *   violet-af <video> <vcm-subdev> <exp-subdev> <exposure> <gain> [--sweep]
 * Prints the best lens code on stdout (last line "BEST <n>").
 */
#include <fcntl.h>
#include <linux/videodev2.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define W 4000
#define H 3000
#define NBUF 4
static void *bufp[NBUF]; static int vfd, sfd, stride;

static int setctrl(int fd, unsigned id, int v)
{
	struct v4l2_control c = { .id = id, .value = v };
	return ioctl(fd, VIDIOC_S_CTRL, &c);
}

static int qbuf(int idx)
{
	struct v4l2_plane pl[1]; struct v4l2_buffer b;
	memset(&b, 0, sizeof b); memset(pl, 0, sizeof pl);
	b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP;
	b.index = idx; b.m.planes = pl; b.length = 1;
	return ioctl(vfd, VIDIOC_QBUF, &b);
}

/* drop `skip` frames, return the next one's index (caller requeues it) */
static int grab(int skip)
{
	struct v4l2_plane pl[1]; struct v4l2_buffer b;
	for (int i = 0; i <= skip; i++) {
		memset(&b, 0, sizeof b); memset(pl, 0, sizeof pl);
		b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE; b.memory = V4L2_MEMORY_MMAP;
		b.m.planes = pl; b.length = 1;
		if (ioctl(vfd, VIDIOC_DQBUF, &b)) return -1;
		if (i < skip) qbuf(b.index);
	}
	return b.index;
}

/* 4x4-binned Laplacian energy over a central ROI (binning averages sensor noise away) */
#define PX(f, y, x) ((f)[(size_t)(y) * stride + ((x) >> 2) * 5 + ((x) & 3)])
static int cell(const uint8_t *f, int cy, int cx)
{
	int s = 0;
	for (int y = 0; y < 4; y++)
		for (int x = 0; x < 4; x++)
			s += PX(f, 4 * cy + y, 4 * cx + x);
	return s;
}
static double score(const uint8_t *f)
{
	double s = 0, m = 0; int cy0 = 190, cy1 = 560, cx0 = 250, cx1 = 750;
	static int g[372][502];
	for (int cy = cy0 - 1; cy <= cy1; cy++)
		for (int cx = cx0 - 1; cx <= cx1; cx++)
			g[cy - cy0 + 1][cx - cx0 + 1] = cell(f, cy, cx);
	for (int y = 1; y <= cy1 - cy0; y++)
		for (int x = 1; x <= cx1 - cx0; x++) {
			m += g[y][x];
			int l = 4 * g[y][x] - g[y-1][x] - g[y+1][x] - g[y][x-1] - g[y][x+1];
			s += (double)l * l;
		}
	m /= (double)(cy1 - cy0) * (cx1 - cx0);
	return s / (m * m) * 1e3;	/* brightness-normalised: flicker-proof */
}

static double at(int pos, int settle)
{
	setctrl(sfd, V4L2_CID_FOCUS_ABSOLUTE, pos);
	int i = grab(settle);
	if (i < 0) return -1;
	double s = score(bufp[i]);
	qbuf(i);
	return s;
}

int main(int argc, char **argv)
{
	if (argc < 6) { fprintf(stderr, "usage\n"); return 2; }
	vfd = open(argv[1], O_RDWR); sfd = open(argv[2], O_RDWR);
	int efd = open(argv[3], O_RDWR);
	if (vfd < 0 || sfd < 0 || efd < 0) { perror("open"); return 1; }
	setctrl(efd, V4L2_CID_EXPOSURE, atoi(argv[4]));
	setctrl(efd, V4L2_CID_ANALOGUE_GAIN, atoi(argv[5]));

	struct v4l2_format fmt = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE };
	fmt.fmt.pix_mp.width = W; fmt.fmt.pix_mp.height = H; fmt.fmt.pix_mp.num_planes = 1;
	fmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_SRGGB10P; fmt.fmt.pix_mp.field = V4L2_FIELD_NONE;
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
	int t = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (ioctl(vfd, VIDIOC_STREAMON, &t)) { perror("streamon"); return 1; }

	for (int i = 0; i < 4; i++) qbuf(grab(0));	/* discard start-up frames */
	int sweep = argc > 6, best = 0; double bs = -1;
	int settle = 2;
	if (sweep) {
		for (int p = 256; p <= 1023; p += 64) printf("%4d %.0f\n", p, at(p, settle));
	}
	/* coarse */
	for (int p = 256; p <= 1023; p += 48) { double s = at(p, settle); if (s > bs) { bs = s; best = p; } }
	/* refine around best */
	for (int step = 32; step >= 4; step /= 2) {
		int c = best;
		for (int d = -1; d <= 1; d += 2) {
			int p = c + d * step; if (p < 0 || p > 1023) continue;
			double s = at(p, settle); if (s > bs) { bs = s; best = p; }
		}
	}
	setctrl(sfd, V4L2_CID_FOCUS_ABSOLUTE, best);
	ioctl(vfd, VIDIOC_STREAMOFF, &t);
	printf("BEST %d score %.0f\n", best, bs);
	return 0;
}
