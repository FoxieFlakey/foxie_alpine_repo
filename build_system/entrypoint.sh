#!/bin/sh

# Strict exit code checking
set -Eeuo pipefail

# Get sensitive configuration only from cp'ed file
# Example configuration:
# {
#   // Same as one in abuild.conf
#   "packager": "Foxie Flakey <foxieflakey@gmail.com>",
#   // Same as one in abuild.conf
#   "maintainer": "Foxie Flakey <foxieflakey@gmail.com>",
#   "public_signing_key": {
#     // Same as filename abuild-keygen generates in .abuild directory
#     "name": "foxieflakey@gmail.com-668771b6.rsa.pub",
#     "key": "...."
#   },
#   "private_signing_key": {
#     // Same as filename abuild-keygen generates in .abuild directory
#     "name": "foxieflakey@gmail.com-668771b6.rsa",
#     "key": "...."
#   }
# }

config_path="/config/config.json"
if [ -f "$config_path" ]; then
  echo "[INFO] Using config at $config_path"
  config="$(cat $config_path)"
else
  1>&2 echo "[ERROR] First run, please copy config to $config_path"
  exit 1 
fi

packager="$(echo "$config" | jq --raw-output .packager)"
maintainer="$(echo "$config" | jq --raw-output .packager)"
public_key_name="$(echo "$config" | jq --raw-output .public_signing_key.name)"
private_key_name="$(echo "$config" | jq --raw-output .private_signing_key.name)"
public_key="$(echo "$config" | jq --raw-output .public_signing_key.key)"
private_key="$(echo "$config" | jq --raw-output .private_signing_key.key)"

function is_filename_unsafe {
  # Exit successfully ONLY if something forbidden is matched
  if [ "$(printf "%s" "$1" | grep "([/][.]{1,2})|[/]|[^-a-zA-Z0-9@.]")" != "" ]; then
    return 0
  fi
  return 1
}

if is_filename_unsafe "$public_key_name"; then
  1>&2 echo "[ERROR] Public key name '$public_key_name' is unsafe key name (it must be valid filename)"
  exit 1
fi

if is_filename_unsafe "$private_key_name"; then
  1>&2 echo "[ERROR] Private key name '$private_key_name' is unsafe key name (it must be valid filename)"
  exit 1
fi

echo "[INFO] Packager: $packager"
echo "[INFO] Maintainer: $maintainer"
echo "[INFO] Public key name: $public_key_name"
echo "[INFO] Private key name: $private_key_name"

function lua_format {
  format="$1"
  # Remove $1
  shift
  echo "print(string.format('$format', table.unpack(arg)))" | lua5.4 - "$@"
}

abuild_conf="/home/runner/.abuild/abuild.conf"
echo "[INFO] Creating $abuild_conf"
mkdir -p -- "$(dirname $abuild_conf)"
lua_format "MAINTAINER=%q" "$maintainer" > $abuild_conf
lua_format "PACKAGER=%q" "$packager" >> $abuild_conf
lua_format "PACKAGER_PRIVKEY=%q" "/home/runner/.abuild/$private_key_name" >> $abuild_conf
printf "%s" "$private_key" > "/home/runner/.abuild/$private_key_name"
printf "%s" "$public_key" > "/home/runner/.abuild/$public_key_name"

sudo cp -- "/home/runner/.abuild/$public_key_name" "/etc/apk/keys/$public_key_name"

# Make sure files/dirs owned by runner
sudo chown runner -R /source_repo
sudo chown runner -R /output_repo

if [ ! -f /source_repo/build_order.txt ]; then
  1>&2 echo "[ERROR] Please copy a copy of source repository in /source_repo"
  exit 1
fi

echo "[INFO] Starting to build"

while IFS="\n" read -u 10 -r line; do
  case $line in
    # Ignore comment and empty lines
    \#*) ;;
    "") ;;
    *) # Do the build
      echo "[INFO] Building $line"
      (cd "/source_repo/$line" && abuild -r -P /output_repo)
      ;;
  esac
done 10< /source_repo/build_order.txt

echo "[INFO] Build is done ^w^"
echo "[INFO] you can see the output in the /output_repo (inside container)"




