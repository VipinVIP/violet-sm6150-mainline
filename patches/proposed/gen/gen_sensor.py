#!/usr/bin/env python3
"""Generate a minimal single-mode V4L2 sensor driver (same skeleton as imx586.c) from a config.
usage: gen_sensor.py <s5k5e8|ov13855> <out.c>   (tables come from ~/violet-ios/cam2/*.json, see docs/PROGRESS.md)"""
import json, sys, os

CFG = {
 's5k5e8': dict(
    json='com.qti.sensormodule.ofilm_s5k5e8.bin.json', name='s5k5e8', compat='samsung,s5k5e8', desc='Samsung S5K5E8',
    lanes=2, link=336000000, width=1296, height=972, code='MEDIA_BUS_FMT_SGRBG10_1X10',
    idreg=0x0000, idlen=2, idval=0x5e80, hblank=2000, vblank=1062-972, vmax=0xffff,
    exp_min=2, exp_off=4, exp_def=800, gain_min=32, gain_max=512, gain_def=64, pclk=60000000,
    init_idx=[7], mode_idx=1, stream_on=[(0x3c16,0),(0x3c0d,0),(0x0100,1),(0x3c0d,0)], stream_off=[(0x0100,0)],
    exp_gain='''
	ret = s5k_write(sd, 0x0104, 1, 1);
	if (ret) return ret;
	s5k_write(sd, 0x0340, 2, lpfr);
	s5k_write(sd, 0x0202, 2, exposure);
	s5k_write(sd, 0x0204, 2, gain);
	s5k_write(sd, 0x0104, 1, 0);
'''),
 'ov13855': dict(
    json='com.qti.sensormodule.ofilm_ov13855.bin.json', name='ov13855', compat='ovti,ov13855', desc='OmniVision OV13855',
    lanes=4, link=360000000, width=2112, height=1568, code='MEDIA_BUS_FMT_SBGGR10_1X10',
    idreg=0x300b, idlen=2, idval=0xd855, hblank=500, vblank=1650-1568, vmax=0xffff,
    exp_min=4, exp_off=8, exp_def=800, gain_min=128, gain_max=1984, gain_def=256, pclk=120000000,
    init_idx=[3], mode_idx=1, stream_on=[(0x0100,1)], stream_off=[(0x0100,0)],
    exp_gain='''
	s5k_write(sd, 0x380e, 2, lpfr);
	s5k_write(sd, 0x3500, 1, (exposure >> 12) & 0x0f);
	s5k_write(sd, 0x3501, 1, (exposure >> 4) & 0xff);
	s5k_write(sd, 0x3502, 1, (exposure << 4) & 0xf0);
	s5k_write(sd, 0x3508, 2, gain);
'''),
}

def main():
    key, out = sys.argv[1], sys.argv[2]
    c = CFG[key]
    runs = json.load(open(os.path.expanduser('~/violet-ios/cam2/' + c['json'])))
    def tab(r): return list(zip(r['regs'], r['vals']))
    init = []
    for i in c['init_idx']: init += tab(runs[i])
    mode = tab(runs[c['mode_idx']])
    N = c['name']; U = N.upper()
    def arr(nm, lst):
        return 'static const struct %s_reg %s[] = {\n%s};\n' % (N, nm, ''.join('\t{ 0x%04x, 0x%02x },\n' % (a, b) for a, b in lst))
    src = TEMPLATE
    rep = dict(N=N, U=U, DESC=c['desc'], COMPAT=c['compat'], LANES=c['lanes'], LINK=c['link'], W=c['width'], H=c['height'],
               CODE=c['code'], IDREG='0x%04x' % c['idreg'], IDLEN=c['idlen'], IDVAL='0x%04x' % c['idval'], HBLANK=c['hblank'],
               VBLANK=c['vblank'], EXPMIN=c['exp_min'], EXPOFF=c['exp_off'], EXPDEF=c['exp_def'], GMIN=c['gain_min'], GMAX=c['gain_max'],
               GDEF=c['gain_def'], PCLK=c['pclk'], INIT=arr('%s_init' % N, init), MODE=arr('%s_mode' % N, mode),
               ON=arr('%s_on' % N, c['stream_on']), OFF=arr('%s_off' % N, c['stream_off']), EXPGAIN=c['exp_gain'])
    for k, v in rep.items():
        src = src.replace('@@%s@@' % k, str(v))
    src = src.replace('s5k_write', '%s_wr' % N).replace('s5k_read', '%s_rd' % N)
    open(out, 'w').write(src)

