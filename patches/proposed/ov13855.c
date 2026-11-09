// SPDX-License-Identifier: GPL-2.0-only
/*
 * OmniVision OV13855 camera sensor driver (violet / Redmi Note 7 Pro bring-up).
 * Single mode, tables recovered from the vendor CAMX sensor-module data. Skeleton follows imx586.c.
 */
#include <linux/unaligned.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/regulator/consumer.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

#define OV13855_ID_REG		0x300b
#define OV13855_ID		0xd855
#define OV13855_INCLK_RATE	24000000
#define OV13855_LINK_FREQ		360000000
#define OV13855_LANES		4
#define OV13855_WIDTH		2112
#define OV13855_HEIGHT		1568

struct ov13855_reg { u16 address; u8 val; };

static const struct ov13855_reg ov13855_init[] = {
	{ 0x0103, 0x01 },
	{ 0x0300, 0x02 },
	{ 0x0301, 0x00 },
	{ 0x0302, 0x5a },
	{ 0x0303, 0x00 },
	{ 0x0304, 0x00 },
	{ 0x0305, 0x01 },
	{ 0x030b, 0x06 },
	{ 0x030c, 0x02 },
	{ 0x030d, 0x88 },
	{ 0x0312, 0x11 },
	{ 0x3022, 0x01 },
	{ 0x3012, 0x40 },
	{ 0x3013, 0x72 },
	{ 0x3016, 0x72 },
	{ 0x301b, 0xf0 },
	{ 0x301f, 0xd0 },
	{ 0x3106, 0x15 },
	{ 0x3107, 0x23 },
	{ 0x3500, 0x00 },
	{ 0x3501, 0x80 },
	{ 0x3502, 0x00 },
	{ 0x3508, 0x02 },
	{ 0x3509, 0x00 },
	{ 0x350a, 0x00 },
	{ 0x350e, 0x00 },
	{ 0x3510, 0x00 },
	{ 0x3511, 0x02 },
	{ 0x3512, 0x00 },
	{ 0x3600, 0x2b },
	{ 0x3601, 0x52 },
	{ 0x3602, 0x60 },
	{ 0x3612, 0x05 },
	{ 0x3613, 0xa4 },
	{ 0x3620, 0x80 },
	{ 0x3621, 0x10 },
	{ 0x3622, 0x30 },
	{ 0x3624, 0x1c },
	{ 0x3640, 0x10 },
	{ 0x3641, 0x70 },
	{ 0x3660, 0x04 },
	{ 0x3661, 0x80 },
	{ 0x3662, 0x12 },
	{ 0x3664, 0x73 },
	{ 0x3665, 0xa7 },
	{ 0x366e, 0xff },
	{ 0x366f, 0xf4 },
	{ 0x3674, 0x00 },
	{ 0x3679, 0x0c },
	{ 0x367f, 0x01 },
	{ 0x3680, 0x0c },
	{ 0x3681, 0x50 },
	{ 0x3682, 0x50 },
	{ 0x3683, 0xa9 },
	{ 0x3684, 0xa9 },
	{ 0x3706, 0x40 },
	{ 0x3709, 0x5f },
	{ 0x3714, 0x24 },
	{ 0x371a, 0x3e },
	{ 0x3737, 0x04 },
	{ 0x3738, 0xcc },
	{ 0x3739, 0x12 },
	{ 0x373d, 0x26 },
	{ 0x3764, 0x20 },
	{ 0x3765, 0x20 },
	{ 0x37a1, 0x36 },
	{ 0x37a8, 0x3b },
	{ 0x37ab, 0x31 },
	{ 0x37c2, 0x04 },
	{ 0x37c3, 0xf1 },
	{ 0x37c5, 0x00 },
	{ 0x37d8, 0x03 },
	{ 0x37d9, 0x0c },
	{ 0x37da, 0xc2 },
	{ 0x37dc, 0x02 },
	{ 0x37e0, 0x00 },
	{ 0x37e1, 0x0a },
	{ 0x37e2, 0x14 },
	{ 0x37e3, 0x04 },
	{ 0x37e4, 0x2a },
	{ 0x37e5, 0x03 },
	{ 0x37e6, 0x04 },
	{ 0x3800, 0x00 },
	{ 0x3801, 0x00 },
	{ 0x3802, 0x00 },
	{ 0x3803, 0x08 },
	{ 0x3804, 0x10 },
	{ 0x3805, 0x9f },
	{ 0x3806, 0x0c },
	{ 0x3807, 0x57 },
	{ 0x3808, 0x10 },
	{ 0x3809, 0x80 },
	{ 0x380a, 0x0c },
	{ 0x380b, 0x40 },
	{ 0x380c, 0x04 },
	{ 0x380d, 0x62 },
	{ 0x380e, 0x0c },
	{ 0x380f, 0x8e },
	{ 0x3811, 0x10 },
	{ 0x3813, 0x08 },
	{ 0x3814, 0x01 },
	{ 0x3815, 0x01 },
	{ 0x3816, 0x01 },
	{ 0x3817, 0x01 },
	{ 0x3820, 0xa8 },
	{ 0x3821, 0x00 },
	{ 0x3822, 0xc2 },
	{ 0x3823, 0x18 },
	{ 0x3826, 0x11 },
	{ 0x3827, 0x1c },
	{ 0x3829, 0x03 },
	{ 0x3832, 0x00 },
	{ 0x3c80, 0x00 },
	{ 0x3c87, 0x01 },
	{ 0x3c8c, 0x19 },
	{ 0x3c8d, 0x1c },
	{ 0x3c90, 0x00 },
	{ 0x3c91, 0x00 },
	{ 0x3c92, 0x00 },
	{ 0x3c93, 0x00 },
	{ 0x3c94, 0x40 },
	{ 0x3c95, 0x54 },
	{ 0x3c96, 0x34 },
	{ 0x3c97, 0x04 },
	{ 0x3c98, 0x00 },
	{ 0x3d8c, 0x73 },
	{ 0x3d8d, 0xc0 },
	{ 0x3f00, 0x0b },
	{ 0x3f03, 0x00 },
	{ 0x4001, 0xe0 },
	{ 0x4008, 0x00 },
	{ 0x4009, 0x0f },
	{ 0x4011, 0xf0 },
	{ 0x4017, 0x08 },
	{ 0x4050, 0x04 },
	{ 0x4051, 0x0b },
	{ 0x4052, 0x00 },
	{ 0x4053, 0x80 },
	{ 0x4054, 0x00 },
	{ 0x4055, 0x80 },
	{ 0x4056, 0x00 },
	{ 0x4057, 0x80 },
	{ 0x4058, 0x00 },
	{ 0x4059, 0x80 },
	{ 0x405e, 0x00 },
	{ 0x4500, 0x07 },
	{ 0x4503, 0x00 },
	{ 0x450a, 0x04 },
	{ 0x4809, 0x04 },
	{ 0x480c, 0x12 },
	{ 0x481f, 0x30 },
	{ 0x4833, 0x10 },
	{ 0x4837, 0x0e },
	{ 0x4902, 0x01 },
	{ 0x4d00, 0x03 },
	{ 0x4d01, 0xc9 },
	{ 0x4d02, 0xbc },
	{ 0x4d03, 0xd7 },
	{ 0x4d04, 0xf0 },
	{ 0x4d05, 0xa2 },
	{ 0x5000, 0xff },
	{ 0x5001, 0x07 },
	{ 0x5040, 0x39 },
	{ 0x5041, 0x10 },
	{ 0x5042, 0x10 },
	{ 0x5043, 0x84 },
	{ 0x5044, 0x62 },
	{ 0x5180, 0x00 },
	{ 0x5181, 0x10 },
	{ 0x5182, 0x02 },
	{ 0x5183, 0x0f },
	{ 0x5200, 0x1b },
	{ 0x520b, 0x07 },
	{ 0x520c, 0x0f },
	{ 0x5300, 0x04 },
	{ 0x5301, 0x0c },
	{ 0x5302, 0x0c },
	{ 0x5303, 0x0f },
	{ 0x5304, 0x00 },
	{ 0x5305, 0x70 },
	{ 0x5306, 0x00 },
	{ 0x5307, 0x80 },
	{ 0x5308, 0x00 },
	{ 0x5309, 0xa5 },
	{ 0x530a, 0x00 },
	{ 0x530b, 0xd3 },
	{ 0x530c, 0x00 },
	{ 0x530d, 0xf0 },
	{ 0x530e, 0x01 },
	{ 0x530f, 0x10 },
	{ 0x5310, 0x01 },
	{ 0x5311, 0x20 },
	{ 0x5312, 0x01 },
	{ 0x5313, 0x20 },
	{ 0x5314, 0x01 },
	{ 0x5315, 0x20 },
	{ 0x5316, 0x08 },
	{ 0x5317, 0x08 },
	{ 0x5318, 0x10 },
	{ 0x5319, 0x88 },
	{ 0x531a, 0x88 },
	{ 0x531b, 0xa9 },
	{ 0x531c, 0xaa },
	{ 0x531d, 0x0a },
	{ 0x5405, 0x02 },
	{ 0x5406, 0x67 },
	{ 0x5407, 0x01 },
	{ 0x5408, 0x4a },
	{ 0x3640, 0x10 },
	{ 0x3641, 0x50 },
	{ 0x3621, 0x10 },
	{ 0x481f, 0x30 },
};

