// SPDX-License-Identifier: GPL-2.0
/*
 * Redmi Note 7 Pro (violet) battery gauge ("QG-lite").
 *
 * Mainline has no driver for the pm6150 QPNP QG fuel gauge or the SMB5
 * charger.  The QG hardware still measures pack voltage and current on its own,
 * so this driver reads those samples straight from the PMIC and does the
 * state-of-charge bookkeeping itself:
 *
 *  - current: QG_LAST_BURST_AVG_I (signed, 152.588 uA/LSB on the 5 A part),
 *    voltage: QG_LAST_ADC_V (194.637 uV/LSB), same formulas as the downstream
 *    qpnp-qg driver;
 *  - SoC is coulomb-counted from the current, starting from the last value the
 *    downstream driver left in its SDAM (so a r10 -> mainline hop continues
 *    seamlessly) or, when that is not trustworthy, from the IR-compensated
 *    open-circuit voltage and the vendor battery profile's 25C OCV table;
 *  - while the pack rests (|I| small) the SoC is pulled towards the OCV value,
 *    and it is pinned to 100 % when the charger reports termination;
 *  - the SoC is written back to the SDAM so it survives a reboot.
 */
#include <linux/delay.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/power_supply.h>
#include <linux/regmap.h>
#include <linux/workqueue.h>
#include <linux/ktime.h>

#define QG_BASE			0x4800
#define QG_SUBTYPE		(QG_BASE + 0x05)
#define QG_STATUS1		(QG_BASE + 0x08)
#define QG_DATA_CTL2		(QG_BASE + 0x42)
#define  BURST_AVG_HOLD	BIT(0)
#define QG_LAST_ADC_V		(QG_BASE + 0xc0)
#define QG_LAST_BURST_AVG_I	(QG_BASE + 0xc6)
#define QG_ADC_IBAT_5A		0x3

#define SDAM_BASE		0xb600
#define SDAM_VALID		(SDAM_BASE + 0x46)
#define SDAM_SOC		(SDAM_BASE + 0x47)
#define SDAM_RBAT		(SDAM_BASE + 0x4a)	/* u16 mOhm */

#define SMB5_CHGR_STATUS1	0x1006	/* [2:0] charge state, 5 = terminate */
#define SMB5_USBIN_RT_STS	0x1310	/* bit 4 USBIN plugged */

#define FCC_UAH			3580000	/* vendor profile, 25C */
#define POLL_MS			5000
#define REST_UA			80000	/* |I| below this counts as resting */
#define REST_SECS		120

/* mV*10 -> percent, vendor Alium 3600 mAh profile, 25C, descending */
static const struct { u16 pct; u16 v; } ocv[] = {
	{100, 43365}, {98, 43147}, {96, 42920}, {94, 42693}, {92, 42469}, {90, 42248},
	{88, 42032}, {86, 41820}, {84, 41607}, {82, 41393}, {80, 41206}, {78, 41063},
	{76, 40918}, {74, 40680}, {72, 40325}, {70, 40039}, {68, 39894}, {66, 39779},
	{64, 39646}, {62, 39487}, {60, 39306}, {58, 39096}, {56, 38900}, {54, 38767},
	{52, 38671}, {50, 38581}, {48, 38490}, {46, 38403}, {44, 38327}, {42, 38257},
	{40, 38195}, {38, 38142}, {36, 38095}, {34, 38052}, {32, 38015}, {30, 37976},
	{28, 37935}, {26, 37890}, {24, 37823}, {22, 37727}, {20, 37617}, {18, 37494},
	{16, 37361}, {14, 37221}, {12, 37120}, {10, 37057}, {8, 37018}, {6, 36855},
	{5, 36510}, {4, 36056}, {3, 35476}, {2, 34685}, {1, 33450}, {0, 30000},
};

