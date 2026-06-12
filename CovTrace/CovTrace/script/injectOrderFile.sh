#!/bin/bash

# This script find SYMBOL_SEARCH_STR from ORDER_FILE_1,
# then insert all content from ORDER_FILE_2 after SYMBOL_SEARCH_STR.
# If SYMBOL_SEARCH_STR does not exist in ORDER_FILE_1,
# ORDER_FILE_2 is appended after ORDER_FILE_1.

ORDER_FILE_1=$1
ORDER_FILE_2=$2
OUTPUT_PATH=$3
SYMBOL_SEARCH_STR=$4

# Clean all comments from the order file
CLEAN_CONTENT=$(mktemp)
grep -v "^#" "$ORDER_FILE_2" > "$CLEAN_CONTENT"

if grep -q "$SYMBOL_SEARCH_STR" "$ORDER_FILE_1"; then
    sed "/$SYMBOL_SEARCH_STR/r $CLEAN_CONTENT" "$ORDER_FILE_1" > "$OUTPUT_PATH"
else
    cat "$ORDER_FILE_1" "$CLEAN_CONTENT" > "$OUTPUT_PATH"
fi