static const struct ov13855_reg ov13855_mode[] = {
	{ 0x0300, 0x02 },
	{ 0x0301, 0x00 },
	{ 0x0302, 0x5a },
	{ 0x0303, 0x01 },
	{ 0x0304, 0x00 },
	{ 0x0305, 0x01 },
	{ 0x3022, 0x01 },
	{ 0x3013, 0x72 },
	{ 0x3016, 0x72 },
	{ 0x301b, 0xf0 },
	{ 0x301f, 0xd0 },
	{ 0x3106, 0x15 },
	{ 0x3107, 0x23 },
	{ 0x3500, 0x00 },
	{ 0x3501, 0x64 },
	{ 0x3502, 0x00 },
	{ 0x3622, 0x30 },
	{ 0x3624, 0x1c },
	{ 0x3662, 0x10 },
	{ 0x3709, 0x5f },
	{ 0x3714, 0x28 },
	{ 0x3737, 0x08 },
	{ 0x3739, 0x20 },
	{ 0x37a1, 0x36 },
	{ 0x37a8, 0x3b },
	{ 0x37ab, 0x31 },
	{ 0x37c2, 0x14 },
	{ 0x37d9, 0x0c },
	{ 0x37e1, 0x0a },
	{ 0x37e2, 0x14 },
	{ 0x37e3, 0x08 },
	{ 0x37e4, 0x38 },
	{ 0x37e5, 0x03 },
	{ 0x37e6, 0x08 },
	{ 0x3800, 0x00 },
	{ 0x3801, 0x00 },
	{ 0x3802, 0x00 },
	{ 0x3803, 0x08 },
	{ 0x3804, 0x10 },
	{ 0x3805, 0x9f },
	{ 0x3806, 0x0c },
	{ 0x3807, 0x4f },
	{ 0x3808, 0x08 },
	{ 0x3809, 0x40 },
	{ 0x380a, 0x06 },
	{ 0x380b, 0x20 },
	{ 0x380c, 0x04 },
	{ 0x380d, 0x62 },
	{ 0x380e, 0x0c },
	{ 0x380f, 0x8e },
	{ 0x3811, 0x08 },
	{ 0x3812, 0x00 },
	{ 0x3813, 0x02 },
	{ 0x3814, 0x03 },
	{ 0x3815, 0x01 },
	{ 0x3816, 0x03 },
	{ 0x3817, 0x01 },
	{ 0x3820, 0xab },
	{ 0x3821, 0x00 },
	{ 0x3826, 0x04 },
	{ 0x3827, 0x90 },
	{ 0x3829, 0x07 },
	{ 0x3f03, 0x00 },
	{ 0x4009, 0x0d },
	{ 0x4011, 0xf0 },
	{ 0x4050, 0x04 },
	{ 0x4051, 0x0b },
	{ 0x4500, 0x07 },
	{ 0x4837, 0x1c },
	{ 0x4902, 0x01 },
	{ 0x4d00, 0x03 },
	{ 0x4d01, 0xc9 },
	{ 0x4d02, 0xbc },
	{ 0x4d03, 0xd7 },
	{ 0x4d04, 0xf0 },
	{ 0x4d05, 0xa2 },
	{ 0x5000, 0xff },
	{ 0x5041, 0x10 },
	{ 0x5042, 0x10 },
	{ 0x5043, 0x84 },
	{ 0x5044, 0x62 },
	{ 0x5300, 0x04 },
	{ 0x5301, 0x0c },
	{ 0x5302, 0x0c },
	{ 0x5303, 0x0f },
	{ 0x5305, 0x70 },
	{ 0x5307, 0x80 },
	{ 0x5309, 0xa5 },
	{ 0x530b, 0xd3 },
	{ 0x5319, 0x88 },
	{ 0x531a, 0x88 },
	{ 0x531b, 0xa9 },
	{ 0x531c, 0xaa },
	{ 0x531d, 0x0a },
	{ 0x5405, 0x02 },
	{ 0x5406, 0x67 },
	{ 0x5407, 0x01 },
	{ 0x5408, 0x4a },
	{ 0x0300, 0x02 },
	{ 0x0301, 0x00 },
	{ 0x0302, 0x5c },
	{ 0x0307, 0x00 },
	{ 0x030d, 0x88 },
};

