#!/bin/zsh
# usage: .improve/golden.sh <tag>  -> renders into .improve/golden/<tag>
set -e
W=${0:A:h:h}
T=$W/Widgets/CasioClockWidget/Tests/CasioClockWidgetTests/GoldenRenderTests.swift
cp $W/.improve/GoldenRenderTests.swift $T
trap "rm -f $T" EXIT
rm -rf $W/.improve/golden/$1
cd $W/Widgets/CasioClockWidget && GOLDEN_DIR=$W/.improve/golden/$1 swift test --scratch-path ~/DevTemp/smarttube/derived-data/casio-improve --filter goldenRenders 2>&1 | grep -E "error:|✘|Test run"
ls $W/.improve/golden/$1 | wc -l
