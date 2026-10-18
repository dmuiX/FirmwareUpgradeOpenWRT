#!/bin/sh
set -e

RELEASE_API="https://api.github.com/repos/jerrykuku/luci-theme-argon/releases/latest"
NON_INTERACTIVE=0
RELEASE_JSON=
THEME_FILE=
CONFIG_FILE=

if [ "${1:-}" = "--non-interactive" ]; then
  NON_INTERACTIVE=1
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--non-interactive]" >&2
  exit 2
fi

cleanup() {
  [ -z "$RELEASE_JSON" ] || rm -f "$RELEASE_JSON"
  [ -z "$THEME_FILE" ] || rm -f "/tmp/$THEME_FILE"
  [ -z "$CONFIG_FILE" ] || rm -f "/tmp/$CONFIG_FILE"
}
trap cleanup EXIT

release_asset_url() {
  jsonfilter -i "$RELEASE_JSON" -e "$1"
}

prompt_for_url() {
  prompt=$1
  default_url=$2

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    printf '%s\n' "$default_url"
    return
  fi

  printf "%s [%s]: " "$prompt" "$default_url" >&2
  read -r selected_url
  printf '%s\n' "${selected_url:-$default_url}"
}

validate_url() {
  url=$1
  pattern=$2

  # The caller supplies an intentional shell glob restricted to this repository.
  # shellcheck disable=SC2254
  case "$url" in
    $pattern) ;;
    *)
      echo "Refusing unexpected release asset URL: $url" >&2
      exit 1
      ;;
  esac
}

command -v jsonfilter >/dev/null 2>&1 || {
  echo "jsonfilter is required to resolve the latest Argon release" >&2
  exit 1
}

cd /tmp
RELEASE_JSON="/tmp/argon-release.$$"
wget -q -O "$RELEASE_JSON" "$RELEASE_API" || {
  echo "Could not query the latest Argon release" >&2
  exit 1
}

LATEST_THEME_LINK=$(release_asset_url '@.assets[@.name~"^luci-theme-argon-[0-9].*\\.apk$"] .browser_download_url')
[ -n "$LATEST_THEME_LINK" ] || {
  echo "The latest release has no Argon theme APK" >&2
  exit 1
}

THEME_LINK=$(prompt_for_url "Argon theme download link" "$LATEST_THEME_LINK")
validate_url "$THEME_LINK" 'https://github.com/jerrykuku/luci-theme-argon/releases/download/*/luci-theme-argon-*.apk'
THEME_FILE=$(basename "$THEME_LINK")
LATEST_VERSION=${THEME_FILE#luci-theme-argon-}
LATEST_VERSION=${LATEST_VERSION%.apk}
FORCE_THEME_INSTALL=0

if apk info -e luci-app-argon-config >/dev/null 2>&1; then
  LATEST_CONFIG_LINK=$(release_asset_url '@.assets[@.name~"^luci-app-argon-config-[0-9].*\\.apk$"] .browser_download_url')
  [ -n "$LATEST_CONFIG_LINK" ] || {
    echo "The latest release has no Argon configuration migration APK" >&2
    exit 1
  }

  echo "Existing Argon configuration detected; installing the migration package first."
  CONFIG_LINK=$(prompt_for_url "Argon config migration download link" "$LATEST_CONFIG_LINK")
  validate_url "$CONFIG_LINK" 'https://github.com/jerrykuku/luci-theme-argon/releases/download/*/luci-app-argon-config-*.apk'
  CONFIG_FILE=$(basename "$CONFIG_LINK")

  wget -O "$CONFIG_FILE" "$CONFIG_LINK" || { echo "Download failed"; exit 1; }
  apk add --allow-untrusted "./$CONFIG_FILE" || { echo "Migration failed"; exit 1; }
  FORCE_THEME_INSTALL=1
  echo "Argon configuration migrated."
elif grep -q '^luci-app-argon-config' /etc/apk/world 2>/dev/null; then
  # A firmware backup can restore a world entry without restoring the package.
  echo "Removing stale luci-app-argon-config entry from /etc/apk/world."
  sed -i '/^luci-app-argon-config/d' /etc/apk/world
fi

INSTALLED_VERSION=$(apk query --fields version --format yaml --installed luci-theme-argon 2>/dev/null \
  | sed -n 's/^- version: //p')

if [ "$FORCE_THEME_INSTALL" -eq 0 ] && [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
  echo "LuCI Argon $INSTALLED_VERSION is already the latest release."
else
  echo "Installing LuCI Argon $LATEST_VERSION${INSTALLED_VERSION:+ (currently $INSTALLED_VERSION)}."
  wget -O "$THEME_FILE" "$THEME_LINK" || { echo "Download failed"; exit 1; }
  apk add --allow-untrusted "./$THEME_FILE" || { echo "Install failed"; exit 1; }

  if ! apk info -e luci-theme-argon >/dev/null 2>&1; then
    echo "Install failed: luci-theme-argon is not installed"
    exit 1
  fi
  echo "LuCI Argon theme and integrated configuration UI installed."
fi

if [ "$(uci get luci.main.mediaurlbase 2>/dev/null)" != "/luci-static/argon" ]; then
  uci set luci.main.mediaurlbase='/luci-static/argon'
  uci commit luci
  /etc/init.d/uhttpd restart || echo "Warning: uhttpd restart failed"
  echo "Argon theme activated and uhttpd restarted."
else
  echo "Argon theme already active."
fi