static const struct ov13855_reg ov13855_on[] = {
	{ 0x0100, 0x01 },
};

static const struct ov13855_reg ov13855_off[] = {
	{ 0x0100, 0x00 },
};


static int scan = 1;
static int rst_inv;
module_param(rst_inv, int, 0644);
static int post_delay = 20;
module_param(post_delay, int, 0644);
module_param(scan, int, 0644);

static const char * const ov13855_supply_names[] = { "dovdd", "avdd", "dvdd" };

struct ov13855 {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct gpio_desc *reset_gpio;
	struct clk *inclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(ov13855_supply_names)];
	struct v4l2_ctrl_handler ctrl_handler;
	struct v4l2_ctrl *vblank_ctrl;
	struct {
		struct v4l2_ctrl *exp_ctrl;
		struct v4l2_ctrl *again_ctrl;
	};
	u32 vblank;
	struct mutex mutex;
};

static const s64 link_freq[] = { OV13855_LINK_FREQ };

static inline struct ov13855 *to_ov13855(struct v4l2_subdev *sd)
{
	return container_of(sd, struct ov13855, sd);
}

static int ov13855_rd(struct v4l2_subdev *sd, u16 reg, u32 len, u32 *val)
{
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	struct i2c_msg msgs[2] = {0};
	u8 addr_buf[2] = {0};
	u8 data_buf[4] = {0};

	put_unaligned_be16(reg, addr_buf);
	msgs[0].addr = client->addr;
	msgs[0].len = 2;
	msgs[0].buf = addr_buf;
	msgs[1].addr = client->addr;
	msgs[1].flags = I2C_M_RD;
	msgs[1].len = len;
	msgs[1].buf = &data_buf[4 - len];
	if (i2c_transfer(client->adapter, msgs, 2) != 2)
		return -EIO;
	*val = get_unaligned_be32(data_buf);
	return 0;
}

