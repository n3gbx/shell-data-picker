#! /bin/bash

names=$(awk 'BEGIN {FS = ","} FNR > 1 { print $2 }' "./demo.csv" | tr '\n' ';') 
picked_names=$(./ui_picker.sh -d "$names" -h "Employees" -c 5)

echo "Employees picked:"
echo "$picked_names"
