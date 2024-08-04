#!/usr/bin/env bash

set -Eeuo pipefail

source_dir="$( dirname -- "${BASH_SOURCE[0]}"; )";   # Get the directory name
source_dir="$( realpath -e -- "$source_dir"; )";    # Resolve its full path if need be

if [ ! -f "$source_dir/build_order.txt" ]; then
  1>&2 echo "[ERROR] Source dir at '$source_dir' is not a valid Foxie's Alpine repo source"
  exit 1
fi

cd "$source_dir"
build_dir="$source_dir/build"

if [ ! -d "$build_dir" ]; then
  mkdir -- "$source_dir/build"
fi

function is_container_exist {
  if [ ! -f "$build_dir/previous_container.txt" ]; then
    return 1
  fi
  
  # Check if container not rm'ed yet
  id="$(cat "$build_dir/previous_container.txt")"
  if [ "$(docker ps --no-trunc --all --quiet | grep "^$id")" != "" ]; then
    return 0
  fi
  
  # The container was already rm'ed delete old stored ID and recreate
  echo "[INFO] Container was deleted recreating"
  rm -f -- "$build_dir/previous_container.txt"
  return 1
}

if is_container_exist; then
  # Reuse previous container
  container_id="$(cat "$build_dir/previous_container.txt")"
  echo "[INFO] Reusing previous container (ID is $container_id)"
else
  # Try create Docker container for later reuse on next invocation
  container_id="$(docker create foxie_build_packages)"
  echo "[INFO] Created new container for future reuse (ID: $container_id)"
  if printf "%s" "$container_id" > "$build_dir/previous_container.txt"; then
    :
  else
    exit_code="$?"
    1>&2 echo "[ERROR] Cannot save container ID at '$build_dir/previous_container.txt'"
    1>&2 echo "[ERROR] Deleting container"
    docker rm "$container_id"
    exit "$exit_code"
  fi
fi

sh -- "$source_dir/build_system/build.sh" "$build_dir/packages" "$container_id"