static int ov13855_wr(struct v4l2_subdev *sd, u16 reg, u32 len, u32 val)
{
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	u8 buf[6] = {0};

	put_unaligned_be16(reg, buf);
	put_unaligned_be32(val << (8 * (4 - len)), buf + 2);
	if (i2c_master_send(client, buf, len + 2) != len + 2)
		return -EIO;
	return 0;
}

static int ov13855_wr_list(struct v4l2_subdev *sd, const struct ov13855_reg *r, u32 n)
{
	u32 i;
	int ret;

	for (i = 0; i < n; i++) {
		ret = ov13855_wr(sd, r[i].address, 1, r[i].val);
		if (ret)
			return ret;
	}
	return 0;
}

static int ov13855_update_exp_gain(struct ov13855 *s, u32 exposure, u32 gain)
{
	struct v4l2_subdev *sd = &s->sd;
	u32 lpfr = s->vblank + OV13855_HEIGHT;
	int ret = 0;

	
	ov13855_wr(sd, 0x380e, 2, lpfr);
	ov13855_wr(sd, 0x3500, 1, (exposure >> 12) & 0x0f);
	ov13855_wr(sd, 0x3501, 1, (exposure >> 4) & 0xff);
	ov13855_wr(sd, 0x3502, 1, (exposure << 4) & 0xf0);
	ov13855_wr(sd, 0x3508, 2, gain);

	return ret;
}

static int ov13855_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct ov13855 *s = container_of(ctrl->handler, struct ov13855, ctrl_handler);
	int ret = 0;

	switch (ctrl->id) {
	case V4L2_CID_VBLANK:
		s->vblank = ctrl->val;
		ret = __v4l2_ctrl_modify_range(s->exp_ctrl, 4, s->vblank + OV13855_HEIGHT - 8,
					       1, 800);
		break;
	case V4L2_CID_EXPOSURE:
		if (!pm_runtime_get_if_in_use(s->dev))
			return 0;
		ret = ov13855_update_exp_gain(s, ctrl->val, s->again_ctrl->val);
		pm_runtime_put(s->dev);
		break;
	default:
		break;
	}
	return ret;
}

