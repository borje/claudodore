# Run from programs/<machine>/<name>/. Each run.py owns its build: `run.py build` builds, prints the PRG path(s), exits.
# build:  -> build/<machine>/<name>*.prg
# runvice: builds, then autostarts the (first) PRG in a VICE window (x64sc / xvic).
# upload: builds, then copies the PRG(s) to /Usb0/c64/ on the C64 Ultimate (c64 programs only).

build:
    @cd "{{invocation_directory()}}" && uv run --project "{{justfile_directory()}}" run.py build

runvice:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{invocation_directory()}}"
    case "$(basename "$(dirname "$PWD")")" in c64) vice=x64sc ;; vic20) vice=xvic ;; *) echo "runvice: run from programs/<machine>/<name>/" >&2; exit 1 ;; esac
    prg=$(uv run --project "{{justfile_directory()}}" run.py build | head -1)
    exec "$vice" -autostart "$prg"

upload:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{invocation_directory()}}"
    [[ -f run.py && "$(basename "$(dirname "$PWD")")" == c64 ]] || { echo "upload: run from programs/c64/<name>/" >&2; exit 1; }
    prgs=$(uv run --project "{{justfile_directory()}}" run.py build)  # fails here if the build fails
    c64u fs ls /Usb0/c64 >/dev/null 2>&1 || c64u fs mkdir /Usb0/c64
    while IFS= read -r prg; do c64u fs upload "$prg" "/Usb0/c64/$(basename "$prg")"; done <<< "$prgs"
