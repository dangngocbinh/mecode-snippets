#!/bin/bash

# Test mapfile with multi-line string
test_data="outline_database-data
outline_https-portal-data
outline_storage-data"

echo "Using mapfile:"
mapfile -t arr < <(echo "$test_data")
echo "Array length: ${#arr[@]}"
for i in "${!arr[@]}"; do
    echo "  [$i] = '${arr[$i]}'"
done
