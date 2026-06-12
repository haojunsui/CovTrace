#!/bin/sh

/bin/mkdir -p "${BUILT_PRODUCTS_DIR}"

XCODE_PATH=`/usr/bin/xcode-select -print-path`
/bin/cp -R "${XCODE_PATH}/../SharedFrameworks/CoreSymbolicationDT.framework" "${BUILT_PRODUCTS_DIR}"
