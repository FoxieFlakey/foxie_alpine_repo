#!/bin/sh

# Strict exit code checking
set -Eeuo pipefail

if [ $# -lt 2 ] && [ $# -gt 3 ]; then
  1>&2 echo "Usage: $0 <dest directory> <build config path> [container id for reuse]"
  exit 1
fi

dest_dir="$1"
config_path="$2"
if [ ! -d "$1" ]; then
  mkdir -- "$1"
fi

if [ $# -lt 3 ]; then
  echo "[HOST] [INFO] Creating container"
  container_id="$(docker create foxie_build_packages)"
  container_reused=n
else
  echo "[HOST] [INFO] Reusing container"
  container_id="$3"
  container_reused=y
fi

echo "[HOST] [INFO] Copying files"
docker cp -- "$2" "$container_id:/config/config.json"

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