struct violet_batt {
	struct device *dev;
	struct regmap *map;
	struct power_supply *psy;
	struct delayed_work work;
	bool five_amp;
	int rbat_mohm;
	int vbat_uv, ibat_ua;		/* ibat: >0 discharging */
	s64 charge_uah;			/* remaining charge */
	int soc;			/* percent, 0..100 */
	int sdam_soc;
	bool plugged, term;
	ktime_t last, rest_since;
	bool resting;
};

/* returns percent * 100 */
static int ocv_to_soc_x100(int uv)
{
	int v = uv / 100, i;

	if (v >= ocv[0].v)
		return 10000;
	for (i = 1; i < ARRAY_SIZE(ocv); i++) {
		if (v >= ocv[i].v) {
			int span = ocv[i - 1].v - ocv[i].v;
			int dp = (ocv[i - 1].pct - ocv[i].pct) * 100;

			return ocv[i].pct * 100 + (v - ocv[i].v) * dp / span;
		}
	}
	return 0;
}

static int violet_batt_sample(struct violet_batt *b)
{
	unsigned int lo, hi, raw;
	u8 buf[2];
	int ret;

	ret = regmap_bulk_read(b->map, QG_LAST_ADC_V, buf, 2);
	if (ret)
		return ret;
	raw = buf[0] | (buf[1] << 8);
	b->vbat_uv = raw * 194637ULL / 1000;

	regmap_update_bits(b->map, QG_DATA_CTL2, BURST_AVG_HOLD, BURST_AVG_HOLD);
	ret = regmap_bulk_read(b->map, QG_LAST_BURST_AVG_I, buf, 2);
	regmap_update_bits(b->map, QG_DATA_CTL2, BURST_AVG_HOLD, 0);
	if (ret)
		return ret;
	raw = buf[0] | (buf[1] << 8);
	b->ibat_ua = -(s16)raw * (b->five_amp ? 152588LL : 305176LL) / 1000;

	regmap_read(b->map, SMB5_USBIN_RT_STS, &hi);
	b->plugged = hi & BIT(4);
	regmap_read(b->map, SMB5_CHGR_STATUS1, &lo);
	b->term = (lo & 7) == 5;
	return 0;
}

static void violet_batt_poll(struct work_struct *w)
{
	struct violet_batt *b = container_of(w, struct violet_batt, work.work);
	ktime_t now = ktime_get_boottime();
	s64 dt_ms = ktime_ms_delta(now, b->last);
	int soc, ocv_uv, soc_ocv_x100;

	if (violet_batt_sample(b))
		goto out;
	b->last = now;

	/* coulomb counting, ibat > 0 = discharging */
	if (dt_ms > 0 && dt_ms < 60000)
		b->charge_uah -= (s64)b->ibat_ua * dt_ms / 3600000;

	/* IR-compensated open circuit voltage */
	ocv_uv = b->vbat_uv + (s64)b->ibat_ua * b->rbat_mohm / 1000;
	soc_ocv_x100 = ocv_to_soc_x100(ocv_uv);

	if (abs(b->ibat_ua) < REST_UA) {
		if (!b->resting) {
			b->resting = true;
			b->rest_since = now;
		}
		/* after a quiet spell trust the OCV: nudge the counter to it */
		if (ktime_ms_delta(now, b->rest_since) > REST_SECS * 1000) {
			s64 target = (s64)soc_ocv_x100 * FCC_UAH / 10000;

			b->charge_uah += (target - b->charge_uah) / 20;
		}
	} else {
		b->resting = false;
	}

	/* the charger says the pack is full */
	if (b->plugged && b->term && b->vbat_uv > 4300000 && b->ibat_ua > -150000)
		b->charge_uah = FCC_UAH;

	b->charge_uah = clamp_t(s64, b->charge_uah, 0, FCC_UAH);
	soc = DIV_ROUND_CLOSEST_ULL(b->charge_uah * 100, FCC_UAH);

	/* only publish moves that agree with the current's direction */
	if (soc != b->soc) {
		if ((soc < b->soc && b->ibat_ua > -20000) ||
		    (soc > b->soc && b->ibat_ua < 20000))
			b->soc = soc;
	}
	if (b->soc != b->sdam_soc) {
		regmap_write(b->map, SDAM_SOC, b->soc);
		b->sdam_soc = b->soc;
	}
	dev_dbg(b->dev, "v=%d i=%d ocv=%d soc_ocv=%d.%02d q=%lld soc=%d plug=%d term=%d\n",
		b->vbat_uv, b->ibat_ua, ocv_uv, soc_ocv_x100 / 100, soc_ocv_x100 % 100,
		b->charge_uah, b->soc, b->plugged, b->term);
	power_supply_changed(b->psy);
out:
	schedule_delayed_work(&b->work, msecs_to_jiffies(POLL_MS));
}

