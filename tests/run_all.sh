#!/bin/sh
set -eu

usage() {
	echo "usage: $0 [bmk [output-root]]" >&2
	exit 1
}

if test "$#" -gt 2
then
	usage
fi

if test "$#" -ge 1
then
	bmk=$1
else
	bmk=$(command -v bmk || true)
fi

if test -z "$bmk" || test ! -x "$bmk"
then
	echo "A runnable bmk was not found. Pass its path as the first argument." >&2
	exit 1
fi

bmk_dir=$(CDPATH= cd -- "$(dirname -- "$bmk")" && pwd -P)
bmk="$bmk_dir/$(basename -- "$bmk")"
sdk_root=$(CDPATH= cd -- "$bmk_dir/.." && pwd -P)
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
installed_repository="$sdk_root/mod/gamenet.mod"

if test ! -d "$installed_repository"
then
	echo "GameNet is not installed at $installed_repository" >&2
	exit 1
fi

installed_repository=$(CDPATH= cd -- "$installed_repository" && pwd -P)
if test "$installed_repository" != "$repository"
then
	echo "This checkout is not the GameNet copy used by the selected SDK." >&2
	echo "Repository: $repository" >&2
	echo "Installed:  $installed_repository" >&2
	exit 1
fi

if test "$#" -eq 2
then
	output_root=$2
	if test -e "$output_root"
	then
		echo "Output path already exists: $output_root" >&2
		exit 1
	fi
	mkdir -p "$output_root"
else
	output_root=$(mktemp -d "${TMPDIR:-/tmp}/gamenet-tests.XXXXXX")
fi
output_root=$(CDPATH= cd -- "$output_root" && pwd -P)

platform=$(uname -s)
architecture=$(uname -m)
executable_suffix=
steam_runtime=

case "$platform" in
	Darwin)
		steam_runtime="$sdk_root/mod/steam.mod/steamsdk.mod/sdk/redistributable_bin/osx/libsteam_api.dylib"
		;;
	Linux)
		case "$architecture" in
			x86_64|amd64) steam_directory=linux64 ;;
			aarch64|arm64) steam_directory=linuxarm64 ;;
			i386|i486|i586|i686) steam_directory=linux32 ;;
			*) echo "Unsupported Linux architecture: $architecture" >&2; exit 1 ;;
		esac
		steam_runtime="$sdk_root/mod/steam.mod/steamsdk.mod/sdk/redistributable_bin/$steam_directory/libsteam_api.so"
		;;
	MINGW*|MSYS*)
		executable_suffix=.exe
		steam_runtime="$sdk_root/mod/steam.mod/steamsdk.mod/sdk/redistributable_bin/win64/steam_api64.dll"
		;;
	*)
		echo "Unsupported test host: $platform" >&2
		exit 1
		;;
esac

if test ! -f "$steam_runtime"
then
	echo "Steam runtime was not found: $steam_runtime" >&2
	exit 1
fi
cp "$steam_runtime" "$output_root/$(basename -- "$steam_runtime")"

if test "$platform" = Darwin && test ! -d "$sdk_root/mod/apple.mod/gamekit.mod"
then
	echo "Apple.GameKit is required for macOS tests: $sdk_root/mod/apple.mod/gamekit.mod" >&2
	exit 1
fi

manifest="$output_root/tests.list"
find "$repository" -path '*/tests/test.bmx' -type f | sort > "$manifest"
find "$repository/examples" -name 'test*.bmx' -type f | sort >> "$manifest"

test_count=0
run_test() {
	source=$1
	relative=${source#"$repository"/}
	case "$platform:$relative" in
		Darwin:*) ;;
		*:gamekit.mod/tests/test.bmx) return ;;
	esac

	name=$(printf '%s' "$relative" | sed 's#/tests/test\.bmx$##; s#\.mod$##; s#\.bmx$##; s#[^A-Za-z0-9_-]#-#g')
	executable="$output_root/$name"
	build_log="$output_root/$name.build.log"
	run_log="$output_root/$name.run.log"

	printf 'TEST %-56s' "$relative"
	if ! "$bmk" makeapp -r -o "$executable" "$source" > "$build_log" 2>&1
	then
		echo "BUILD FAILED"
		cat "$build_log"
		exit 1
	fi
	if ! "$executable$executable_suffix" > "$run_log" 2>&1
	then
		echo "RUN FAILED"
		cat "$run_log"
		exit 1
	fi
	echo "PASSED"
	test_count=$((test_count + 1))
}

while IFS= read -r source
do
	run_test "$source"
done < "$manifest"

echo
echo "$test_count GameNet test programs passed."
echo "Build and run logs: $output_root"