TEMPLATE = r'''// SPDX-License-Identifier: GPL-2.0-only
/*
 * @@DESC@@ camera sensor driver (violet / Redmi Note 7 Pro bring-up).
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

#define @@U@@_ID_REG		@@IDREG@@
#define @@U@@_ID		@@IDVAL@@
#define @@U@@_INCLK_RATE	24000000
#define @@U@@_LINK_FREQ		@@LINK@@
#define @@U@@_LANES		@@LANES@@
#define @@U@@_WIDTH		@@W@@
#define @@U@@_HEIGHT		@@H@@

struct @@N@@_reg { u16 address; u8 val; };

@@INIT@@
@@MODE@@
@@ON@@
@@OFF@@

static int scan = 1;
static int rst_inv;
module_param(rst_inv, int, 0644);
static int post_delay = 20;
module_param(post_delay, int, 0644);
module_param(scan, int, 0644);

static const char * const @@N@@_supply_names[] = { "dovdd", "avdd", "dvdd" };

struct @@N@@ {
	struct device *dev;
	struct v4l2_subdev sd;
	struct media_pad pad;
	struct gpio_desc *reset_gpio;
	struct clk *inclk;
	struct regulator_bulk_data supplies[ARRAY_SIZE(@@N@@_supply_names)];
	struct v4l2_ctrl_handler ctrl_handler;
	struct v4l2_ctrl *vblank_ctrl;
	struct {
		struct v4l2_ctrl *exp_ctrl;
		struct v4l2_ctrl *again_ctrl;
	};
	u32 vblank;
	struct mutex mutex;
};

static const s64 link_freq[] = { @@U@@_LINK_FREQ };

static inline struct @@N@@ *to_@@N@@(struct v4l2_subdev *sd)
{
	return container_of(sd, struct @@N@@, sd);
}

static int @@N@@_rd(struct v4l2_subdev *sd, u16 reg, u32 len, u32 *val)
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

static int @@N@@_wr(struct v4l2_subdev *sd, u16 reg, u32 len, u32 val)
{
	struct i2c_client *client = v4l2_get_subdevdata(sd);
	u8 buf[6] = {0};

	put_unaligned_be16(reg, buf);
	put_unaligned_be32(val << (8 * (4 - len)), buf + 2);
	if (i2c_master_send(client, buf, len + 2) != len + 2)
		return -EIO;
	return 0;
}

static int @@N@@_wr_list(struct v4l2_subdev *sd, const struct @@N@@_reg *r, u32 n)
{
	u32 i;
	int ret;

	for (i = 0; i < n; i++) {
		ret = @@N@@_wr(sd, r[i].address, 1, r[i].val);
		if (ret)
			return ret;
	}
	return 0;
}

static int @@N@@_update_exp_gain(struct @@N@@ *s, u32 exposure, u32 gain)
{
	struct v4l2_subdev *sd = &s->sd;
	u32 lpfr = s->vblank + @@U@@_HEIGHT;
	int ret = 0;

	@@EXPGAIN@@
	return ret;
}

static int @@N@@_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct @@N@@ *s = container_of(ctrl->handler, struct @@N@@, ctrl_handler);
	int ret = 0;

	switch (ctrl->id) {
	case V4L2_CID_VBLANK:
		s->vblank = ctrl->val;
		ret = __v4l2_ctrl_modify_range(s->exp_ctrl, @@EXPMIN@@, s->vblank + @@U@@_HEIGHT - @@EXPOFF@@,
					       1, @@EXPDEF@@);
		break;
	case V4L2_CID_EXPOSURE:
		if (!pm_runtime_get_if_in_use(s->dev))
			return 0;
		ret = @@N@@_update_exp_gain(s, ctrl->val, s->again_ctrl->val);
		pm_runtime_put(s->dev);
		break;
	default:
		break;
	}
	return ret;
}

static const struct v4l2_ctrl_ops @@N@@_ctrl_ops = { .s_ctrl = @@N@@_set_ctrl };

static int @@N@@_enum_mbus_code(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				struct v4l2_subdev_mbus_code_enum *code)
{
	if (code->index)
		return -EINVAL;
	code->code = @@CODE@@;
	return 0;
}

static int @@N@@_enum_frame_size(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
				 struct v4l2_subdev_frame_size_enum *fse)
{
	if (fse->index || fse->code != @@CODE@@)
		return -EINVAL;
	fse->min_width = fse->max_width = @@U@@_WIDTH;
	fse->min_height = fse->max_height = @@U@@_HEIGHT;
	return 0;
}

static void @@N@@_fill_fmt(struct v4l2_mbus_framefmt *f)
{
	f->width = @@U@@_WIDTH;
	f->height = @@U@@_HEIGHT;
	f->code = @@CODE@@;
	f->field = V4L2_FIELD_NONE;
	f->colorspace = V4L2_COLORSPACE_RAW;
	f->ycbcr_enc = V4L2_YCBCR_ENC_DEFAULT;
	f->quantization = V4L2_QUANTIZATION_DEFAULT;
	f->xfer_func = V4L2_XFER_FUNC_NONE;
}

static int @@N@@_set_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	@@N@@_fill_fmt(&fmt->format);
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		*v4l2_subdev_state_get_format(st, fmt->pad) = fmt->format;
	return 0;
}

static int @@N@@_get_fmt(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			 struct v4l2_subdev_format *fmt)
{
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(st, fmt->pad);
	else
		@@N@@_fill_fmt(&fmt->format);
	return 0;
}

static int @@N@@_get_selection(struct v4l2_subdev *sd, struct v4l2_subdev_state *st,
			       struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP:
	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.left = 0;
		sel->r.top = 0;
		sel->r.width = @@U@@_WIDTH;
		sel->r.height = @@U@@_HEIGHT;
		return 0;
	}
	return -EINVAL;
}

static int @@N@@_init_state(struct v4l2_subdev *sd, struct v4l2_subdev_state *st)
{
	@@N@@_fill_fmt(v4l2_subdev_state_get_format(st, 0));
	return 0;
}

static int @@N@@_start(struct @@N@@ *s)
{
	struct v4l2_subdev *sd = &s->sd;
	int ret;

	ret = @@N@@_wr_list(sd, @@N@@_init, ARRAY_SIZE(@@N@@_init));
	if (!ret)
		ret = @@N@@_wr_list(sd, @@N@@_mode, ARRAY_SIZE(@@N@@_mode));
	if (ret)
		return ret;
	ret = __v4l2_ctrl_handler_setup(sd->ctrl_handler);
	if (ret)
		return ret;
	usleep_range(5000, 6000);
	return @@N@@_wr_list(sd, @@N@@_on, ARRAY_SIZE(@@N@@_on));
}

static int @@N@@_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct @@N@@ *s = to_@@N@@(sd);
	int ret = 0;

	mutex_lock(&s->mutex);
	if (enable) {
		ret = pm_runtime_resume_and_get(s->dev);
		if (!ret) {
			ret = @@N@@_start(s);
			if (ret)
				pm_runtime_put(s->dev);
		}
	} else {
		@@N@@_wr_list(sd, @@N@@_off, ARRAY_SIZE(@@N@@_off));
		pm_runtime_put(s->dev);
	}
	mutex_unlock(&s->mutex);
	return ret;
}

static int @@N@@_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct @@N@@ *s = to_@@N@@(sd);
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

static int @@N@@_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct @@N@@ *s = to_@@N@@(sd);

	clk_disable_unprepare(s->inclk);
	gpiod_set_value_cansleep(s->reset_gpio, 1);
	regulator_disable(s->supplies[2].consumer);
	regulator_disable(s->supplies[0].consumer);
	regulator_disable(s->supplies[1].consumer);
	return 0;
}

static int @@N@@_init_controls(struct @@N@@ *s)
{
	struct v4l2_ctrl_handler *h = &s->ctrl_handler;
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl *c;
	int ret;

	ret = v4l2_ctrl_handler_init(h, 8);
	if (ret)
		return ret;
	h->lock = &s->mutex;
	s->exp_ctrl = v4l2_ctrl_new_std(h, &@@N@@_ctrl_ops, V4L2_CID_EXPOSURE, @@EXPMIN@@,
					@@VBLANK@@ + @@U@@_HEIGHT - @@EXPOFF@@, 1, @@EXPDEF@@);
	s->again_ctrl = v4l2_ctrl_new_std(h, &@@N@@_ctrl_ops, V4L2_CID_ANALOGUE_GAIN, @@GMIN@@, @@GMAX@@, 1, @@GDEF@@);
	v4l2_ctrl_cluster(2, &s->exp_ctrl);
	s->vblank_ctrl = v4l2_ctrl_new_std(h, &@@N@@_ctrl_ops, V4L2_CID_VBLANK, @@VBLANK@@, 0xfffff, 1, @@VBLANK@@);
	v4l2_ctrl_new_std(h, &@@N@@_ctrl_ops, V4L2_CID_PIXEL_RATE, @@PCLK@@, @@PCLK@@, 1, @@PCLK@@);
	c = v4l2_ctrl_new_int_menu(h, &@@N@@_ctrl_ops, V4L2_CID_LINK_FREQ, 0, 0, link_freq);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	c = v4l2_ctrl_new_std(h, &@@N@@_ctrl_ops, V4L2_CID_HBLANK, 0, 0xffff, 1, @@HBLANK@@);
	if (c)
		c->flags |= V4L2_CTRL_FLAG_READ_ONLY;
	if (!v4l2_fwnode_device_parse(s->dev, &props))
		v4l2_ctrl_new_fwnode_properties(h, &@@N@@_ctrl_ops, &props);
	if (h->error) {
		ret = h->error;
		v4l2_ctrl_handler_free(h);
		return ret;
	}
	s->sd.ctrl_handler = h;
	return 0;
}

static int @@N@@_parse_hw(struct @@N@@ *s)
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
	if (clk_get_rate(s->inclk) != @@U@@_INCLK_RATE) {
		dev_err(s->dev, "inclk frequency mismatch\n");
		return -EINVAL;
	}
	for (i = 0; i < ARRAY_SIZE(@@N@@_supply_names); i++)
		s->supplies[i].supply = @@N@@_supply_names[i];
	ret = devm_regulator_bulk_get(s->dev, ARRAY_SIZE(@@N@@_supply_names), s->supplies);
	if (ret)
		return ret;
	ep = fwnode_graph_get_next_endpoint(dev_fwnode(s->dev), NULL);
	if (!ep)
		return -ENXIO;
	ret = v4l2_fwnode_endpoint_alloc_parse(ep, &bus);
	fwnode_handle_put(ep);
	if (ret)
		return ret;
	if (bus.bus.mipi_csi2.num_data_lanes != @@U@@_LANES) {
		dev_err(s->dev, "lanes %d not supported\n", bus.bus.mipi_csi2.num_data_lanes);
		ret = -EINVAL;
	}
	v4l2_fwnode_endpoint_free(&bus);
	return ret;
}

static const struct v4l2_subdev_video_ops @@N@@_video_ops = { .s_stream = @@N@@_set_stream };
static const struct v4l2_subdev_pad_ops @@N@@_pad_ops = {
	.enum_mbus_code = @@N@@_enum_mbus_code,
	.enum_frame_size = @@N@@_enum_frame_size,
	.get_fmt = @@N@@_get_fmt,
	.set_fmt = @@N@@_set_fmt,
	.get_selection = @@N@@_get_selection,
};
static const struct v4l2_subdev_ops @@N@@_subdev_ops = { .video = &@@N@@_video_ops, .pad = &@@N@@_pad_ops };
static const struct v4l2_subdev_internal_ops @@N@@_internal_ops = { .init_state = @@N@@_init_state };

static int @@N@@_probe(struct i2c_client *client)
{
	struct @@N@@ *s;
	u32 id = 0;
	int ret;

	s = devm_kzalloc(&client->dev, sizeof(*s), GFP_KERNEL);
	if (!s)
		return -ENOMEM;
	s->dev = &client->dev;
	v4l2_i2c_subdev_init(&s->sd, client, &@@N@@_subdev_ops);
	s->sd.internal_ops = &@@N@@_internal_ops;
	ret = @@N@@_parse_hw(s);
	if (ret)
		return ret;
	mutex_init(&s->mutex);
	ret = @@N@@_power_on(s->dev);
	if (ret)
		goto err_mutex;
	ret = @@N@@_rd(&s->sd, @@U@@_ID_REG, @@IDLEN@@, &id);
	dev_info(s->dev, "chip id read: ret=%d id=0x%04x (expected 0x%04x)\n", ret, id, @@U@@_ID);
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
	if (id != @@U@@_ID && id != 0 && id != 0xffff)
		dev_warn(s->dev, "unexpected chip id, continuing\n");
	if (id == 0 || id == 0xffff) {
		ret = -ENXIO;
		goto err_off;
	}
	s->vblank = @@VBLANK@@;
	ret = @@N@@_init_controls(s);
	if (ret)
		goto err_off;
	s->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	s->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;
	v4l2_i2c_subdev_set_name(&s->sd, client, "@@N@@", NULL);
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
	@@N@@_power_off(s->dev);
err_mutex:
	mutex_destroy(&s->mutex);
	return ret;
}

static void @@N@@_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct @@N@@ *s = to_@@N@@(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(sd->ctrl_handler);
	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		@@N@@_power_off(&client->dev);
	pm_runtime_set_suspended(&client->dev);
	mutex_destroy(&s->mutex);
}

static const struct dev_pm_ops @@N@@_pm_ops = { SET_RUNTIME_PM_OPS(@@N@@_power_off, @@N@@_power_on, NULL) };
static const struct of_device_id @@N@@_of_match[] = { { .compatible = "@@COMPAT@@" }, { } };
MODULE_DEVICE_TABLE(of, @@N@@_of_match);

static struct i2c_driver @@N@@_driver = {
	.probe = @@N@@_probe,
	.remove = @@N@@_remove,
	.driver = { .name = "@@N@@", .pm = &@@N@@_pm_ops, .of_match_table = @@N@@_of_match },
};
module_i2c_driver(@@N@@_driver);

MODULE_DESCRIPTION("@@DESC@@ sensor driver");
MODULE_LICENSE("GPL");
'''
main()