static int violet_batt_get(struct power_supply *psy, enum power_supply_property p,
			   union power_supply_propval *val)
{
	struct violet_batt *b = power_supply_get_drvdata(psy);

	switch (p) {
	case POWER_SUPPLY_PROP_PRESENT:
		val->intval = 1;
		return 0;
	case POWER_SUPPLY_PROP_TECHNOLOGY:
		val->intval = POWER_SUPPLY_TECHNOLOGY_LION;
		return 0;
	case POWER_SUPPLY_PROP_VOLTAGE_MAX_DESIGN:
		val->intval = 4400000;
		return 0;
	case POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN:
		val->intval = 3400000;
		return 0;
	case POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN:
		val->intval = FCC_UAH;
		return 0;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		val->intval = b->charge_uah;
		return 0;
	case POWER_SUPPLY_PROP_HEALTH:
		val->intval = POWER_SUPPLY_HEALTH_GOOD;
		return 0;
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		val->intval = b->vbat_uv;
		return 0;
	case POWER_SUPPLY_PROP_CURRENT_NOW:
		val->intval = -b->ibat_ua;	/* kernel ABI: negative = discharging? keep vendor sign flipped */
		return 0;
	case POWER_SUPPLY_PROP_CAPACITY:
		val->intval = b->soc;
		return 0;
	case POWER_SUPPLY_PROP_CAPACITY_LEVEL:
		val->intval = b->soc >= 100 ? POWER_SUPPLY_CAPACITY_LEVEL_FULL :
			      b->soc >= 85 ? POWER_SUPPLY_CAPACITY_LEVEL_HIGH :
			      b->soc >= 20 ? POWER_SUPPLY_CAPACITY_LEVEL_NORMAL :
			      b->soc >= 5 ? POWER_SUPPLY_CAPACITY_LEVEL_LOW :
					    POWER_SUPPLY_CAPACITY_LEVEL_CRITICAL;
		return 0;
	case POWER_SUPPLY_PROP_STATUS:
		if (!b->plugged)
			val->intval = POWER_SUPPLY_STATUS_DISCHARGING;
		else if (b->soc >= 100 || (b->term && b->vbat_uv > 4300000))
			val->intval = POWER_SUPPLY_STATUS_FULL;
		else if (b->ibat_ua < -30000)
			val->intval = POWER_SUPPLY_STATUS_CHARGING;
		else
			val->intval = POWER_SUPPLY_STATUS_NOT_CHARGING;
		return 0;
	default:
		return -EINVAL;
	}
}

static const enum power_supply_property violet_batt_props[] = {
	POWER_SUPPLY_PROP_STATUS, POWER_SUPPLY_PROP_PRESENT, POWER_SUPPLY_PROP_TECHNOLOGY,
	POWER_SUPPLY_PROP_HEALTH, POWER_SUPPLY_PROP_VOLTAGE_NOW, POWER_SUPPLY_PROP_CURRENT_NOW,
	POWER_SUPPLY_PROP_CAPACITY, POWER_SUPPLY_PROP_CAPACITY_LEVEL,
	POWER_SUPPLY_PROP_CHARGE_NOW, POWER_SUPPLY_PROP_CHARGE_FULL_DESIGN,
	POWER_SUPPLY_PROP_VOLTAGE_MAX_DESIGN, POWER_SUPPLY_PROP_VOLTAGE_MIN_DESIGN,
};

