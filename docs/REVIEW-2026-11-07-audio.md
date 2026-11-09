# Independent review of the headphone routing plan (2026-11-07)

Two reviewers, same conclusion: the "front end is bound to a back end" premise is probably WRONG; the
symptom is a Linux-side desync in q6routing/ADM, not a stuck port inside the DSP firmware.

## Reviewer A (Claude, Opus, via `claude -p --model opus`)

- `sound/soc/qcom/qdsp6/q6routing.c` keeps ONE `port_id` per front-end session, but each
  `<BE> Audio Mixer MultiMediaN` switch has its own DAPM path:
  - turning a switch ON sets `session->port_id = be_id` and connects only that kcontrol's path; the path to
    the previous BE stays connected;
  - GET reports 1 only for the current `port_id`, so the old route *reads* as 0 while DAPM still has it
    connected;
  - turning the OLD switch OFF hits `session->port_id != be_id` and returns 0 without disconnecting - the
    stale path cannot be cleared from userspace, only by a reboot;
  - `q6routing_stream_open` opens the ADM copp only on `port_id`, with params filled by that BE's hw_params,
    while DPCM starts whichever BEs DAPM believes are connected.
  => the ASM session can be matrix-mapped to a copp on an AFE port that DPCM never started, with stale or zero
  parameters. The DSP then never drains the buffer: no write-done, no period IRQ, `paplay` blocks forever and
  there is no kernel error. "Whichever was used last works" is last-writer-wins on `port_id`.
- Therefore: the FE/BE "binding" observation was almost certainly measured after cross-routing had already
  desynced things, and the "MM4<->codec, MM3<->MI2S" rule is not a hardware fact.
- Plan changes: never cross-route (one FE per BE, fixed at boot); one UCM card with two devices and let
  PulseAudio switch ports; drop the ADSP-restart idea (APR/PDR teardown takes the card down, and on reboot the
  re-probe "fixes" it only by accident); AudioReach is not reachable on this firmware (needs an ADSP built with
  GPR/APM - the stock Android-9 ADSP speaks APR/ADM).
- Real fix worth upstreaming: in `msm_routing_put_audio_mixer`, when switching an FE to a new BE, first
  disconnect the previous BE's kcontrol path (found via `port_id`), or reject the switch with -EBUSY while
  another BE is selected.
- Cheap discriminators: read back `amixer contents` vs the DPCM `/sys/kernel/debug/asoc/<card>/<link>/state`
  after cross-routing; from a clean boot route ONLY MM3 -> codec-DMA and play; while a stream is hung, check
  that pcm3p is `RUNNING` with a frozen `hw_ptr`.

## Reviewer B (independent subagent, same facts, no repo access)

- Ranked mechanisms: (1) ADM COPP/matrix leak, (2) q6routing bookkeeping not reset, (3) q6afe port-state skew,
  (4) clock/GDSC vote leak, (5) DPCM runtime stuck (low), (6) SWR slave detach (that is the other bug).
  A genuinely leaked AFE port normally fails the NEXT start with -EBUSY/-EIO, not a silent block - so the
  "AFE port leak" theory is weak compared with 1-3.
- `0x3008=c1 / 0x3009=fc` proves analog power, not data flow; and "clean logs" proves nothing while
  pr_debug is off - enable `dynamic_debug` for `drivers/soc/qcom/qdsp6/*` and for q6afe/q6adm/q6asm/q6routing
  before concluding there is no error.
- Decisive test: a FRESH front end (MM1) into the stuck BE, then the stuck FE into a healthy BE. Fresh FE also
  hangs => back-end side; only the reused FE hangs => session/ADM side.
- remoteproc ADSP restart with the card bound will hang; needs a full unbind/rebind sequence. Not a recovery
  tool; `violet-bus-guard release/ensure` stays the cheap recovery.
- Do not go back to a design where a PA profile/sink switch re-creates PCMs under a live stream.
