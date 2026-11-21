#!/bin/zsh
# Interactive XCTest automation. Ask before running: it interrupts VoiceOver.
set -u
set -o pipefail
if [[ $# -eq 0 ]]; then
    print -r -- 'Usage: ui-tests.sh BrainDumpUITests/Class[/test] [...]' >&2
    exit 2
fi
for test_filter in "$@"; do
    if [[ "$test_filter" != BrainDumpUITests/* ]]; then
        print -r -- "Invalid UI-test filter: $test_filter" >&2
        exit 2
    fi
done
project_root=${0:A:h:h}
cd "$project_root" || exit 1
args=(test -project BrainDump.xcodeproj -scheme BrainDumpUITests -testPlan BrainDumpUITests -configuration Debug -parallel-testing-enabled NO)
for test_filter in "$@"; do
    args+=("-only-testing:$test_filter")
done
case "$(uname -m)" in
    arm64) args+=(-destination 'platform=macOS,arch=arm64') ;;
    x86_64) args+=(-destination 'platform=macOS,arch=x86_64') ;;
    *) exit 2 ;;
esac
ui_test_log=$(mktemp "${TMPDIR:-/tmp}/braindump-ui-tests.XXXXXX") || exit 1
ui_result_bundle="${ui_test_log}.xcresult"
args+=(-resultBundlePath "$ui_result_bundle")
xcodebuild "${args[@]}" 2>&1 | tee "$ui_test_log" | ./.bin/xcsift -f toon -w --exit-on-failure
ui_test_status=$?
printf '\nRaw UI-test log: %s\nResult bundle: %s\n' "$ui_test_log" "$ui_result_bundle"
exit "$ui_test_status"
