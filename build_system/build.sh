#!/bin/sh

# Strict exit code checking
set -Eeuo pipefail

# Load user's abuild.conf
if [ -f "$HOME/.abuild/abuild.conf" ]; then
  . "$HOME/.abuild/abuild.conf"
else
  1>&2 echo "[HOST] [ERROR] Cannot load abuild.conf from ~/.abuild/abuild.conf"
  1>&2 echo "[HOST] [ERROR] Try generate new keys with abuild-keygen"
  exit 1
fi

if [ $# -lt 1 ] && [ $# -gt 2 ]; then
  1>&2 echo "Usage: $0 <dest directory> [container id for reuse]"
  exit 1
fi

dest_dir="$1"
config_path="$(mktemp)"
trap "rm -f '$config_path'" EXIT

function lua_format {
  format="$1"
  # Remove $1
  shift
  echo "print(string.format([==[$format]==], table.unpack(arg)))" | lua5.4 - "$@"
}

function safe_quote_with_substituted_new_line {
  lua5.4 -e "print((string.format('%q', io.read('*a')):gsub('\\n', 'n')))"
}

public_key_name="$(basename -- "$PACKAGER_PRIVKEY.pub")"
private_key_name="$(basename -- "$PACKAGER_PRIVKEY")"
public_key="$(cat "$PACKAGER_PRIVKEY.pub" | safe_quote_with_substituted_new_line)"
private_key="$(cat "$PACKAGER_PRIVKEY" | safe_quote_with_substituted_new_line)"

# Generate the build config containing packager information and signing keys
lua_format "{\"packager\": %q, \"maintainer\": %q, \"public_signing_key\": {\"name\": %q, \"key\": %s}, \"private_signing_key\": {\"name\": %q, \"key\": %s}}" "$PACKAGER" "$MAINTAINER" "$public_key_name" "$public_key" "$private_key_name" "$private_key" > "$config_path"

if [ ! -d "$dest_dir" ]; then
  mkdir -- "$dest_dir"
fi

if [ $# -lt 2 ]; then
  echo "[HOST] [INFO] Creating container"
  container_id="$(docker create foxie_build_packages)"
  container_reused=n
else
  echo "[HOST] [INFO] Reusing container"
  container_id="$2"
  container_reused=y
fi

echo "[HOST] [INFO] Copying files"
docker cp -- "$config_path" "$container_id:/config/config.json"

# Copy each file from source repository
(
  cd "$(git rev-parse --show-toplevel)"
  git ls-tree --name-only HEAD | while read -r relative_path; do
    docker cp -- "$relative_path" "$container_id:/source_repo/$relative_path"
  done
)

echo "[HOST] [INFO] Running the build"
docker start --attach "$container_id"

echo "[HOST] [INFO] Copying the result"
docker cp -- "$container_id:/output_repo/." "$dest_dir"

if [ "$container_reused" == n ]; then
  echo "[HOST] [INFO] Deleting container"
  docker rm "$container_id"
else
  echo "[HOST] [INFO] Container was reused don't delete"
fi