static const struct v4l2_ctrl_ops ov13855_ctrl_ops = { .s_ctrl = ov13855_set_ctrl };

static int ov13855_enum_mbus_code(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index)
		return -EINVAL;
	code->code = MEDIA_BUS_FMT_SBGGR10_1X10;
	return 0;
}

static int ov13855_enum_frame_size(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				 struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->index || fse->code != MEDIA_BUS_FMT_SBGGR10_1X10)
		return -EINVAL;
	fse->min_width = fse->max_width = OV13855_WIDTH;
	fse->min_height = fse->max_height = OV13855_HEIGHT;
	return 0;
}

static void ov13855_fill_fmt(struct v4l2_mbus_framefmt *f)
{
	f->width = OV13855_WIDTH;
	f->height = OV13855_HEIGHT;
	f->code = MEDIA_BUS_FMT_SBGGR10_1X10;
	f->field = V4L2_FIELD_NONE;
	f->colorspace = V4L2_COLORSPACE_RAW;
	f->ycbcr_enc = V4L2_YCBCR_ENC_DEFAULT;
	f->quantization = V4L2_QUANTIZATION_DEFAULT;
	f->xfer_func = V4L2_XFER_FUNC_NONE;
}

static int ov13855_set_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	ov13855_fill_fmt(&fmt->format);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		*v4l2_subdev_state_get_format(st, fmt->pad) = fmt->format;
	return 0;
}

static int ov13855_get_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(st, fmt->pad);
	else
		ov13855_fill_fmt(&fmt->format);
	return 0;
}

static int ov13855_get_selection(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			       struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = OV13855_WIDTH;
		sel->r.height = OV13855_HEIGHT;
		return 0;
	}
	return -EINVAL;
}

static int ov13855_init_state(struct v4l2_subdev *sd, struct v4l2_subdev_state *st)
{
	ov13855_fill_fmt(v4l2_subdev_state_get_format(st, 0));
	return 0;
}

static int ov13855_start(struct ov13855 *s)
{
	struct v4l2_subdev *sd = &s->sd;
	int ret;

	ret = ov13855_wr_list(sd, ov13855_init, ARRAY_SIZE(ov13855_init));
	if (!ret)
		ret = ov13855_wr_list(sd, ov13855_mode, ARRAY_SIZE(ov13855_mode));
	if (ret)
		return ret;
	ret = __v4l2_ctrl_handler_setup(sd->ctrl_handler);
	if (ret)
		return ret;
	usleep_range(5000, 6000);
	return ov13855_wr_list(sd, ov13855_on, ARRAY_SIZE(ov13855_on));
}

static int ov13855_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct ov13855 *s = to_ov13855(sd);
	int ret = 0;

	mutex_lock(&s->mutex);
	if (enable) {
		ret = pm_runtime_resume_and_get(s->dev);
		if (!ret) {
			ret = ov13855_start(s);
			if (ret)
				pm_runtime_put(s->dev);
		}
	} else {
		ov13855_wr_list(sd, ov13855_off, ARRAY_SIZE(ov13855_off));
		pm_runtime_put(s->dev);
	}
	mutex_unlock(&s->mutex);
	return ret;
}

static int ov13855_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct ov13855 *s = to_ov13855(sd);
	int ret;

	/* same order as the working imx586 recipe: reset asserted, rails, MCLK, release */
	gpiod_set_value_cansleep(s->reset_gpio, rst_inv ? 0 : 1);
	msleep(20);
	ret = regulator_enable(s->supplies[1].consumer);	/* avdd */
	if (ret)
		return ret;
	usleep_range(1000, 2000);
	ret = regulator_enable(s->supplies[0].consumer);	/* dovdd */
	if (ret)
		goto err_avdd;
	usleep_range(1000, 2000);
	ret = regulator_enable(s->supplies[2].consumer);	/* dvdd */
	if (ret)
		goto err_dovdd;
	usleep_range(1000, 2000);
	ret = clk_prepare_enable(s->inclk);
	if (ret)
		goto err_dvdd;
	usleep_range(1000, 2000);
	gpiod_set_value_cansleep(s->reset_gpio, rst_inv ? 1 : 0);
	msleep(post_delay);
	return 0;
