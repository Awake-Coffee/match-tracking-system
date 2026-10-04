#!/usr/bin/env bash
# Vercel build: installs Flutter and builds the web app into app/build/web.
#
# Vercel has no Flutter, and the Supabase settings are compile-time
# --dart-define values, so the project's environment variables only reach the
# app if they are passed to `flutter build` here.
set -euo pipefail

FLUTTER_VERSION=3.47.6 # matches app/.metadata
FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675

root=$(cd "$(dirname "$0")/.." && pwd)
sdk_dir=${FLUTTER_HOME:-$root/.flutter}

if [ ! -x "$sdk_dir/flutter/bin/flutter" ]; then
  archive=flutter_linux_${FLUTTER_VERSION}-stable.tar.xz
  echo "Downloading Flutter $FLUTTER_VERSION"
  mkdir -p "$sdk_dir"
  curl -fsSL -o "$sdk_dir/$archive" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$archive"
  echo "$FLUTTER_SHA256  $sdk_dir/$archive" | sha256sum -c -
  tar -xJf "$sdk_dir/$archive" -C "$sdk_dir"
  rm "$sdk_dir/$archive"
fi

# The SDK is a git checkout owned by the archive's uid; the build runs as root.
git config --global --add safe.directory "$sdk_dir/flutter"
export PATH="$sdk_dir/flutter/bin:$PATH"
flutter config --no-analytics >/dev/null
flutter --version

supabase_url=${SUPABASE_URL:-}
supabase_key=${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-}}
# A URL without a scheme (e.g. a redacted placeholder) builds fine but sends
# every auth call to the app's own host.
if [[ $supabase_url != https://* ]] || [ -z "$supabase_key" ]; then
  if [ "${VERCEL_ENV:-}" = production ]; then
    echo "SUPABASE_URL (https://...) and SUPABASE_PUBLISHABLE_KEY must be set for production builds." >&2
    exit 1
  fi
  echo "Supabase settings missing; building in demo mode."
fi

cd "$root/app"
flutter build web --release \
  --dart-define=SUPABASE_URL="$supabase_url" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$supabase_key"
