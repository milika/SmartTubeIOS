# SmartTube task runner. `just` lists recipes. Every recipe is safe to run from any cwd.
set shell := ["bash", "-euo", "pipefail", "-c"]

root      := justfile_directory()
workspace := root + "/SmartTube.xcworkspace"
project   := root + "/SmartTubeApp/SmartTubeApp.xcodeproj"
package   := root + "/SmartTubeIOS"
derived   := env_var_or_default("SMARTTUBE_DERIVED_DATA", env_var("HOME") + "/DevTemp/smarttube/derived-data/xcode")
# Single source of truth for the target simulator. Override: `just sim="iPhone 17" test-ui`.
sim       := env_var_or_default("SMARTTUBE_SIM", "iPhone 17")
tv_sim    := env_var_or_default("SMARTTUBE_TV_SIM", "Apple TV")
workers   := "3"   # 16 GB Mac Mini ceiling; 5 stalls clone boot (docs/running-tests.md)

default:
    @just --list

# --- quality gates ---------------------------------------------------------
# Extension sources live outside SmartTubeApp/Sources, so every Swift folder is listed.
format:
    xcrun swift-format format --in-place --recursive --configuration {{root}}/.swift-format {{package}}/Sources {{package}}/Tests {{root}}/SmartTubeApp/Sources {{root}}/SmartTubeApp/UITests "{{root}}/SmartTubeApp/Smart Tube" {{root}}/SmartTubeApp/ShareExtension {{root}}/SmartTubeApp/SafariExtension {{root}}/SmartTubeApp/DownloadWidget

format-check:
    xcrun swift-format lint --strict --recursive --configuration {{root}}/.swift-format {{package}}/Sources {{package}}/Tests {{root}}/SmartTubeApp/Sources {{root}}/SmartTubeApp/UITests "{{root}}/SmartTubeApp/Smart Tube" {{root}}/SmartTubeApp/ShareExtension {{root}}/SmartTubeApp/SafariExtension {{root}}/SmartTubeApp/DownloadWidget

lint:
    cd {{root}} && swiftlint lint --strict --baseline .swiftlint.baseline --config .swiftlint.yml

lint-baseline:
    cd {{root}} && swiftlint lint --write-baseline .swiftlint.baseline --config .swiftlint.yml || true

secrets-check:
    cd {{root}} && scripts/check-no-secrets.sh

# Fails if signing/bundle identity was duplicated outside Config/Base.xcconfig
# (Xcode's Signing pane writes DEVELOPMENT_TEAM into project.pbxproj behind your back).
identity-check:
    cd {{root}} && scripts/check-identity.sh

# Print the team, bundle IDs, App Group and version every target will actually build with.
# Use this to confirm a Config/Secrets.xcconfig override took effect.
identity:
    @for t in SmartTube "Smart Tube" SmartTubeDownloadWidget SmartTubeShareExtension; do \
        echo "== $t"; \
        xcodebuild -project {{project}} -target "$t" -configuration Debug -showBuildSettings 2>/dev/null \
            | grep -E "^ *(PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|SMARTTUBE_APP_GROUP_ID|SMARTTUBE_UBIQUITY_KVSTORE_ID|MARKETING_VERSION|CURRENT_PROJECT_VERSION) = "; \
    done

doc-links:
    cd {{root}} && scripts/check-doc-links.sh

# --- build & test ------------------------------------------------------------
build:
    xcodebuild build -workspace {{workspace}} -scheme SmartTube -destination "platform=iOS Simulator,name={{sim}}" -derivedDataPath {{derived}} CODE_SIGNING_ALLOWED=NO -quiet

build-tvos:
    xcodebuild build -workspace {{workspace}} -scheme "Smart Tube" -destination "platform=tvOS Simulator,name={{tv_sim}}" -derivedDataPath {{derived}} CODE_SIGNING_ALLOWED=NO -quiet

test-unit:
    cd {{package}} && swift test --parallel 2>&1 | tail -30