err_dvdd:
	regulator_disable(s->supplies[2].consumer);
err_dovdd:
	regulator_disable(s->supplies[0].consumer);
err_avdd:
	regulator_disable(s->supplies[1].consumer);
	return ret;
}

static int ov13855_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct ov13855 *s = to_ov13855(sd);

	clk_disable_unprepare(s->inclk);
	gpiod_set_value_cansleep(s->reset_gpio, 1);
	regulator_disable(s->supplies[2].consumer);
	regulator_disable(s->supplies[0].consumer);
	regulator_disable(s->supplies[1].consumer);
	return 0;
}

static int ov13855_init_controls(struct ov13855 *s)
{
	struct v4l2_ctrl_handler *h = &s->ctrl_handler;
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl *c;
	int ret;

	ret = v4l2_ctrl_handler_init(h, 8);
	if (ret)
		return ret;
	h->lock = &s->mutex;
	s->exp_ctrl = v4l2_ctrl_new_std(h, &ov13855_ctrl_ops, V4L2_CID_EXPOSURE, 4,
					82 + OV13855_HEIGHT - 8, 1, 800);
	s->again_ctrl = v4l2_ctrl_new_std(h, &ov13855_ctrl_ops, V4L2_CID_ANALOGUE_GAIN, 128, 1984, 1, 256);
	v4l2_ctrl_cluster(2, &s->exp_ctrl);
	s->vblank_ctrl = v4l2_ctrl_new_std(h, &ov13855_ctrl_ops, V4L2_CID_VBLANK, 82, 0xfffff, 1, 82);
	v4l2_ctrl_new_std(h, &ov13855_ctrl_ops, V4L2_CID_PIXEL_RATE, 120000000, 120000000, 1, 120000000);
	c = v4l2_ctrl_new_int_menu(h, &ov13855_ctrl_ops, V4L2_CID_LINK_FREQ, 0, 0, link_freq);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	c = v4l2_ctrl_new_std(h, &ov13855_ctrl_ops, V4L2_CID_HBLANK, 0, 0xffff, 1, 500);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	if (!v4l2_fwnode_device_parse(s->dev, &props))
		v4l2_ctrl_new_fwnode_properties(h, &ov13855_ctrl_ops, &props);
	if (h->error) {
		ret = h->error;
		v4l2_ctrl_handler_free(h);
		return ret;
	}
	s->sd.ctrl_handler = h;
	return 0;
}

static int ov13855_parse_hw(struct ov13855 *s)
{
	struct fwnode_handle *ep;
	struct v4l2_fwnode_endpoint bus = { .bus_type = V4L2_MBUS_CSI2_DPHY };
	unsigned int i;
	int ret;

	s->reset_gpio = devm_gpiod_get_optional(s->dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(s->reset_gpio))
		return PTR_ERR(s->reset_gpio);
	s->inclk = devm_v4l2_sensor_clk_get(s->dev, NULL);
	if (IS_ERR(s->inclk))
		return dev_err_probe(s->dev, PTR_ERR(s->inclk), "inclk\n");
	if (clk_get_rate(s->inclk) != OV13855_INCLK_RATE) {
		dev_err(s->dev, "inclk frequency mismatch\n");
		return -EINVAL;
	}
	for (i = 0; i < ARRAY_SIZE(ov13855_supply_names); i++)
		s->supplies[i].supply = ov13855_supply_names[i];
	ret = devm_regulator_bulk_get(s->dev, ARRAY_SIZE(ov13855_supply_names), s->supplies);
	if (ret)
		return ret;
	ep = fwnode_graph_get_next_endpoint(dev_fwnode(s->dev), NULL);
	if (!ep)
		return -ENXIO;
	ret = v4l2_fwnode_endpoint_alloc_parse(ep, &bus);
	fwnode_handle_put(ep);
	if (ret)
		return ret;
	if (bus.bus.mipi_csi2.num_data_lanes != OV13855_LANES) {
		dev_err(s->dev, "lanes %d not supported\n", bus.bus.mipi_csi2.num_data_lanes);
		ret = -EINVAL;
	}
	v4l2_fwnode_endpoint_free(&bus);
	return ret;
}

