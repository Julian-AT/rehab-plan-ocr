#!/bin/sh
# Finder/File Provider metadata is not bundle content and can reject codesign.
# Only touch the product being signed; never follow links into source/assets.
set -eu
[ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] || exit 0
: "${TARGET_BUILD_DIR:?Missing target build directory}"
: "${FULL_PRODUCT_NAME:?Missing product name}"
case "$FULL_PRODUCT_NAME" in
  */*)
    echo 'Expected a product basename' >&2
    exit 1
    ;;
  *.app | *.appex) ;;
  *)
    echo 'Expected an app or extension product' >&2
    exit 1
    ;;
esac
product="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
[ -d "$product" ] && [ ! -L "$product" ] || {
  echo 'Expected an actual built product directory' >&2
  exit 1
}
/usr/bin/xattr -crs "$product"
