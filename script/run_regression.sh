#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET=${1:-all}
DUT=${DUT:-sv}
FUNC_SEEDS=${FUNC_SEEDS:-"1 23"}
PERF_SEEDS=${PERF_SEEDS:-"1"}
RUN_TIME=${RUN_TIME:-60s}
VERB=${VERB:-UVM_LOW}
MAKE_CMD=${MAKE_CMD:-make}
VERILATOR=${VERILATOR:-verilator}

case "${DUT}" in
    sv)
        BUILD_NAME=${BUILD_NAME:-sv_regression}
        FILELIST=${FILELIST:-./script/filelist_sv.f}
        TB_TOP=${TB_TOP:-tb_top_sv}
        RTL_FILELIST=${RTL_FILELIST:-./rtl-sv/filelist.f}
        RTL_TOP=${RTL_TOP:-ppe_top_sv}
        ;;
    single_fe)
        BUILD_NAME=${BUILD_NAME:-single_fe_regression}
        FILELIST=${FILELIST:-./script/filelist_single_fe.f}
        TB_TOP=${TB_TOP:-tb_top_single_fe}
        RTL_FILELIST=${RTL_FILELIST:-./rtl-sv/filelist_single_fe.f}
        RTL_TOP=${RTL_TOP:-ppe_single_fe_inorder}
        ;;
    legacy)
        BUILD_NAME=${BUILD_NAME:-legacy_regression}
        FILELIST=${FILELIST:-./script/filelist.f}
        TB_TOP=${TB_TOP:-tb_top}
        RTL_FILELIST=${RTL_FILELIST:-./script/rtl_filelist.f}
        RTL_TOP=${RTL_TOP:-ppe_top}
        ;;
    *)
        echo "DUT must be 'sv', 'single_fe', or 'legacy'" >&2
        exit 2
        ;;
esac

FUNCTIONAL_TESTS=(
    ppe_basic_test
    ppe_fe_pipeline_test
    ppe_dep_loss_test
    ppe_rob32_wrap_test
    ppe_ingress_elastic_stress_test
)

PERFORMANCE_CASES=(
    P1_DELAY1
    P1_DELAY2
    P1_DELAY3
    P2_MIXED_DELAY
    P3_LANES1
    P3_LANES2
    P3_LANES3
    P4_DEP1_D0
    P4_DEP1_D3
    P5_DEP2
    P5_DEP4
    P5_DEP7
    P6_DEP25
    P6_DEP50
    P6_DEP75
)

case "${TARGET}" in
    functional|performance|all) ;;
    *)
        echo "Usage: $0 {functional|performance|all}" >&2
        exit 2
        ;;
esac

SUMMARY_DIR="${ROOT_DIR}/sim/regression/${DUT}/${TARGET}"
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
    local case_name=${4:-}
    local run_tag
    local run_log
    local label
    local status

    if [[ -n "${case_name}" ]]; then
        run_tag="${DUT}_${category}_${case_name}_seed_${seed}"
        label="${testname}/${case_name}/seed=${seed}"
    else
        run_tag="${DUT}_${category}_${testname}_seed_${seed}"
        label="${testname}/seed=${seed}"
    fi
    run_log="${ROOT_DIR}/sim/run/${run_tag}/log/run.log"

    printf 'RUN  %s\n' "${label}" | tee -a "${SUMMARY_LOG}"
    if [[ -n "${case_name}" ]]; then
        "${MAKE_CMD}" -C "${ROOT_DIR}" run \
            FILELIST="${FILELIST}" TB_TOP="${TB_TOP}" \
            BUILD_NAME="${BUILD_NAME}" TESTNAME="${testname}" SEED="${seed}" \
            RUN_TAG="${run_tag}" RUN_TIME="${RUN_TIME}" VERB="${VERB}" \
            USER_SIM_OPTS="+PERF_CASE=${case_name}"
        status=$?
    else
        "${MAKE_CMD}" -C "${ROOT_DIR}" run \
            FILELIST="${FILELIST}" TB_TOP="${TB_TOP}" \
            BUILD_NAME="${BUILD_NAME}" TESTNAME="${testname}" SEED="${seed}" \
            RUN_TAG="${run_tag}" RUN_TIME="${RUN_TIME}" VERB="${VERB}"
        status=$?
    fi

    record_result "${label}" "${run_log}" "${status}"
    if [[ "${category}" == "performance" && -f "${run_log}" ]]; then
        grep -E '^UVM_INFO .*\[(P0_PERF|PERF_METRIC|LOAD_PERF)\]' "${run_log}" \
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
    local case_name
    local seed

    for seed in ${PERF_SEEDS}; do
        if [[ "${DUT}" == "single_fe" ]]; then
            run_uvm performance ppe_single_fe_p0_perf_test "${seed}"
        else
            run_uvm performance ppe_p0_perf_test "${seed}"
        fi
        for case_name in "${PERFORMANCE_CASES[@]}"; do
            run_uvm performance ppe_perf_test "${seed}" "${case_name}"
        done
        run_uvm performance ppe_load_mix_perf_test "${seed}"
    done
}

cd "${ROOT_DIR}"
echo "Building ${DUT} regression image: ${BUILD_NAME}" | tee -a "${SUMMARY_LOG}"
if [[ "${DUT}" == "sv" || "${DUT}" == "single_fe" ]]; then
    lint_cmd=("${VERILATOR}" --lint-only --Wall -Wno-fatal
              --top-module "${RTL_TOP}" -f "${RTL_FILELIST}")
else
    lint_cmd=("${MAKE_CMD}" lint RTL_FILELIST="${RTL_FILELIST}")
fi
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

printf 'SUMMARY dut=%s target=%s pass=%d fail=%d\n' \
    "${DUT}" "${TARGET}" "${pass_count}" "${fail_count}" \
    | tee -a "${SUMMARY_LOG}"
if [[ "${TARGET}" == "performance" || "${TARGET}" == "all" ]]; then
    echo "Performance metrics: ${METRICS_LOG}" | tee -a "${SUMMARY_LOG}"
fi

((fail_count == 0))
