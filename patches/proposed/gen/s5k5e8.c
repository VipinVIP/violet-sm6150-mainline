// SPDX-License-Identifier: GPL-2.0-only
/*
 * Samsung S5K5E8 camera sensor driver (violet / Redmi Note 7 Pro bring-up).
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

#define S5K5E8_ID_REG		0x0000
#define S5K5E8_ID		0x5e80
#define S5K5E8_INCLK_RATE	24000000
#define S5K5E8_LINK_FREQ		336000000
#define S5K5E8_LANES		2
#define S5K5E8_WIDTH		1296
#define S5K5E8_HEIGHT		972

struct s5k5e8_reg { u16 address; u8 val; };

static const struct s5k5e8_reg s5k5e8_init[] = {
	{ 0x3906, 0x7e },
	{ 0x3c01, 0x0f },
	{ 0x3c14, 0x00 },
	{ 0x3235, 0x08 },
	{ 0x3063, 0x2e },
	{ 0x307a, 0x10 },
	{ 0x307b, 0x0e },
	{ 0x3079, 0x20 },
	{ 0x3070, 0x05 },
	{ 0x3067, 0x06 },
	{ 0x3071, 0x62 },
	{ 0x3203, 0x43 },
	{ 0x3205, 0x43 },
	{ 0x320b, 0x42 },
	{ 0x3007, 0x00 },
	{ 0x3008, 0x14 },
	{ 0x3020, 0x58 },
	{ 0x300d, 0x34 },
	{ 0x300e, 0x17 },
	{ 0x3021, 0x02 },
	{ 0x3010, 0x59 },
	{ 0x3002, 0x01 },
	{ 0x3005, 0x01 },
	{ 0x3008, 0x04 },
	{ 0x300f, 0x70 },
	{ 0x3010, 0x69 },
	{ 0x3017, 0x10 },
	{ 0x3019, 0x19 },
	{ 0x300c, 0x62 },
	{ 0x3064, 0x10 },
	{ 0x3c08, 0x0e },
	{ 0x3c09, 0x10 },
	{ 0x3c31, 0x0d },
	{ 0x3c32, 0xac },
	{ 0x3929, 0x07 },
};

static const struct s5k5e8_reg s5k5e8_mode[] = {
	{ 0x0136, 0x18 },
	{ 0x0137, 0x00 },
	{ 0x0305, 0x06 },
	{ 0x0306, 0x18 },
	{ 0x0307, 0xa8 },
	{ 0x0308, 0x34 },
	{ 0x0309, 0x42 },
	{ 0x3c1f, 0x00 },
	{ 0x3c17, 0x00 },
	{ 0x3c0b, 0x04 },
	{ 0x3c1c, 0x47 },
	{ 0x3c1d, 0x15 },
	{ 0x3c14, 0x04 },
	{ 0x3c16, 0x00 },
	{ 0x0820, 0x03 },
	{ 0x0821, 0x44 },
	{ 0x0114, 0x01 },
	{ 0x0344, 0x00 },
	{ 0x0345, 0x08 },
	{ 0x0346, 0x00 },
	{ 0x0347, 0x08 },
	{ 0x0348, 0x0a },
	{ 0x0349, 0x27 },
	{ 0x034a, 0x07 },
	{ 0x034b, 0x9f },
	{ 0x034c, 0x05 },
	{ 0x034d, 0x10 },
	{ 0x034e, 0x03 },
	{ 0x034f, 0xcc },
	{ 0x0900, 0x01 },
	{ 0x0901, 0x22 },
	{ 0x0381, 0x01 },
	{ 0x0383, 0x01 },
	{ 0x0385, 0x01 },
	{ 0x0387, 0x03 },
	{ 0x0340, 0x04 },
	{ 0x0341, 0x26 },
	{ 0x0342, 0x14 },
	{ 0x0343, 0x50 },
	{ 0x0200, 0x00 },
	{ 0x0201, 0x00 },
	{ 0x0202, 0x03 },
	{ 0x0203, 0xde },
	{ 0x3303, 0x02 },
	{ 0x3400, 0x00 },
	{ 0x323b, 0x02 },
	{ 0x3301, 0x00 },
	{ 0x3321, 0x04 },
	{ 0x3306, 0x00 },
	{ 0x3307, 0x08 },
	{ 0x3308, 0x0a },
	{ 0x3309, 0x27 },
	{ 0x330a, 0x01 },
	{ 0x330b, 0x01 },
	{ 0x330e, 0x00 },
	{ 0x330f, 0x08 },
	{ 0x3310, 0x07 },
	{ 0x3311, 0x9f },
	{ 0x3312, 0x03 },
	{ 0x3313, 0x01 },
};

static const struct s5k5e8_reg s5k5e8_on[] = {
	{ 0x3c16, 0x00 },
	{ 0x3c0d, 0x00 },
	{ 0x0100, 0x01 },
	{ 0x3c0d, 0x00 },
};

static const struct s5k5e8_reg s5k5e8_off[] = {
	{ 0x0100, 0x00 },
};


static int scan = 1;
static int rst_inv;
module_param(rst_inv, int, 0644);
static int post_delay = 20;
module_param(post_delay, int, 0644);
module_param(scan, int, 0644);

static const char * const s5k5e8_supply_names[] = { "dovdd", "avdd", "dvdd" };

struct s5k5e8 {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct gpio_desc *reset_gpio;
	struct clk *inclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(s5k5e8_supply_names)];
	struct v4l2_ctrl_handler ctrl_handler;
	struct v4l2_ctrl *vblank_ctrl;
	struct {
		struct v4l2_ctrl *exp_ctrl;
		struct v4l2_ctrl *again_ctrl;
	};
	u32 vblank;
	struct mutex mutex;
};

static const s64 link_freq[] = { S5K5E8_LINK_FREQ };

static inline struct s5k5e8 *to_s5k5e8(struct v4l2_subdev *sd)
{
	return container_of(sd, struct s5k5e8, sd);
}

static int s5k5e8_rd(struct v4l2_subdev *sd, u16 reg, u32 len, u32 *val)
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

static int s5k5e8_wr(struct v4l2_subdev *sd, u16 reg, u32 len, u32 val)
{
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	u8 buf[6] = {0};

	put_unaligned_be16(reg, buf);
	put_unaligned_be32(val << (8 * (4 - len)), buf + 2);
	if (i2c_master_send(client, buf, len + 2) != len + 2)
		return -EIO;
	return 0;
}

static int s5k5e8_wr_list(struct v4l2_subdev *sd, const struct s5k5e8_reg *r, u32 n)
{
	u32 i;
	int ret;

	for (i = 0; i < n; i++) {
		ret = s5k5e8_wr(sd, r[i].address, 1, r[i].val);
		if (ret)
			return ret;
	}
	return 0;
}

static int s5k5e8_update_exp_gain(struct s5k5e8 *s, u32 exposure, u32 gain)
{
	struct v4l2_subdev *sd = &s->sd;
	u32 lpfr = s->vblank + S5K5E8_HEIGHT;
	int ret = 0;

	
	ret = s5k5e8_wr(sd, 0x0104, 1, 1);
	if (ret) return ret;
	s5k5e8_wr(sd, 0x0340, 2, lpfr);
	s5k5e8_wr(sd, 0x0202, 2, exposure);
	s5k5e8_wr(sd, 0x0204, 2, gain);
	s5k5e8_wr(sd, 0x0104, 1, 0);

	return ret;
}

static int s5k5e8_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct s5k5e8 *s = container_of(ctrl->handler, struct s5k5e8, ctrl_handler);
	int ret = 0;

	switch (ctrl->id) {
	case V4L2_CID_VBLANK:
		s->vblank = ctrl->val;
		ret = __v4l2_ctrl_modify_range(s->exp_ctrl, 2, s->vblank + S5K5E8_HEIGHT - 4,
					       1, 800);
		break;
	case V4L2_CID_EXPOSURE:
		if (!pm_runtime_get_if_in_use(s->dev))
			return 0;
		ret = s5k5e8_update_exp_gain(s, ctrl->val, s->again_ctrl->val);
		pm_runtime_put(s->dev);
		break;
	default:
		break;
	}
	return ret;
}

static const struct v4l2_ctrl_ops s5k5e8_ctrl_ops = { .s_ctrl = s5k5e8_set_ctrl };

static int s5k5e8_enum_mbus_code(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index)
		return -EINVAL;
	code->code = MEDIA_BUS_FMT_SGRBG10_1X10;
	return 0;
}

static int s5k5e8_enum_frame_size(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				 struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->index || fse->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;
	fse->min_width = fse->max_width = S5K5E8_WIDTH;
	fse->min_height = fse->max_height = S5K5E8_HEIGHT;
	return 0;
}

static void s5k5e8_fill_fmt(struct v4l2_mbus_framefmt *f)
{
	f->width = S5K5E8_WIDTH;
	f->height = S5K5E8_HEIGHT;
	f->code = MEDIA_BUS_FMT_SGRBG10_1X10;
	f->field = V4L2_FIELD_NONE;
	f->colorspace = V4L2_COLORSPACE_RAW;
	f->ycbcr_enc = V4L2_YCBCR_ENC_DEFAULT;
	f->quantization = V4L2_QUANTIZATION_DEFAULT;
	f->xfer_func = V4L2_XFER_FUNC_NONE;
}

static int s5k5e8_set_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	s5k5e8_fill_fmt(&fmt->format);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		*v4l2_subdev_state_get_format(st, fmt->pad) = fmt->format;
	return 0;
}

static int s5k5e8_get_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(st, fmt->pad);
	else
		s5k5e8_fill_fmt(&fmt->format);
	return 0;
}

static int s5k5e8_get_selection(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			       struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = S5K5E8_WIDTH;
		sel->r.height = S5K5E8_HEIGHT;
		return 0;
	}
	return -EINVAL;
}

static int s5k5e8_init_state(struct v4l2_subdev *sd, struct v4l2_subdev_state *st)
{
	s5k5e8_fill_fmt(v4l2_subdev_state_get_format(st, 0));
	return 0;
}

static int s5k5e8_start(struct s5k5e8 *s)
{
	struct v4l2_subdev *sd = &s->sd;
	int ret;

	ret = s5k5e8_wr_list(sd, s5k5e8_init, ARRAY_SIZE(s5k5e8_init));
	if (!ret)
		ret = s5k5e8_wr_list(sd, s5k5e8_mode, ARRAY_SIZE(s5k5e8_mode));
	if (ret)
		return ret;
	ret = __v4l2_ctrl_handler_setup(sd->ctrl_handler);
	if (ret)
		return ret;
	usleep_range(5000, 6000);
	return s5k5e8_wr_list(sd, s5k5e8_on, ARRAY_SIZE(s5k5e8_on));
}

static int s5k5e8_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct s5k5e8 *s = to_s5k5e8(sd);
	int ret = 0;

	mutex_lock(&s->mutex);
	if (enable) {
		ret = pm_runtime_resume_and_get(s->dev);
		if (!ret) {
			ret = s5k5e8_start(s);
			if (ret)
				pm_runtime_put(s->dev);
		}
	} else {
		s5k5e8_wr_list(sd, s5k5e8_off, ARRAY_SIZE(s5k5e8_off));
		pm_runtime_put(s->dev);
	}
	mutex_unlock(&s->mutex);
	return ret;
}

static int s5k5e8_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct s5k5e8 *s = to_s5k5e8(sd);
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

static int s5k5e8_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct s5k5e8 *s = to_s5k5e8(sd);

	clk_disable_unprepare(s->inclk);
	gpiod_set_value_cansleep(s->reset_gpio, 1);
	regulator_disable(s->supplies[2].consumer);
	regulator_disable(s->supplies[0].consumer);
	regulator_disable(s->supplies[1].consumer);
	return 0;
}

static int s5k5e8_init_controls(struct s5k5e8 *s)
{
	struct v4l2_ctrl_handler *h = &s->ctrl_handler;
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl *c;
	int ret;

	ret = v4l2_ctrl_handler_init(h, 8);
	if (ret)
		return ret;
	h->lock = &s->mutex;
	s->exp_ctrl = v4l2_ctrl_new_std(h, &s5k5e8_ctrl_ops, V4L2_CID_EXPOSURE, 2,
					90 + S5K5E8_HEIGHT - 4, 1, 800);
	s->again_ctrl = v4l2_ctrl_new_std(h, &s5k5e8_ctrl_ops, V4L2_CID_ANALOGUE_GAIN, 32, 512, 1, 64);
	v4l2_ctrl_cluster(2, &s->exp_ctrl);
	s->vblank_ctrl = v4l2_ctrl_new_std(h, &s5k5e8_ctrl_ops, V4L2_CID_VBLANK, 90, 0xfffff, 1, 90);
	v4l2_ctrl_new_std(h, &s5k5e8_ctrl_ops, V4L2_CID_PIXEL_RATE, 60000000, 60000000, 1, 60000000);
	c = v4l2_ctrl_new_int_menu(h, &s5k5e8_ctrl_ops, V4L2_CID_LINK_FREQ, 0, 0, link_freq);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	c = v4l2_ctrl_new_std(h, &s5k5e8_ctrl_ops, V4L2_CID_HBLANK, 0, 0xffff, 1, 2000);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	if (!v4l2_fwnode_device_parse(s->dev, &props))
		v4l2_ctrl_new_fwnode_properties(h, &s5k5e8_ctrl_ops, &props);
	if (h->error) {
		ret = h->error;
		v4l2_ctrl_handler_free(h);
		return ret;
	}
	s->sd.ctrl_handler = h;
	return 0;
}

static int s5k5e8_parse_hw(struct s5k5e8 *s)
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
	if (clk_get_rate(s->inclk) != S5K5E8_INCLK_RATE) {
		dev_err(s->dev, "inclk frequency mismatch\n");
		return -EINVAL;
	}
	for (i = 0; i < ARRAY_SIZE(s5k5e8_supply_names); i++)
		s->supplies[i].supply = s5k5e8_supply_names[i];
	ret = devm_regulator_bulk_get(s->dev, ARRAY_SIZE(s5k5e8_supply_names), s->supplies);
	if (ret)
		return ret;
	ep = fwnode_graph_get_next_endpoint(dev_fwnode(s->dev), NULL);
	if (!ep)
		return -ENXIO;
	ret = v4l2_fwnode_endpoint_alloc_parse(ep, &bus);
	fwnode_handle_put(ep);
	if (ret)
		return ret;
	if (bus.bus.mipi_csi2.num_data_lanes != S5K5E8_LANES) {
		dev_err(s->dev, "lanes %d not supported\n", bus.bus.mipi_csi2.num_data_lanes);
		ret = -EINVAL;
	}
	v4l2_fwnode_endpoint_free(&bus);
	return ret;
}

static const struct v4l2_subdev_video_ops s5k5e8_video_ops = { .s_stream = s5k5e8_set_stream };
static const struct v4l2_subdev_pad_ops s5k5e8_pad_ops = {
	.enum_mbus_code = s5k5e8_enum_mbus_code,
	.enum_frame_size = s5k5e8_enum_frame_size,
	.get_fmt = s5k5e8_get_fmt,
	.set_fmt = s5k5e8_set_fmt,
	.get_selection = s5k5e8_get_selection,
};
static const struct v4l2_subdev_ops s5k5e8_subdev_ops = { .video = &s5k5e8_video_ops, .pad = &s5k5e8_pad_ops };
static const struct v4l2_subdev_internal_ops s5k5e8_internal_ops = { .init_state = s5k5e8_init_state };

static int s5k5e8_probe(struct i2c_client *client)
{
	struct s5k5e8 *s;
	u32 id = 0;
	int ret;

	s = devm_kzalloc(&client->dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = &client->dev;
	v4l2_i2c_subdev_init(&s->sd, client, &s5k5e8_subdev_ops);
	s->sd.internal_ops = &s5k5e8_internal_ops;
	ret = s5k5e8_parse_hw(s);
	if (ret)
		return ret;
	mutex_init(&s->mutex);
	ret = s5k5e8_power_on(s->dev);
	if (ret)
		goto err_mutex;
	ret = s5k5e8_rd(&s->sd, S5K5E8_ID_REG, 2, &id);
	dev_info(s->dev, "chip id read: ret=%d id=0x%04x (expected 0x%04x)\n", ret, id, S5K5E8_ID);
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
	if (id != S5K5E8_ID && id != 0 && id != 0xffff)
		dev_warn(s->dev, "unexpected chip id, continuing\n");
	if (id == 0 || id == 0xffff) {
		ret = -ENXIO;
		goto err_off;
	}
	s->vblank = 90;
	ret = s5k5e8_init_controls(s);
	if (ret)
		goto err_off;
	s->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	v4l2_i2c_subdev_set_name(&s->sd, client, "s5k5e8", NULL);
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
	s5k5e8_power_off(s->dev);
err_mutex:
	mutex_destroy(&s->mutex);
	return ret;
}

static void s5k5e8_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct s5k5e8 *s = to_s5k5e8(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(sd->ctrl_handler);
	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		s5k5e8_power_off(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	mutex_destroy(&s->mutex);
}

static const struct dev_pm_ops s5k5e8_pm_ops = { SET_RUNTIME_PM_OPS(s5k5e8_power_off, s5k5e8_power_on, NULL) };
static const struct of_device_id s5k5e8_of_match[] = { { .compatible = "samsung,s5k5e8" }, { } };
MODULE_DEVICE_TABLE(of, s5k5e8_of_match);

static struct i2c_driver s5k5e8_driver = {
	.probe = s5k5e8_probe,
	.remove = s5k5e8_remove,
	.driver = { .name = "s5k5e8", .pm = &s5k5e8_pm_ops, .of_match_table = s5k5e8_of_match },
};
module_i2c_driver(s5k5e8_driver);

MODULE_DESCRIPTION("Samsung S5K5E8 sensor driver");
MODULE_LICENSE("GPL");
