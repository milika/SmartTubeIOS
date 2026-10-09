#!/bin/zsh
# Full gate set vs baseline. usage: .improve/verify.sh <tag>
W=${0:A:h:h}; P=$W/Widgets/CasioClockWidget; I=$W/.improve; S=~/DevTemp/smarttube/derived-data/casio-improve
G=/Users/milikadelic/.claude/plugins/cache/milika/code-improvement/1.4.0/skills/improve-codebase/scripts/gate.py
fail=0
(cd $P && swift build --scratch-path $S -Xswiftc -warnings-as-errors > $I/$1-build.log 2>&1) || { echo "BUILD(macOS, warnings-as-errors) FAILED"; fail=1; }
(cd $P && swift test --scratch-path $S > $I/$1-test.log 2>&1); te=$?
grep -E "✘ Test \"" $I/$1-test.log | sed 's/ recorded.*//; s/ failed after.*//' | sort -u > $I/$1-failing.txt
echo "tests: $(grep 'Test run with' $I/$1-test.log) exit $te; failing: $(wc -l < $I/$1-failing.txt | tr -d ' ')"
[[ -s $I/$1-failing.txt || $te -ne 0 ]] && { cat $I/$1-failing.txt; fail=1; }
for p in "iOS Simulator" "watchOS Simulator"; do
  (cd $P && xcodebuild -scheme CasioClockWidget -destination "generic/platform=$p" -derivedDataPath ~/DevTemp/smarttube/derived-data/casio-improve-xc build > "$I/$1-xc-${p// /}.log" 2>&1) || { echo "$p BUILD FAILED"; fail=1; }
  echo "$p: $(tail -1 "$I/$1-xc-${p// /}.log" | tr -d '*') warnings $(grep -c 'warning:' "$I/$1-xc-${p// /}.log")"
done
cd $W
xcrun swift-format lint --strict --recursive --configuration .swift-format $P/Sources $P/Tests > $I/$1-format.log 2>&1
sed -i '' "s#^$W/##" $I/$1-format.log
swiftlint lint --config $I/swiftlint-casio.yml 2>/dev/null | sed "s#^$W/##" > $I/$1-lint.log
cat $I/$1-format.log $I/$1-lint.log > $I/$1-diags.log
echo "diags: format $(wc -l < $I/$1-format.log | tr -d ' '), lint $(wc -l < $I/$1-lint.log | tr -d ' ')"
python3 $G diags $I/$1-diags.log --baseline $I/baseline-diags.txt --git-base 0aeeee8f > $I/$1-diagcmp.log; [[ $? -ne 0 ]] && fail=1; tail -4 $I/$1-diagcmp.log
$I/golden.sh $1 > /dev/null || fail=1; python3 $I/goldcmp.py $I/golden/base $I/golden/$1 3 > $I/$1-golden.log; [[ $? -ne 0 ]] && fail=1; tail -6 $I/$1-golden.log
[[ $fail -eq 0 ]] && echo "ALL GATES GREEN" || echo "GATES RED"
