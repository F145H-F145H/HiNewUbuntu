#!/bin/bash
# Script to install packages listed in ./config/packages.list using apt

PACKAGE_LIST="./config/packages.list"

if [[ ! -f "$PACKAGE_LIST" ]]; then
    echo "Error: Package list file '$PACKAGE_LIST' not found."
    exit 1
fi

while IFS= read -r package || [[ -n "$package" ]]; do
    if [[ -z "$package" || "$package" =~ ^# ]]; then
        continue
    fi
    echo "Installing $package..."
    if ! sudo apt install -y "$package"; then
        echo "Error: Failed to install $package"
        exit 1
    fi
done < "$PACKAGE_LIST"

echo "Done apt install packages"