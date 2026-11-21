#!/bin/zsh
# Fixed, reviewable build/test entry point. Never launches BrainDump or UI tests.
set -u
set -o pipefail

usage() {
    print -r -- 'Usage: verify.sh build [Debug|Release] | build-ui-tests | test [BrainDumpTests/Suite[/test]]'
}

if [[ $# -eq 1 && "$1" == '--help' ]]; then
    usage
    exit 0
fi
if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 2
fi

project_root=${0:A:h:h}
case "$1" in
    build-ui-tests)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        args=(build-for-testing -project BrainDump.xcodeproj -scheme BrainDumpUITests -testPlan BrainDumpUITests -configuration Debug)
        ;;
    build)
        configuration=${2:-Debug}
        if [[ "$configuration" != Debug && "$configuration" != Release ]]; then
            usage >&2
            exit 2
        fi
        args=(build -project BrainDump.xcodeproj -scheme BrainDump -configuration "$configuration")
        ;;
    test)
        args=(test -project BrainDump.xcodeproj -scheme BrainDumpTests -testPlan BrainDumpTests -configuration Debug)
        if [[ $# -eq 2 ]]; then
            if [[ "$2" != BrainDumpTests/* ]]; then
                usage >&2
                exit 2
            fi
            args+=("-only-testing:$2")
        fi
        ;;
    *) usage >&2; exit 2 ;;
esac

case "$(uname -m)" in
    arm64) args+=(-destination 'platform=macOS,arch=arm64') ;;
    x86_64) args+=(-destination 'platform=macOS,arch=x86_64') ;;
    *) print -r -- 'Unsupported host architecture.' >&2; exit 2 ;;
esac

cd "$project_root" || exit 1
if [[ ! -x ./.bin/xcsift ]]; then
    print -r -- 'Missing local .bin/xcsift; follow AI-Testing-Workflow.md setup.' >&2
    exit 1
fi
verification_log=$(mktemp "${TMPDIR:-/tmp}/braindump-verification.XXXXXX") || exit 1
xcodebuild "${args[@]}" 2>&1 | tee "$verification_log" | sed 's/\*\* TEST BUILD SUCCEEDED \*\*/** BUILD SUCCEEDED **/; s/\*\* TEST BUILD FAILED \*\*/** BUILD FAILED **/' | ./.bin/xcsift -f toon -w --exit-on-failure
verification_status=$?
printf '\nRaw log: %s\n' "$verification_log"
exit "$verification_status"