static const struct power_supply_desc violet_batt_desc = {
	.name = "battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.properties = violet_batt_props,
	.num_properties = ARRAY_SIZE(violet_batt_props),
	.get_property = violet_batt_get,
};

static int violet_batt_probe(struct platform_device *pdev)
{
	struct power_supply_config cfg = {};
	struct violet_batt *b;
	unsigned int v, soc = 0, valid = 0, rbat[2] = {};
	int soc_x100;

	b = devm_kzalloc(&pdev->dev, sizeof(*b), GFP_KERNEL);
	if (!b)
		return -ENOMEM;
	b->dev = &pdev->dev;
	b->map = dev_get_regmap(pdev->dev.parent, NULL);
	if (!b->map)
		return -ENODEV;

	regmap_read(b->map, QG_SUBTYPE, &v);
	b->five_amp = v == QG_ADC_IBAT_5A;
	regmap_read(b->map, SDAM_VALID, &valid);
	regmap_read(b->map, SDAM_SOC, &soc);
	regmap_read(b->map, SDAM_RBAT, &rbat[0]);
	regmap_read(b->map, SDAM_RBAT + 1, &rbat[1]);
	b->rbat_mohm = rbat[0] | (rbat[1] << 8);
	if (b->rbat_mohm < 20 || b->rbat_mohm > 400)
		b->rbat_mohm = 120;

	if (violet_batt_sample(b))
		return dev_err_probe(&pdev->dev, -EIO, "QG not answering\n");
	soc_x100 = ocv_to_soc_x100(b->vbat_uv + (s64)b->ibat_ua * b->rbat_mohm / 1000);
	/*
	 * Start from the OCV estimate when the pack is resting; with a load on it
	 * (or while charging) the downstream driver's saved value is better.
	 */
	if (abs(b->ibat_ua) < REST_UA || !valid || soc > 100 || !soc)
		b->soc = DIV_ROUND_CLOSEST(soc_x100, 100);
	else
		b->soc = soc;
	b->sdam_soc = soc;
	b->charge_uah = (s64)b->soc * FCC_UAH / 100;
	b->last = ktime_get_boottime();
	dev_info(&pdev->dev, "QG %s, rbat %d mOhm, sdam soc %u (valid %u), vbat %d uV ibat %d uA -> start %d%%\n",
		 b->five_amp ? "5A" : "10A", b->rbat_mohm, soc, valid, b->vbat_uv, b->ibat_ua, b->soc);

	cfg.drv_data = b;
	cfg.fwnode = dev_fwnode(&pdev->dev);
	b->psy = devm_power_supply_register(&pdev->dev, &violet_batt_desc, &cfg);
	if (IS_ERR(b->psy))
		return PTR_ERR(b->psy);
	INIT_DELAYED_WORK(&b->work, violet_batt_poll);
	platform_set_drvdata(pdev, b);
	schedule_delayed_work(&b->work, msecs_to_jiffies(POLL_MS));
	return 0;
}

static void violet_batt_remove(struct platform_device *pdev)
{
	cancel_delayed_work_sync(&((struct violet_batt *)platform_get_drvdata(pdev))->work);
}

static const struct of_device_id violet_batt_of[] = {
	{ .compatible = "xiaomi,violet-vbat" }, {}
};
MODULE_DEVICE_TABLE(of, violet_batt_of);

static struct platform_driver violet_batt_driver = {
	.probe = violet_batt_probe,
	.remove = violet_batt_remove,
	.driver = { .name = "violet-vbat", .of_match_table = violet_batt_of },
};
module_platform_driver(violet_batt_driver);
MODULE_DESCRIPTION("violet battery gauge reading the QG hardware");
MODULE_LICENSE("GPL");
