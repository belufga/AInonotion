#!/usr/bin/env bash
# Headless Windows Desktop (x86_64) export of SandboxGore.
#
#   tools/export_windows.sh [release|debug]
#
# GODOT selects the editor binary (default: "godot" on PATH) and GODOT_TEMPLATES the export
# template root. Details and troubleshooting: docs/WINDOWS_EXPORT.md.
set -euo pipefail

cd "$(dirname "$0")/.."
godot="${GODOT:-godot}"
mode="${1:-release}"
out="build/windows/SandboxGore.exe"

case "$mode" in
release | debug) ;;
*)
	echo "usage: $0 [release|debug]" >&2
	exit 2
	;;
esac

# "4.7.2.stable.official.ed1daf0bf" -> "4.7.2.stable", the name of the template directory.
version="$("$godot" --version)"
version="${version%.official*}"
templates="${GODOT_TEMPLATES:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates}/$version"
template="$templates/windows_${mode}_x86_64.exe"
if [ ! -f "$template" ]; then
	echo "Missing export template: $template" >&2
	echo "Install the $version Windows templates first, see docs/WINDOWS_EXPORT.md." >&2
	exit 1
fi

# Stale artifacts would hide a failed export from the check below.
rm -f "$out" "${out%.exe}.pck" "${out%.exe}.console.exe"
mkdir -p "$(dirname "$out")"
"$godot" --headless --path . --import
"$godot" --headless --path . "--export-$mode" "Windows Desktop" "$out"

for artifact in "$out" "${out%.exe}.pck"; do
	if [ ! -s "$artifact" ]; then
		echo "Export failed: $artifact was not written" >&2
		exit 1
	fi
done
ls -l "$(dirname "$out")"
