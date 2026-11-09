# Review request: headphone jack routing on mainline Linux (Qualcomm sm6150 / WCD9375)

Please review this diagnosis and plan critically. Say plainly which parts are wrong, which are unproven, and
what you would test first. Assume the author is an experienced kernel person; skip pleasantries.

## Device / stack
- Xiaomi Redmi Note 7 Pro ("violet"), SM6150, mainline Linux 7.2.10, postmarketOS (OpenRC, Phosh,
  PulseAudio 17).
- Audio: legacy Qualcomm DSP path (mainline `q6asm`/`q6afe`/`q6routing`, NOT AudioReach/q6apm).
- Codec: WCD9375 (wcd937x), SoundWire. Two slaves: RX `sdw:2:0:0217:010a:00:4`, TX `sdw:3:0:0217:010a:00:3`.
  Forms: TX (mic capture, `TX_CODEC_DMA_TX_3`) works and has for weeks.
- Speaker: TI TAS2563 amp on `PRI_MI2S_RX` (front end MultiMedia3, hw:0,2).
- Jack: WCD9375 HPHL/HPHR via `RX_CODEC_DMA_RX_0` (front end MultiMedia4, hw:0,3).
- Stock ADSP firmware (Android 9 era). No vendor HAL in use; no calibration (acdb) plumbing.

## Observed behaviour
1. With a clean boot, both outputs play (verified by ear + TAS amp log). 
2. After a number of route/stream start-stop cycles, ONE back-end stops working: its playback blocks forever
   (`paplay` never returns, `rc=124`), the speaker amp logs no activity, and there is **no kernel error at all**.
   The other back-end still returns rc=0.
3. Whichever was used last tends to be the one that still works; the other needs a reboot to recover.
4. A reboot always restores both.
5. Specific mapping measured by bisection:
   - MultiMedia3 -> codec-DMA (`RX_CODEC_DMA_RX_0`) = silent (clean logs, codec registers powered: 0x3008=c1,
     0x3009=fc). MultiMedia4 -> codec-DMA = works.
   - MultiMedia3 -> `PRI_MI2S_RX` = works. MultiMedia4 -> `PRI_MI2S_RX` = silent.
   i.e. each front end appears bound to one back end.
6. SoundWire: the RX slave detaches when idle; a runtime-PM resume of the master/slave re-attaches it. If the
   master clock-stops and later resumes, the bus can wedge: `SWR CMD error, fifo status 0x3e0010xx`,
   then `DPN_PortCtrl register write failed for port 1`, `Program params failed: -5`,
   `WCD937x Playback: ASoC error (-5) at snd_soc_link_prepare()`, and `write error: I/O error`. Holding
   `power/control=on` on the RX master avoids that.
7. The codec's SDW slave has no DisCo properties (`dev-properties` empty), so `clk_stop_mode1` is false.
   Kernel patched so `qcom_swrm_clk_stop_needs_reset()` forces the controller reset path on resume
   (`drivers/soundwire/qcom.c`); with the bus held awake this path never runs.

## Current workaround
- Two PulseAudio sinks: card `Speaker` (hw:0,2) and `violet_hph` (module-alsa-sink on hw:0,3).
- A user-level watcher (OpenRC service) polls the kernel jack control (`amixer -D hw:0`, numid lookup) and
  switches the **default sink**; it holds the RX master awake.
- No live stream moving (it killed the GStreamer player), no simultaneous use of both PCMs (it wedged
  PulseAudio and the DSP logged SWR CMD errors).

## Proposed plan, please critique
1. Add switch discipline: on jack change, stop the old path, unload the unused sink so its PCM closes, wait
   for the DPCM/back-end to report stopped, then switch the default sink (mirroring what Android's HAL does).
2. When a back-end sticks, restart the ADSP via remoteproc stop/start instead of rebooting (~2 s) to clear the
   AFE port table; validate that it does clear it.
3. Longer term: move this card to AudioReach (q6apm/q6apmbedai), which models device switching properly.

## Questions
- Is the "leaked/stuck AFE port in the ADSP" explanation consistent with the evidence, or is a different
  mechanism more likely (e.g. AFE port refcount leak in mainline q6afe, clock-vote imbalance, AFE port id
  mismatch, ADM matrix not cleared, DSP requiring a specific port-teardown order)?
- Are the front-end/back-end bindings (MM3->MI2S, MM4->codec-DMA) explained by the ADM "copp" topology on
  this firmware, and is there a way to make MM3 feed the codec-DMA port without the vendor HAL? Would an
  explicit ADM matrix/copy-id configuration through existing mainline controls allow it?
- Does restarting the ADSP from Linux (remoteproc) reliably reset AFE state without breaking the sound card
  (DAI/component state), or will the card need a rebind?
- Is AudioReach realistically reachable on this firmware (stock sm6150 ADSP, Android 9 era) or does it require
  a newer ADSP image?
- Anything cheap I have not measured that would discriminate between these hypotheses?
