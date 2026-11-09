#!/usr/bin/env python3
"""violet: libcamera soft-ISP tuning patches (AWB smoothing, highlight-weighted AGC, tone shoulder)."""
import sys, pathlib
root = pathlib.Path.home() / "lc/libcamera-v0.7.2"
changed = []

def patch(path, old, new, tag):
    p = root / path
    s = p.read_text()
    if new in s:
        print(f"  = {tag} already applied"); return
    n = s.count(old)
    if n != 1:
        print(f"  ! {tag}: anchor found {n} times in {path}"); sys.exit(2)
    p.write_text(s.replace(old, new))
    changed.append(f"{path}: {tag}")
    print(f"  + {tag}")

SHADERS = ["src/libcamera/shaders/bayer_1x_packed.frag",
           "src/libcamera/shaders/bayer_unpacked.frag"]

SH_T_OLD = """	/* Apply gamma after colour correction */
	rgb = pow(rgb, vec3(gamma));

"""
SH_T_NEW = """	/* Apply gamma after colour correction */
	rgb = pow(rgb, vec3(gamma));

	/*
	 * violet: highlight shoulder. Values above the knee are compressed
	 * smoothly towards 1.0 instead of clipping, so specular/bright objects
	 * keep their structure instead of turning into a flat white blob.
	 */
	const float knee = 0.72;
	const float kneeRange = 1.0 - knee;
	vec3 over = max(rgb - vec3(knee), vec3(0.0));
	rgb = min(rgb, vec3(knee)) + vec3(kneeRange) * over / (over + vec3(kneeRange));

"""
patch(SHADERS[0], SH_T_OLD, SH_T_NEW, "shader shoulder (bayer_1x_packed.frag)")

# bayer_unpacked.frag uses 4-space indentation
SH_T_OLD_SP = SH_T_OLD.replace("\t", "    ")
SH_T_NEW_SP = SH_T_NEW.replace("\t", "    ")
patch(SHADERS[1], SH_T_OLD_SP, SH_T_NEW_SP, "shader shoulder (bayer_unpacked.frag)")

CPU_OLD = """		value = UINT8_MAX * std::pow(normalized, gamma);
"""
CPU_NEW = """		/* violet: highlight shoulder, same curve as the GPU shader. */
		float valueF = std::pow(normalized, gamma);
		constexpr float knee = 0.72f;
		if (valueF > knee) {
			constexpr float kneeRange = 1.0f - knee;
			const float over = valueF - knee;
			valueF = knee + kneeRange * over / (over + kneeRange);
		}
		value = UINT8_MAX * valueF;
"""
patch("src/libcamera/software_isp/debayer_cpu.cpp", CPU_OLD, CPU_NEW, "cpu gamma shoulder")

AWB_OLD = """	auto &gains = context.activeState.awb.gains;
	gains = { {
		sum.r() <= sum.g() / 4 ? 4.0f : static_cast<float>(sum.g()) / sum.r(),
		1.0,
		sum.b() <= sum.g() / 4 ? 4.0f : static_cast<float>(sum.g()) / sum.b(),
	} };
"""
AWB_NEW = """	/*
	 * violet: temporal smoothing. The raw grey-world estimate jumps with
	 * every frame (and with every object entering the frame), which showed up
	 * as the preview/shot flipping between neutral and green. Converge
	 * towards the target instead of adopting it, and ignore sub-1% wobble.
	 */
	const float targetR = sum.r() <= sum.g() / 4 ? 4.0f : static_cast<float>(sum.g()) / sum.r();
	const float targetB = sum.b() <= sum.g() / 4 ? 4.0f : static_cast<float>(sum.g()) / sum.b();
	constexpr float kAwbSmoothing = 0.12f;
	constexpr float kAwbDeadband = 0.01f;

	auto &gains = context.activeState.awb.gains;
	float nextR = gains.r() + kAwbSmoothing * (targetR - gains.r());
	float nextB = gains.b() + kAwbSmoothing * (targetB - gains.b());
	if (std::abs(targetR - gains.r()) < kAwbDeadband * gains.r())
		nextR = gains.r();
	if (std::abs(targetB - gains.b()) < kAwbDeadband * gains.b())
		nextB = gains.b();
	gains = { { nextR, 1.0f, nextB } };
"""
patch("src/ipa/simple/algorithms/awb.cpp", AWB_OLD, AWB_NEW, "awb temporal smoothing")

AGC_OLD = """	float exposureMSV = (denom == 0 ? 0 : static_cast<float>(num) / denom);
	updateExposure(context, frameContext, exposureMSV);
"""
AGC_NEW = """	float exposureMSV = (denom == 0 ? 0 : static_cast<float>(num) / denom);

	/*
	 * violet: highlight-weighted metering. The mid-range MSV target happily
	 * lets a bright object clip (a white shirt filled 10% of a shot with
	 * 255,255,255). Bias the target darker as the population of the top
	 * histogram bins grows, so highlights roll off instead.
	 */
	if (denom > 0) {
		unsigned int totalPixels = 0;
		unsigned int hiPixels = 0;
		const unsigned int hiStart = SwIspStats::kYHistogramSize * 9 / 10;

		for (unsigned int i = 0; i < SwIspStats::kYHistogramSize; i++)
			totalPixels += histogram[i];
		for (unsigned int i = hiStart; i < SwIspStats::kYHistogramSize; i++)
			hiPixels += histogram[i];

		if (totalPixels) {
			const float hiRatio = static_cast<float>(hiPixels) / totalPixels;
			constexpr float kHiLimit = 0.02f;
			constexpr float kHiWeight = 8.0f;
			if (hiRatio > kHiLimit) {
				const float pull = std::min(kHiWeight * (hiRatio - kHiLimit),
							    static_cast<float>(kExposureBinsCount));
				exposureMSV += pull;
				LOG(IPASoftExposure, Debug) << "highlights " << hiRatio * 100 << "% -> MSV -" << pull;
			}
		}
	}

	updateExposure(context, frameContext, exposureMSV);
"""
patch("src/ipa/simple/algorithms/agc.cpp", AGC_OLD, AGC_NEW, "agc highlight weighting")

# std::abs for floats
p = root / "src/ipa/simple/algorithms/awb.cpp"
s = p.read_text()
if "#include <cmath>" not in s:
    s = s.replace("#include <numeric>", "#include <cmath>\n#include <numeric>", 1)
    p.write_text(s); changed.append("awb.cpp: include cmath"); print("  + awb include <cmath>")

print("changed files:", len(changed))
