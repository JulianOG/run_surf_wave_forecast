# Port Fairy maximum-map fix

Replace only this file in the repository:

- `scripts/render_social_assets.R`

The pinned FUNWAVE-TVD executable has no `WaveHeight` output option. The old
script therefore failed while looking for files that it can never produce.

The replacement uses FUNWAVE's supported `Hmax` output and labels it correctly
as **maximum free-surface elevation (Hmax)**. This is not presented as maximum
individual-wave height. If an older executable does not write `Hmax`, it falls
back to the maximum saved eta snapshot and labels that clearly.

Commit and push this one file, then rerun the workflow. No Docker rebuild is
needed.
