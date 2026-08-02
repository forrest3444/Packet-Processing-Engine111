#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET=${1:-all}
FUNC_SEEDS=${FUNC_SEEDS:-"1 23"}
PERF_SEEDS=${PERF_SEEDS:-"1"}
RUN_TIME=${RUN_TIME:-60s}
VERB=${VERB:-UVM_LOW}
MAKE_CMD=${MAKE_CMD:-make}
VERILATOR=${VERILATOR:-verilator}

BUILD_NAME=${BUILD_NAME:-four_fe_regression}
FILELIST=${FILELIST:-./script/filelist_sv.f}
TB_TOP=${TB_TOP:-tb_top_sv}
RTL_FILELIST=${RTL_FILELIST:-./rtl/filelist.f}
RTL_TOP=${RTL_TOP:-PPE_TOP_SV}

FUNCTIONAL_TESTS=(
    ppe_basic_test
    ppe_dep_loss_test
    ppe_rob32_wrap_test
    ppe_ingress_elastic_stress_test
)

PERFORMANCE_TESTS=(
    ppe_p0_perf_test
    ppe_uniform_random_delay_test
    ppe_load_mix_perf_test
)

case "${TARGET}" in
    functional|performance|all) ;;
    *)
        echo "Usage: $0 {functional|performance|all}" >&2
        exit 2
        ;;
esac

SUMMARY_DIR="${ROOT_DIR}/sim/regression/four_fe/${TARGET}"
SUMMARY_LOG="${SUMMARY_DIR}/summary.log"
BUILD_LOG="${SUMMARY_DIR}/build.log"
METRICS_LOG="${SUMMARY_DIR}/performance_metrics.log"
mkdir -p "${SUMMARY_DIR}"
: > "${SUMMARY_LOG}"
: > "${BUILD_LOG}"
: > "${METRICS_LOG}"

pass_count=0
fail_count=0

record_result() {
    local label=$1
    local run_log=$2
    local command_status=$3

    if [[ ${command_status} -eq 0 && -f "${run_log}" ]] &&
       grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "${run_log}" &&
       grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "${run_log}"; then
        printf 'PASS %s\n' "${label}" | tee -a "${SUMMARY_LOG}"
        pass_count=$((pass_count + 1))
    else
        printf 'FAIL %s log=%s\n' "${label}" "${run_log}" | tee -a "${SUMMARY_LOG}"
        fail_count=$((fail_count + 1))
    fi
}

run_uvm() {
    local category=$1
    local testname=$2
    local seed=$3
    local run_tag
    local run_log
    local label
    local status

    run_tag="four_fe_${category}_${testname}_seed_${seed}"
    label="${testname}/seed=${seed}"
    run_log="${ROOT_DIR}/sim/run/${run_tag}/log/run.log"

    printf 'RUN  %s\n' "${label}" | tee -a "${SUMMARY_LOG}"
    "${MAKE_CMD}" -C "${ROOT_DIR}" run \
        FILELIST="${FILELIST}" TB_TOP="${TB_TOP}" \
        BUILD_NAME="${BUILD_NAME}" TESTNAME="${testname}" SEED="${seed}" \
        RUN_TAG="${run_tag}" RUN_TIME="${RUN_TIME}" VERB="${VERB}"
    status=$?

    record_result "${label}" "${run_log}" "${status}"
    if [[ "${category}" == "performance" && -f "${run_log}" ]]; then
        grep -E '^UVM_INFO .*\[(P0_PERF|UNIFORM_PERF|LOAD_PERF)\]' "${run_log}" \
            >> "${METRICS_LOG}" || true
    fi
}

run_functional() {
    local testname
    local seed

    for testname in "${FUNCTIONAL_TESTS[@]}"; do
        for seed in ${FUNC_SEEDS}; do
            run_uvm functional "${testname}" "${seed}"
        done
    done
}

run_performance() {
    local testname
    local seed

    for seed in ${PERF_SEEDS}; do
        for testname in "${PERFORMANCE_TESTS[@]}"; do
            run_uvm performance "${testname}" "${seed}"
        done
    done
}

cd "${ROOT_DIR}"
echo "Building four-FE regression image: ${BUILD_NAME}" | tee -a "${SUMMARY_LOG}"
lint_cmd=("${VERILATOR}" --lint-only --Wall -Wno-fatal -Wno-DECLFILENAME
          --top-module "${RTL_TOP}" -f "${RTL_FILELIST}")
if ! "${lint_cmd[@]}" >> "${BUILD_LOG}" 2>&1; then
    echo "FAIL lint log=${BUILD_LOG}" | tee -a "${SUMMARY_LOG}"
    exit 1
fi
if ! "${MAKE_CMD}" elab FILELIST="${FILELIST}" TB_TOP="${TB_TOP}" \
    BUILD_NAME="${BUILD_NAME}" >> "${BUILD_LOG}" 2>&1; then
    echo "FAIL elab log=${BUILD_LOG}" | tee -a "${SUMMARY_LOG}"
    exit 1
fi

if [[ "${TARGET}" == "functional" || "${TARGET}" == "all" ]]; then
    run_functional
fi
if [[ "${TARGET}" == "performance" || "${TARGET}" == "all" ]]; then
    run_performance
fi

printf 'SUMMARY dut=four_fe target=%s pass=%d fail=%d\n' \
    "${TARGET}" "${pass_count}" "${fail_count}" \
    | tee -a "${SUMMARY_LOG}"
if [[ "${TARGET}" == "performance" || "${TARGET}" == "all" ]]; then
    echo "Performance metrics: ${METRICS_LOG}" | tee -a "${SUMMARY_LOG}"
fi

((fail_count == 0))
