# PresentMon And LatencyMon Notes

Use this reference when the user provides telemetry or when you need to interpret likely spike ownership.

## PresentMon Heuristics
- Good averages with rare giant frametime spikes usually indicate burst contention, background activity, shader compilation, asset streaming, or a display-path transition.
- High `MsCPUBusy` on spike frames with low `MsGPUTime` points toward CPU-side scheduling, game-thread stalls, or background contention.
- High `MsCPUWait` can indicate the CPU is waiting on GPU completion or another dependency; read it together with `MsGPUWait` and `MsGPUTime`.
- High `MsGPUWait` or `MsGPUTime` on spike frames points toward GPU load, driver path issues, VRAM pressure, or rendering settings.
- `PresentMode: Other` and `Composed: Flip` can include menu transitions, overlays, or alt-tab artifacts; avoid overfitting those frames.

## LatencyMon Heuristics
- Top DPC or ISR offenders suggest driver latency, but do not claim causation without timing alignment to the actual symptom.
- Hard pagefault leaders matter most when spikes coincide with storage activity, memory pressure, or app background loading.
- Network, audio, storage, RGB, and peripheral software are common offenders worth isolating before deeper system changes.
- One bad LatencyMon sample after long uptime is weaker evidence than a cleanly reproduced capture around the symptom.

## Interpretation Guardrails
- Do not label a problem as GPU-bound only from low FPS. Use spike-frame metrics.
- Do not treat a single driver module as guilty unless the symptom improved when the related feature or process was removed.
- Do not recommend blanket registry edits when the evidence still supports a simpler profile, overlay, or background-process mismatch.

## Useful Comparison Questions
- Did the spike frequency change, or only spike magnitude?
- Did CPU-side metrics drop after the change, or did the issue merely move elsewhere?
- Did the problem appear only on one account, one save, one display mode, or one monitor refresh path?
