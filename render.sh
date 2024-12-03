#!/bin/bash

rm -r graphs/*.png

for file in graphs/*.dot; do
    [ -e "$file" ] || continue
    basename="${file%.dot}"
    output="${basename}.png"
    dot "$file" -Tpng -o "$output"
    echo "Converted $file to $output"
done