static const struct v4l2_subdev_video_ops ov13855_video_ops = { .s_stream = ov13855_set_stream };
static const struct v4l2_subdev_pad_ops ov13855_pad_ops = {
	.enum_mbus_code = ov13855_enum_mbus_code,
	.enum_frame_size = ov13855_enum_frame_size,
	.get_fmt = ov13855_get_fmt,
	.set_fmt = ov13855_set_fmt,
	.get_selection = ov13855_get_selection,
};
static const struct v4l2_subdev_ops ov13855_subdev_ops = { .video = &ov13855_video_ops, .pad = &ov13855_pad_ops };
static const struct v4l2_subdev_internal_ops ov13855_internal_ops = { .init_state = ov13855_init_state };

static int ov13855_probe(struct i2c_client *client)
{
	struct ov13855 *s;
	u32 id = 0;
	int ret;

	s = devm_kzalloc(&client->dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = &client->dev;
	v4l2_i2c_subdev_init(&s->sd, client, &ov13855_subdev_ops);
	s->sd.internal_ops = &ov13855_internal_ops;
	ret = ov13855_parse_hw(s);
	if (ret)
		return ret;
	mutex_init(&s->mutex);
	ret = ov13855_power_on(s->dev);
	if (ret)
		goto err_mutex;
	ret = ov13855_rd(&s->sd, OV13855_ID_REG, 2, &id);
	dev_info(s->dev, "chip id read: ret=%d id=0x%04x (expected 0x%04x)\n", ret, id, OV13855_ID);
	if (ret && scan) {
		struct i2c_adapter *ad = client->adapter;
		union i2c_smbus_data d;
		int a;

		for (a = 0x08; a < 0x78; a++)
			if (!i2c_smbus_xfer(ad, a, 0, I2C_SMBUS_READ, 0, I2C_SMBUS_BYTE, &d)) {
				u8 rb[2] = { 0, 0 }, ob[2] = { 0, 0 };
				struct i2c_msg m[2] = {
					{ .addr = a, .len = 2, .buf = rb },
					{ .addr = a, .flags = I2C_M_RD, .len = 2, .buf = ob },
				};
				int r = i2c_transfer(ad, m, 2);

				dev_info(s->dev, "scan: ACK at 0x%02x, reg0000 -> r=%d %02x %02x\n", a, r, ob[0], ob[1]);
			}
	}
	if (ret) {
		ret = -ENXIO;
		goto err_off;
	}
	if (id != OV13855_ID && id != 0 && id != 0xffff)
		dev_warn(s->dev, "unexpected chip id, continuing\n");
	if (id == 0 || id == 0xffff) {
		ret = -ENXIO;
		goto err_off;
	}
	s->vblank = 82;
	ret = ov13855_init_controls(s);
	if (ret)
		goto err_off;
	s->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	v4l2_i2c_subdev_set_name(&s->sd, client, "ov13855", NULL);
	s->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&s->sd.entity, 1, &s->pad);
	if (ret)
		goto err_ctrl;
	ret = v4l2_async_register_subdev_sensor(&s->sd);
	if (ret < 0)
		goto err_ent;
	pm_runtime_set_active(s->dev);
	pm_runtime_enable(s->dev);
	pm_runtime_idle(s->dev);
	return 0;
err_ent:
	media_entity_cleanup(&s->sd.entity);
err_ctrl:
	v4l2_ctrl_handler_free(s->sd.ctrl_handler);
err_off:
	ov13855_power_off(s->dev);
err_mutex:
	mutex_destroy(&s->mutex);
	return ret;
}

static void ov13855_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct ov13855 *s = to_ov13855(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(sd->ctrl_handler);
	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		ov13855_power_off(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	mutex_destroy(&s->mutex);
}

static const struct dev_pm_ops ov13855_pm_ops = { SET_RUNTIME_PM_OPS(ov13855_power_off, ov13855_power_on, NULL) };
static const struct of_device_id ov13855_of_match[] = { { .compatible = "ovti,ov13855" }, { } };
MODULE_DEVICE_TABLE(of, ov13855_of_match);

static struct i2c_driver ov13855_driver = {
	.probe = ov13855_probe,
	.remove = ov13855_remove,
	.driver = { .name = "ov13855", .pm = &ov13855_pm_ops, .of_match_table = ov13855_of_match },
};
module_i2c_driver(ov13855_driver);

MODULE_DESCRIPTION("OmniVision OV13855 sensor driver");
MODULE_LICENSE("GPL");
