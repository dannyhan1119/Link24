#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_font="${1:-${project_root}/fonts/source/NotoSansCJKsc-Regular.full.otf}"
output_font="${2:-${project_root}/fonts/NotoSansCJKsc-Regular.otf}"

if ! command -v hb-subset >/dev/null 2>&1; then
	printf 'hb-subset is required (provided by Homebrew harfbuzz).\n' >&2
	exit 1
fi

if [[ ! -f "${source_font}" ]]; then
	printf 'Source font not found: %s\n' "${source_font}" >&2
	exit 1
fi

corpus_file="$(mktemp "${TMPDIR:-/tmp}/link24-font-corpus.XXXXXX")"
output_tmp="$(mktemp "${TMPDIR:-/tmp}/link24-font-subset.XXXXXX.otf")"
trap 'rm -f "${corpus_file}" "${output_tmp}"' EXIT

# Keep printable ASCII even if a character is not currently present in a label.
printf '%s\n' ' !"#$%&'\''()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~' > "${corpus_file}"

# UI copy lives in scripts and project resources. Feeding the complete files to
# HarfBuzz is intentional: it catches localized strings without maintaining a
# fragile hand-written character list.
while IFS= read -r source_file; do
	cat "${project_root}/${source_file}" >> "${corpus_file}"
done < <(
	cd "${project_root}"
	rg --files src scenes data 2>/dev/null | rg '\.(gd|tscn|tres|json|cfg|csv)$' || true
)
cat "${project_root}/project.godot" >> "${corpus_file}"

hb-subset "${source_font}" \
	--text-file="${corpus_file}" \
	--layout-features='*' \
	--name-IDs='*' \
	--output-file="${output_tmp}"

mv "${output_tmp}" "${output_font}"
chmod 0644 "${output_font}"
printf 'Wrote %s (%s bytes)\n' "${output_font}" "$(stat -f %z "${output_font}")"
