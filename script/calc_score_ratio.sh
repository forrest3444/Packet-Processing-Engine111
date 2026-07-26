#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 8 ]]; then
    echo "usage: $0 BASE_CYCLES BASE_FREQ_MHZ BASE_AREA BASE_POWER CAND_CYCLES CAND_FREQ_MHZ CAND_AREA CAND_POWER" >&2
    exit 2
fi

awk \
    -v bc="$1" -v bf="$2" -v ba="$3" -v bp="$4" \
    -v cc="$5" -v cf="$6" -v ca="$7" -v cp="$8" '
BEGIN {
    if (bc <= 0 || bf <= 0 || ba <= 0 || bp <= 0 ||
        cc <= 0 || cf <= 0 || ca <= 0 || cp <= 0) {
        print "error: all inputs must be positive" > "/dev/stderr"
        exit 2
    }

    base_time_us = bc / bf
    cand_time_us = cc / cf
    perf_ratio   = base_time_us / cand_time_us
    area_ratio   = ba / ca
    power_ratio  = bp / cp
    score_ratio  = perf_ratio * perf_ratio \
                 * sqrt(area_ratio) * sqrt(power_ratio)

    printf "base_time_us=%.9f\n", base_time_us
    printf "candidate_time_us=%.9f\n", cand_time_us
    printf "performance_ratio=%.9f\n", perf_ratio
    printf "area_ratio=%.9f\n", area_ratio
    printf "power_ratio=%.9f\n", power_ratio
    printf "score_ratio=%.9f\n", score_ratio
}'