# filter: `just test-unit-filter HLSManifestParserTests`
test-unit-filter name:
    cd {{package}} && swift test --filter {{name}} 2>&1 | tail -40

# temporary until WS3-T3.4 adds the Smoke/Live test plans
test-ui-legacy:
    mkdir -p "$HOME/DevTemp/smarttube/logs"
    xcodebuild test -workspace {{workspace}} -scheme SmartTube -destination "platform=iOS Simulator,name={{sim}}" -derivedDataPath {{derived}} -parallel-testing-enabled YES -maximum-parallel-testing-workers {{workers}} -only-testing:SmartTubeUITests 2>&1 | tee $HOME/DevTemp/smarttube/logs/smarttube-parallel-test.log | grep -E "Test Case|TEST SUCCEEDED|TEST FAILED|error:" | tail -40

test-smoke:
    mkdir -p "$HOME/DevTemp/smarttube/logs"
    xcodebuild test -workspace {{workspace}} -scheme SmartTube -testPlan Smoke -destination "platform=iOS Simulator,name={{sim}}" -derivedDataPath {{derived}} -parallel-testing-enabled YES -maximum-parallel-testing-workers {{workers}} -resultBundlePath $HOME/DevTemp/smarttube/logs/smarttube-smoke.xcresult CODE_SIGNING_ALLOWED=NO 2>&1 | tee $HOME/DevTemp/smarttube/logs/smarttube-smoke.log | grep -E "Test Case|TEST SUCCEEDED|TEST FAILED|error:" | tail -40

test-ui:
    mkdir -p "$HOME/DevTemp/smarttube/logs"
    xcodebuild test -workspace {{workspace}} -scheme SmartTube -testPlan Live -destination "platform=iOS Simulator,name={{sim}}" -derivedDataPath {{derived}} -parallel-testing-enabled YES -maximum-parallel-testing-workers {{workers}} -resultBundlePath $HOME/DevTemp/smarttube/logs/smarttube-live.xcresult 2>&1 | tee $HOME/DevTemp/smarttube/logs/smarttube-live.log | grep -E "Test Case|TEST SUCCEEDED|TEST FAILED|error:" | tail -60

# run one UI test: `just test-ui-one SmartTubeUITests/PlayerControlsUITests/testPlayPause`
test-ui-one id:
    xcodebuild test -workspace {{workspace}} -scheme SmartTube -destination "platform=iOS Simulator,name={{sim}}" -derivedDataPath {{derived}} -only-testing:{{id}} 2>&1 | grep -E "Test Case|TEST SUCCEEDED|TEST FAILED|error:" | tail -20

ci: secrets-check identity-check doc-links format-check lint test-unit
    @echo "CI gate passed"

# regenerate the Unreleased section of CHANGELOG.md from Conventional Commits since the last tag
changelog:
    git-cliff --config {{root}}/cliff.toml --unreleased --prepend {{root}}/CHANGELOG.md

# --- metrics (ratchet, see docs/adr/0001) -------------------------------------
metrics:
    @echo "largest files:"; find {{package}}/Sources -name '*.swift' -exec wc -l {} + | sort -rn | head -11
    @echo "AGENTS.md bytes/lines:"; wc -c -l {{root}}/AGENTS.md
    @echo "a11y literals:"; grep -rho 'accessibilityIdentifier("' --include='*.swift' {{package}}/Sources {{root}}/SmartTubeApp/Sources | wc -l
    @echo "sleep( in UITests:"; grep -rhoE '\bsleep\(' {{root}}/SmartTubeApp/UITests | wc -l
    @echo "XCTSkip:"; grep -rho 'XCTSkip' {{root}}/SmartTubeApp/UITests | wc -l
    @echo ".shared reads in Views:"; grep -rho '\.shared\b' --include='*.swift' {{package}}/Sources/SmartTubeIOS/Views | wc -l
    @echo "mirror tests:"; grep -rli 'mirror' {{package}}/Tests | wc -l
