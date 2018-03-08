#!/bin/bash

# quick & dirty deploy onto local host
target=/app/admin-scripts/bin

if [ -d $target ]; then
    rm -rf $target/*
    # the cp flattens out symlinks, we desire this in this case
    cp bin/* $target
else
    echo "Cannot find deploy target folder: $d"
    exit 1
fi
