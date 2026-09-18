# Kimi K2.6 H200x2 SGLang Flag Test Plan

Goal: reduce TTFT as much as possible for Kimi K2.6 on `h200x2`, even if some candidates trade away throughput or stability. Rerun the benchmark script from the parent scripts directory, defaulting to `${repo_root}/../tools/benchmarks/benchmark.py`, with the same fixed-seed benchmark flags:

```bash
--num-prompts 100 --concurrency 2 --timeout 3600 --seed 52
```

Every test is based on repo-root `04_launch.sh` behavior:

- uses repo-root `envs/kimi_k26/h200x2.env`
- uses `--kt-expert-placement-strategy frequency`
- uses the latest repo-root `experts/kimi_k26/h200x2/02/expert_distribution_recorder_*.pt`
- uses experts recorded from the same `--seed 52` benchmark workload
- keeps `--disable-radix-cache`
- keeps `--disable-chunked-prefix-cache`
- writes the full resolved SGLang engine command and benchmark output to repo-root `results/kimi_k26/h200x2/tests/testNNN.txt`

Do not edit installed packages. Do not edit `04_launch.sh` for this sweep.

Portability notes:

- Keep the scripts in `tools/` beside this markdown file. They derive `plan_dir` from their own location and default `repo_root` to two directories above this file; override `KT_REPO_ROOT` only if you move the plan bundle somewhere else.
- Override `KT_EXPERTS_PATH`, `KT_PYTHON_ENV`, `KT_BENCHMARK_PATH`, `KT_BENCHMARK_MODEL`, `RESULTS_DIR`, `KT_HOST`, `KT_PORT`, `KT_API_KEY`, or `KT_PLAN_FILE` when moving this runner to another system.
- `tools/kimi_k26_seeded_workflow.sh` recreates wiped repo-root `experts/.../01` and `experts/.../02` directories, records fixed-seed experts with repo-root `02_record.sh` and `03_record.sh`, combines them, then runs the 100+ seeded tests below.
- Benchmark stdout/stderr is written live to `/tmp/*benchmark.live.log`; `record*.txt` and `testNNN.txt` are written after benchmark completion with commands plus the final `RESULTS` section.
- The runner skips only fully successful results: `BENCHMARK_EXIT_CODE: 0` and `Successful requests: 100/100`.
- Failed or partial result files are archived with `.previous_YYYYmmddTHHMMSSZ` and retried up to `MAX_TEST_ATTEMPTS` times, default `3`.
- Starting with `test025` by default, each new test sends a best-effort Discord notification as `Starting testNNN | ...` with a compact explanation of chunk size, threshold, memory fraction, expert count, CPU/deferred settings, and notable SGLang flags. Override `KT_HERMES_START_FROM` to change the first test that emits start notifications.
- Successful tests send best-effort Discord notifications with `hermes send --to discord`: one message for the completed test and one for the current balanced best. Balanced best first keeps mean TTFT within `max(250ms, 0.5%)` of the fastest successful run, then prefers higher output tokens/sec, lower P95, lower median, and lower mean TTFT. Set `KT_HERMES_NOTIFY=0` to disable this on systems without Hermes configured.
- Failed test attempts also send best-effort Discord notifications as `Fail 1/3 testNNN`, `Fail 2/3 testNNN`, and `Fail 3/3 testNNN`. After the final failed attempt, the runner records the failed result and continues to the next test instead of stopping the sweep.
- By default, `test026+` is dynamic: `tools/kimi_k26_seeded_workflow.sh` ranks successful `test001-test025` results, records the top `KT_DYNAMIC_POST25_TOP_N=3` anchors, runs overlay probes only on the best `KT_DYNAMIC_POST25_OVERLAY_TOP_N=1` anchor, then starts the deeper top-anchor probes immediately after that block. With the default 16 overlay probes, the deep-dive tests start at `test042` instead of repeating the same overlay set for the 2nd and 3rd anchors. This keeps rented-compute runs cheaper while still preserving the top-3 anchor metadata. Set `KT_DYNAMIC_POST25_OVERLAY_TOP_N=3` to restore the old repeat-all-three behavior, or `KT_DYNAMIC_POST25=0` to use the static `run_test 026+` rows below instead.
- Dynamic post-25 anchor selection writes repo-root `results/kimi_k26/h200x2/tests/dynamic_post25_anchors_seed52.tsv` with the exact source tests, chunk sizes, thresholds, and TTFT metrics used.
- Startup cleanup waits for old SGLang child processes and GPU allocations to disappear before the next launch. If startup memory imbalance persists, increase `GPU_CLEANUP_TIMEOUT_SECONDS` or `GPU_CLEANUP_EXTRA_SLEEP_SECONDS`.
- Use `KT_FIRST_TEST=NNN` and `KT_LAST_TEST=NNN` to resume or narrow the sweep without editing the test matrix.

## Completed Follow-Up Results Through Test066

These result files were produced manually after the dynamic sweep. They supersede the historical static `run_test 065/066` rows below for the current repo-root `results/kimi_k26/h200x2/tests` directory. Do not infer the manual result-file numbers from the older static matrix rows.

- `test065_r1_053_mem0912_ctx262k`: full-context version of `test053`; `--kt-cpuinfer 16`, `--kt-threadpool-count 2`, `--kt-num-gpu-experts 136`, `--mem-fraction-static 0.912`, `--max-total-tokens 262144`, `--chunked-prefill-size 16384`, `--kt-gpu-prefill-token-threshold 1024`; actual `max_total_num_tokens=262144`; 100/100 requests; output `20.05` tok/s; mean TTFT `20.928s`; median TTFT `13.602s`; P95 TTFT `48.498s`. This is the current TTFT-preferred full-context config.
- `test066_r1_065_cpuinfer32`: same as `test065`, except `--kt-cpuinfer 32`; actual `max_total_num_tokens=262144`; 100/100 requests; output `21.60` tok/s; mean TTFT `22.218s`; median TTFT `14.509s`; P95 TTFT `51.703s`. This is the throughput-preferred full-context variant, but TTFT was worse than `test065`.
- Startup probing found `--mem-fraction-static 0.910` started but only reported `max_total_num_tokens=260812`; `0.912` reached the requested `262144`.
- `envs/kimi_k26/h200x2.env` currently encodes the `test065` normal-launch values for `01_launch.sh`: cpuinfer `16`, threadpool `2`, GPU experts `136`, mem fraction `0.912`, chunk `16384`, threshold `1024`, max-running requests `2`, max-total tokens `262144`, and CUDA graph batch sizes `1 2`. `01_launch.sh` still uses `--kt-expert-placement-strategy uniform` and no `--init-expert-location`; the sweep runner uses `frequency` plus the latest recorded experts.
- Do not change KV-cache dtype or prefix/radix-cache behavior unless explicitly requested. The completed runs kept `kv_cache_dtype=auto` / BF16 and preserved `--disable-radix-cache --disable-chunked-prefix-cache`.

## Runner

Run from this directory after confirming no unrelated SGLang job is meant to stay alive. The durable runner is `tools/kimi_k26_seeded_workflow.sh`; the code block below keeps the test matrix that the runner parses.

```bash
#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plan_dir="$(cd -- "${tool_dir}/.." && pwd)"
repo_root="${KT_REPO_ROOT:-$(cd -- "${plan_dir}/../.." && pwd)}"
repo_parent="$(cd -- "${repo_root}/.." && pwd)"
cd "${repo_root}"

KT_EXPERTS_PATH="${KT_EXPERTS_PATH:-kimi_k26/h200x2}"
KT_PYTHON_ENV="${KT_PYTHON_ENV:-${HOME}/env_qwen3-ktransformers}"
KT_TEST_ENV="${KT_TEST_ENV:-${repo_root}/envs/${KT_EXPERTS_PATH}.env}"
KT_BENCHMARK_MODEL="${KT_BENCHMARK_MODEL:-kimi_k2}"
KT_BENCHMARK_PATH="${KT_BENCHMARK_PATH:-${repo_parent}/tools/benchmarks/benchmark.py}"
KT_BENCHMARK_FLAGS=(--num-prompts 100 --concurrency 2 --timeout 3600 --seed 52)
RESULTS_DIR="${RESULTS_DIR:-${repo_root}/results/${KT_EXPERTS_PATH}/tests}"
KT_PLAN_FILE="${KT_PLAN_FILE:-${plan_dir}/plan.md}"
MAX_TEST_ATTEMPTS="${MAX_TEST_ATTEMPTS:-3}"
GPU_CLEANUP_TIMEOUT_SECONDS="${GPU_CLEANUP_TIMEOUT_SECONDS:-180}"
GPU_CLEANUP_POLL_SECONDS="${GPU_CLEANUP_POLL_SECONDS:-5}"
GPU_CLEANUP_EXTRA_SLEEP_SECONDS="${GPU_CLEANUP_EXTRA_SLEEP_SECONDS:-10}"
KT_HOST="${KT_HOST:-0.0.0.0}"
KT_PORT="${KT_PORT:-8000}"
KT_API_KEY="${KT_API_KEY:-YOUR_API_KEY}"
KT_READY_URL="${KT_READY_URL:-http://127.0.0.1:${KT_PORT}/v1/models}"

if [[ -d "${KT_PYTHON_ENV}" ]]; then
  source "${KT_PYTHON_ENV}/bin/activate"
fi

source "${repo_root}/tools/launch_config.sh"
load_launch_config "${KT_TEST_ENV}"

mkdir -p "${RESULTS_DIR}"

recorder_dir="${repo_root}/experts/${EXPERTS_PATH}/02"
latest_expert_location="$(find "${recorder_dir}" -maxdepth 1 -type f -name 'expert_distribution_recorder_*.pt' | sort -V | tail -n 1)"
if [[ -z "${latest_expert_location}" ]]; then
  echo "No expert_distribution_recorder_*.pt files found in ${recorder_dir}" >&2
  exit 1
fi

sglang_process_pids() {
  pgrep -f "python -m sglang.launch_server|sglang::scheduler|sglang::detokenizer|sglang::tokenizer" 2>/dev/null || true
}

sglang_gpu_processes() {
  command -v nvidia-smi >/dev/null 2>&1 || return 0
  nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null \
    | awk '/sglang::|sglang.launch_server/'
}

wait_for_no_sglang_processes() {
  local deadline=$((SECONDS + GPU_CLEANUP_TIMEOUT_SECONDS))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if [[ -z "$(sglang_process_pids)" ]] && [[ -z "$(sglang_gpu_processes)" ]]; then
      return 0
    fi
    sleep "${GPU_CLEANUP_POLL_SECONDS}"
  done
  return 1
}

cleanup_server() {
  pkill -TERM -f "python -m sglang.launch_server" 2>/dev/null || true
  pkill -TERM -f "sglang.launch_server|sglang::scheduler|sglang::detokenizer|sglang::tokenizer" 2>/dev/null || true

  if ! wait_for_no_sglang_processes; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] CLEANUP_FORCE_KILL remaining_sglang_processes"
    sglang_process_pids | xargs -r kill -KILL 2>/dev/null || true
    pkill -KILL -f "python -m sglang.launch_server" 2>/dev/null || true
    pkill -KILL -f "sglang.launch_server|sglang::scheduler|sglang::detokenizer|sglang::tokenizer" 2>/dev/null || true
    wait_for_no_sglang_processes || {
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] CLEANUP_STILL_BUSY"
      sglang_gpu_processes || true
    }
  fi

  sleep "${GPU_CLEANUP_EXTRA_SLEEP_SECONDS}"
}

wait_for_server() {
  local pid="$1"
  local out="$2"
  local server_log="$3"

  for _ in $(seq 1 180); do
    if curl -fsS -H "Authorization: Bearer ${KT_API_KEY}" "${KT_READY_URL}" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      {
        echo
        echo "SERVER_EXITED_BEFORE_READY"
        echo "SERVER_LOG_TAIL:"
        tail -n 200 "${server_log}" || true
      } >> "${out}"
      return 1
    fi
    sleep 10
  done

  {
    echo
    echo "SERVER_READINESS_TIMEOUT"
    echo "SERVER_LOG_TAIL:"
    tail -n 200 "${server_log}" || true
  } >> "${out}"
  return 1
}

successful_result() {
  local out="$1"
  [[ -f "${out}" ]] || return 1
  grep -q '^END_UTC:' "${out}" || return 1
  grep -q '^BENCHMARK_EXIT_CODE: 0' "${out}" || return 1
  grep -Eq 'Successful requests:[[:space:]]+100/100' "${out}" || return 1
}

archive_failed_result() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mv "${path}" "${path}.previous_${stamp}"
}

run_test() {
  local id="$1"
  local label="$2"
  local kt_cpuinfer="$3"
  local kt_threadpool_count="$4"
  local kt_num_gpu_experts="$5"
  local kt_deferred="$6"
  local mem_fraction_static="$7"
  local chunked_prefill_size="$8"
  local extra_args="$9"

  local out="${RESULTS_DIR}/test${id}.txt"
  local server_log="${RESULTS_DIR}/test${id}.server.log"
  local -a extra_arg_list=()
  read -r -a extra_arg_list <<< "${extra_args}"

  if successful_result "${out}"; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SKIP test${id}_${label} already completed successfully"
    return 0
  fi

  if [[ -f "${out}" ]]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] RETRY_PREVIOUS_FAILED test${id}_${label}"
    archive_failed_result "${out}"
  fi
  if [[ -f "${server_log}" ]]; then
    archive_failed_result "${server_log}"
  fi

  local -a cmd=(
    env CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}"
    "${ADDITIONAL_SGLANG_ENV_ARGS[@]}"
    numactl --cpunodebind="${NUMACTL_CPUNODEBIND}" --membind="${NUMACTL_MEMBIND}"
    python -m sglang.launch_server
      --host "${KT_HOST}"
      --port "${KT_PORT}"
      --api-key "${KT_API_KEY}"
      --model-path "${model_path}"
      --kt-weight-path "${model_path}"
      --kt-cpuinfer "${kt_cpuinfer}"
      --kt-threadpool-count "${kt_threadpool_count}"
      --kt-num-gpu-experts "${kt_num_gpu_experts}"
      --kt-method "${KT_METHOD}"
      --kt-max-deferred-experts-per-token "${kt_deferred}"
      --kt-expert-placement-strategy frequency
      --init-expert-location "${latest_expert_location}"
      --trust-remote-code
      --mem-fraction-static "${mem_fraction_static}"
      --chunked-prefill-size "${chunked_prefill_size}"
      --served-model-name "${SERVED_MODEL_NAME}"
      --enable-mixed-chunk
      --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
      --numa-node "${NUMA_NODE_ARGS[@]}"
      --enable-p2p-check
      --disable-shared-experts-fusion
      --disable-radix-cache
      --disable-chunked-prefix-cache
      "${extra_arg_list[@]}"
  )

  local -a benchmark_cmd=(
    python "${KT_BENCHMARK_PATH}"
      "${KT_BENCHMARK_FLAGS[@]}"
      --model "${KT_BENCHMARK_MODEL}"
      --label "${KT_EXPERTS_PATH} | test${id}_${label}"
  )

  : > "${out}"
  local attempt
  for attempt in $(seq 1 "${MAX_TEST_ATTEMPTS}"); do
    cleanup_server
    if (( attempt > 1 )); then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] RETRY test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      sleep 20
    fi
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"

    {
      echo "TEST: test${id}_${label}"
      echo "ATTEMPT: ${attempt}/${MAX_TEST_ATTEMPTS}"
      echo "START_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "EXPERT_FILE: ${latest_expert_location}"
      echo
      echo "SGLANG_COMMAND:"
      printf '%q ' "${cmd[@]}"
      echo
      echo
      echo "BENCHMARK_COMMAND:"
      printf '%q ' "${benchmark_cmd[@]}"
      echo
      echo
      echo "SERVER_LOG: ${server_log}"
      echo
      echo "BENCHMARK_OUTPUT:"
    } >> "${out}"

    "${cmd[@]}" > "${server_log}" 2>&1 &
    local server_pid="$!"

    if ! wait_for_server "${server_pid}" "${out}" "${server_log}"; then
      kill "${server_pid}" 2>/dev/null || true
      wait "${server_pid}" 2>/dev/null || true
      cleanup_server
      echo "ATTEMPT_RESULT: READY_FAIL" >> "${out}"
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] READY_FAIL test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      if (( attempt == MAX_TEST_ATTEMPTS )); then
        echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${out}"
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FINAL_READY_FAIL test${id}_${label}"
      fi
      continue
    fi

    set +e
    "${benchmark_cmd[@]}" >> "${out}" 2>&1
    local benchmark_rc="$?"
    set -e

    {
      echo
      echo "BENCHMARK_EXIT_CODE: ${benchmark_rc}"
    } >> "${out}"

    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
    cleanup_server

    if [[ "${benchmark_rc}" -eq 0 ]] && grep -Eq 'Successful requests:[[:space:]]+100/100' "${out}"; then
      echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${out}"
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DONE test${id}_${label} benchmark_rc=${benchmark_rc} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      return 0
    fi

    echo "ATTEMPT_RESULT: BENCHMARK_FAIL rc=${benchmark_rc}" >> "${out}"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BENCHMARK_FAIL test${id}_${label} benchmark_rc=${benchmark_rc} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
    if (( attempt == MAX_TEST_ATTEMPTS )); then
      echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${out}"
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FINAL_BENCHMARK_FAIL test${id}_${label}"
    fi
  done

  return 0
}

COMMON="--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 131072"
GRAPH2="--cuda-graph-max-bs 2 --cuda-graph-bs 1 2"
GRAPH4="--cuda-graph-max-bs 4 --cuda-graph-bs 1 2 4"
GRAPH8="--cuda-graph-max-bs 8 --cuda-graph-bs 1 2 4 8"
FAST_BACKEND="--prefill-attention-backend fa3 --decode-attention-backend flashinfer --sampling-backend flashinfer --disable-custom-all-reduce"
FLASHINFER_BACKEND="--prefill-attention-backend flashinfer --decode-attention-backend flashinfer --sampling-backend flashinfer --disable-custom-all-reduce"
TRITON_PREFILL_BACKEND="--prefill-attention-backend triton --decode-attention-backend flashinfer --sampling-backend flashinfer --disable-custom-all-reduce"
NVLS="--enable-nccl-nvls"

# Baseline and chunk/threshold sweep.
run_test 001 baseline_04_current                      16 1 136 2 0.85 4096  "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2}"
run_test 002 chunk6144_thr400                         16 1 136 2 0.85 6144  "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2}"
run_test 003 chunk8192_thr400                         16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2}"
run_test 004 chunk12288_thr400                        16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2}"
run_test 005 chunk16384_thr400                        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2}"
run_test 006 chunk6144_thr1024                        16 1 136 2 0.85 6144  "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 007 chunk6144_thr4096                        16 1 136 2 0.85 6144  "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 008 chunk8192_thr512                         16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 512 ${GRAPH2}"
run_test 009 chunk8192_thr1024                        16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 010 chunk8192_thr2048                        16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2}"
run_test 011 chunk8192_thr4096                        16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 012 chunk8192_thr8192                        16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 013 chunk12288_thr512                        16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 512 ${GRAPH2}"
run_test 014 chunk12288_thr1024                       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 015 chunk12288_thr2048                       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2}"
run_test 016 chunk12288_thr4096                       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 017 chunk12288_thr8192                       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 018 chunk16384_thr512                        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 512 ${GRAPH2}"
run_test 019 chunk16384_thr1024                       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 020 chunk16384_thr2048                       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2}"
run_test 021 chunk16384_thr4096                       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 022 chunk16384_thr8192                       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 023 chunk16384_thr16384                      16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 16384 ${GRAPH2}"
run_test 024 chunk24576_thr4096_stretch               16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 025 chunk24576_thr8192_stretch               16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"

# Backend overlays for likely chunk winners.
run_test 026 chunk16384_thr1024_fast_backend          16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${FAST_BACKEND}"
run_test 027 chunk16384_thr4096_fast_backend          16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 028 chunk16384_thr8192_fast_backend          16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND}"
run_test 029 chunk12288_thr1024_fast_backend          16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${FAST_BACKEND}"
run_test 030 chunk12288_thr4096_fast_backend          16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 031 chunk8192_thr1024_fast_backend           16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${FAST_BACKEND}"
run_test 032 baseline_fast_backend                    16 1 136 2 0.85 4096  "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2} ${FAST_BACKEND}"
run_test 033 chunk16384_thr1024_fast_nvls             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 034 chunk16384_thr4096_fast_nvls             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 035 chunk12288_thr4096_fast_nvls             16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 036 chunk16384_thr1024_flashinfer_prefill    16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${FLASHINFER_BACKEND}"
run_test 037 chunk16384_thr1024_triton_prefill        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${TRITON_PREFILL_BACKEND}"

# GPU expert count and memory headroom variants.
run_test 038 exp128_mem082_chunk16384_thr1024         16 1 128 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 039 exp128_mem085_chunk16384_thr1024         16 1 128 2 0.85 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 040 exp112_mem082_chunk16384_thr1024         16 1 112 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 041 exp112_mem085_chunk16384_thr1024         16 1 112 2 0.85 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 042 exp096_mem082_chunk16384_thr1024         16 1 96  2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 043 exp096_mem085_chunk16384_thr1024         16 1 96  2 0.85 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 044 exp064_mem082_chunk16384_thr1024         16 1 64  2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 045 exp136_mem080_chunk16384_thr1024         16 1 136 2 0.80 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 046 exp136_mem084_chunk16384_thr1024         16 1 136 2 0.84 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 047 exp136_mem086_chunk12288_thr1024         16 1 136 2 0.86 12288 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 048 exp128_mem082_chunk16384_thr4096_fast    16 1 128 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 049 exp112_mem082_chunk16384_thr4096_fast    16 1 112 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 050 exp096_mem082_chunk16384_thr4096_fast    16 1 96  2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 051 exp144_mem078_chunk12288_thr1024_stretch 16 1 144 2 0.78 12288 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 052 exp144_mem080_chunk8192_thr1024_stretch  16 1 144 2 0.80 8192  "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"

# CPU expert and deferred expert variants.
run_test 053 cpu08_def2_chunk16384_thr1024            8  1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 054 cpu12_def2_chunk16384_thr1024            12 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 055 cpu20_def2_chunk16384_thr1024            20 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 056 cpu24_def2_chunk16384_thr1024            24 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 057 cpu16_def3_chunk16384_thr1024            16 1 136 3 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 058 cpu12_def3_chunk16384_thr1024            12 1 136 3 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 059 cpu20_def3_chunk16384_thr1024            20 1 136 3 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 060 cpu24_def3_chunk16384_thr1024            24 1 136 3 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 061 cpu16_def4_chunk16384_thr1024            16 1 136 4 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 062 cpu12_def4_chunk16384_thr1024            12 1 136 4 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 063 cpu20_def4_chunk16384_thr1024            20 1 136 4 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 064 threadpool2_cpu16_def2_chunk16384        16 2 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 065 threadpool2_cpu20_def3_chunk16384        20 2 136 3 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"

# CUDA graph, max-running, and scheduler-adjacent variants.
run_test 066 graph4_chunk16384_thr1024                16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH4}"
run_test 067 graph8_chunk16384_thr1024                16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH8}"
run_test 068 graph4_chunk16384_thr4096_fast           16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} ${FAST_BACKEND}"
run_test 069 graph8_chunk16384_thr4096_fast           16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH8} ${FAST_BACKEND}"
run_test 070 graph_off_chunk16384_thr1024             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 --disable-cuda-graph"
run_test 071 graph_off_chunk16384_thr4096             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 --disable-cuda-graph"
run_test 072 maxrun1_chunk16384_thr1024               16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 1 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 073 maxrun3_graph4_chunk16384_thr1024        16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 3 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 1024 ${GRAPH4}"
run_test 074 maxrun4_graph4_chunk16384_thr1024        16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 4 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 1024 ${GRAPH4}"
run_test 075 max_total_98304_chunk16384_thr1024       16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 98304 --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 076 max_total_196608_chunk16384_thr1024      16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 196608 --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 077 disable_graph_padding_chunk16384         16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --disable-cuda-graph-padding"

# Advanced but still plausible SGLang flags.
run_test 078 piecewise_graph_chunk16384_thr1024       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --enable-piecewise-cuda-graph --piecewise-cuda-graph-tokens 1024 2048 4096 8192 16384"
run_test 079 piecewise_graph_chunk12288_thr4096       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --enable-piecewise-cuda-graph --piecewise-cuda-graph-tokens 1024 2048 4096 8192 12288"
run_test 080 nvls_only_baseline                       16 1 136 2 0.85 4096  "${COMMON} --kt-gpu-prefill-token-threshold 400 ${GRAPH2} ${NVLS}"
run_test 081 nvls_chunk16384_thr1024                  16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} ${NVLS}"
run_test 082 flashinfer_allreduce_chunk16384          16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --enable-flashinfer-allreduce-fusion"
run_test 083 dynamic_expert_update_thr1024            16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --kt-enable-dynamic-expert-update"
run_test 084 dynamic_expert_update_thr4096            16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --kt-enable-dynamic-expert-update"
run_test 085 max_prefill_32768_chunk16384             16 1 136 2 0.80 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --max-prefill-tokens 32768"
run_test 086 max_prefill_24576_chunk24576             16 1 136 2 0.76 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} --max-prefill-tokens 32768"
run_test 087 explicit_prefill_max_requests2           16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --prefill-max-requests 2"
run_test 088 explicit_schedule_fcfs                   16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --schedule-policy fcfs"
run_test 089 attention_backend_fa3                    16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --attention-backend fa3 --sampling-backend flashinfer --disable-custom-all-reduce"
run_test 090 decode_triton_prefill_fa3                16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2} --prefill-attention-backend fa3 --decode-attention-backend triton --sampling-backend flashinfer --disable-custom-all-reduce"

# Late controls. Run only after the useful candidates above.
run_test 091 threshold0_chunk16384_control            16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 0 ${GRAPH2}"
run_test 092 chunk32768_thr8192_stretch               16 1 136 2 0.74 32768 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 093 chunk32768_thr16384_stretch              16 1 128 2 0.74 32768 "${COMMON} --kt-gpu-prefill-token-threshold 16384 ${GRAPH2}"
run_test 094 graph_off_chunk12288_thr4096_fast        16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 --disable-cuda-graph ${FAST_BACKEND}"
run_test 095 graph_off_chunk16384_thr4096_fast        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 --disable-cuda-graph ${FAST_BACKEND}"
run_test 096 exp128_mem080_chunk24576_thr8192_fast    16 1 128 2 0.80 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND}"

# Expanded TTFT-first local search. These bias toward reducing prefill latency,
# even if throughput or stability may get worse.
run_test 097 chunk10240_thr1024                       16 1 136 2 0.84 10240 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 098 chunk10240_thr2048                       16 1 136 2 0.84 10240 "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2}"
run_test 099 chunk10240_thr4096                       16 1 136 2 0.84 10240 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 100 chunk14336_thr1024                       16 1 136 2 0.83 14336 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 101 chunk14336_thr2048                       16 1 136 2 0.83 14336 "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2}"
run_test 102 chunk14336_thr4096                       16 1 136 2 0.83 14336 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 103 chunk18432_thr1024                       16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 1024 ${GRAPH2}"
run_test 104 chunk18432_thr4096                       16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 105 chunk18432_thr8192                       16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 106 chunk20480_thr4096                       16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 107 chunk20480_thr8192                       16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 108 chunk20480_thr12288                      16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 12288 ${GRAPH2}"
run_test 109 chunk28672_thr8192_exp128_stretch        16 1 128 2 0.75 28672 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2}"
run_test 110 chunk28672_thr16384_exp128_stretch       16 1 128 2 0.75 28672 "${COMMON} --kt-gpu-prefill-token-threshold 16384 ${GRAPH2}"
run_test 111 chunk16384_thr3072                       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 3072 ${GRAPH2}"
run_test 112 chunk12288_thr3072                       16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 3072 ${GRAPH2}"
run_test 113 chunk8192_thr3072                        16 1 136 2 0.85 8192  "${COMMON} --kt-gpu-prefill-token-threshold 3072 ${GRAPH2}"
run_test 114 chunk24576_thr12288                      16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 12288 ${GRAPH2}"
run_test 115 chunk24576_thr16384                      16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 16384 ${GRAPH2}"

# Backend overlays on expanded local-search candidates.
run_test 116 chunk14336_thr4096_fast                  16 1 136 2 0.83 14336 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 117 chunk18432_thr4096_fast                  16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 118 chunk20480_thr8192_fast                  16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND}"
run_test 119 chunk24576_thr8192_fast                  16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND}"
run_test 120 chunk16384_thr3072_fast                  16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 3072 ${GRAPH2} ${FAST_BACKEND}"
run_test 121 chunk12288_thr3072_fast                  16 1 136 2 0.84 12288 "${COMMON} --kt-gpu-prefill-token-threshold 3072 ${GRAPH2} ${FAST_BACKEND}"
run_test 122 chunk16384_thr2048_fast_nvls             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 2048 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 123 chunk16384_thr8192_fast_nvls             16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 124 chunk18432_thr4096_fast_nvls             16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 125 chunk20480_thr8192_fast_nvls             16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 126 chunk24576_thr8192_fast_nvls             16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
run_test 127 graph4_chunk18432_thr4096_fast           16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} ${FAST_BACKEND}"
run_test 128 graph4_chunk20480_thr8192_fast           16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH4} ${FAST_BACKEND}"
run_test 129 chunk16384_thr4096_flashinfer_nvls       16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FLASHINFER_BACKEND} ${NVLS}"
run_test 130 chunk18432_thr4096_flashinfer            16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FLASHINFER_BACKEND}"
run_test 131 graph4_chunk16384_thr4096_triton_prefill 16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} ${TRITON_PREFILL_BACKEND}"
run_test 132 graph4_chunk18432_thr4096_triton_prefill 16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} ${TRITON_PREFILL_BACKEND}"

# Graph-off and graph-size checks around larger chunks.
run_test 133 graph_off_chunk18432_thr4096             16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 --disable-cuda-graph"
run_test 134 graph_off_chunk20480_thr8192             16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 --disable-cuda-graph"
run_test 135 graph_off_chunk24576_thr8192             16 1 136 2 0.78 24576 "${COMMON} --kt-gpu-prefill-token-threshold 8192 --disable-cuda-graph"
run_test 136 graph4_chunk18432_thr4096                16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4}"
run_test 137 graph4_chunk20480_thr8192                16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH4}"
run_test 138 graph8_chunk18432_thr4096                16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH8}"
run_test 139 graph8_chunk20480_thr8192                16 1 136 2 0.79 20480 "${COMMON} --kt-gpu-prefill-token-threshold 8192 ${GRAPH8}"
run_test 140 graph4_disable_padding_chunk16384        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} --disable-cuda-graph-padding"

# Expert-count and memory interaction around larger prefill chunks.
run_test 141 exp136_mem078_chunk18432_thr4096         16 1 136 2 0.78 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 142 exp136_mem080_chunk18432_thr4096         16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 143 exp136_mem082_chunk18432_thr4096         16 1 136 2 0.82 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 144 exp128_mem078_chunk18432_thr4096         16 1 128 2 0.78 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 145 exp128_mem080_chunk18432_thr4096         16 1 128 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 146 exp128_mem082_chunk18432_thr4096         16 1 128 2 0.82 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 147 exp112_mem080_chunk18432_thr4096         16 1 112 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 148 exp096_mem080_chunk18432_thr4096         16 1 96  2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 149 exp144_mem076_chunk12288_thr4096_stretch 16 1 144 2 0.76 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 150 exp144_mem078_chunk16384_thr4096_stretch 16 1 144 2 0.78 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 151 exp152_mem074_chunk8192_thr4096_stretch  16 1 152 2 0.74 8192  "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 152 exp152_mem076_chunk12288_thr4096_stretch 16 1 152 2 0.76 12288 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"

# CPU fallback refinements around the likely bigger-chunk candidates.
run_test 153 cpu08_def3_chunk18432_thr4096            8  1 136 3 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 154 cpu12_def2_chunk18432_thr4096            12 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 155 cpu12_def3_chunk18432_thr4096            12 1 136 3 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 156 cpu16_def3_chunk18432_thr4096            16 1 136 3 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 157 cpu20_def2_chunk18432_thr4096            20 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 158 cpu20_def3_chunk18432_thr4096            20 1 136 3 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 159 cpu24_def2_chunk18432_thr4096            24 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 160 cpu24_def3_chunk18432_thr4096            24 1 136 3 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 161 cpu28_def2_chunk18432_thr4096            28 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 162 cpu16_def5_chunk16384_thr4096            16 1 136 5 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 163 cpu12_def5_chunk16384_thr4096            12 1 136 5 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 164 threadpool2_cpu16_chunk18432_thr4096     16 2 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 165 threadpool2_cpu20_chunk18432_thr4096     20 2 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"

# TTFT-specific request admission and token-budget variants.
run_test 166 maxrun1_chunk18432_thr4096               16 1 136 2 0.80 18432 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 1 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 167 maxrun1_chunk16384_thr4096_fast          16 1 136 2 0.82 16384 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 1 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND}"
run_test 168 max_total_98304_chunk18432_thr4096       16 1 136 2 0.80 18432 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 98304 --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 169 max_total_110592_chunk18432_thr4096      16 1 136 2 0.80 18432 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 110592 --kt-gpu-prefill-token-threshold 4096 ${GRAPH2}"
run_test 170 maxrun3_graph4_chunk18432_thr4096        16 1 136 2 0.80 18432 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 3 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 4096 ${GRAPH4}"
run_test 171 maxrun4_graph4_chunk18432_thr4096        16 1 136 2 0.80 18432 "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 4 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold 4096 ${GRAPH4}"
run_test 172 prefill_max_requests1_chunk18432         16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --prefill-max-requests 1"
run_test 173 prefill_max_requests2_chunk18432         16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --prefill-max-requests 2"

# Extra advanced variants and tokenizer-side TTFT checks.
run_test 174 dynamic_expert_update_chunk18432_thr4096 16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --kt-enable-dynamic-expert-update"
run_test 175 piecewise_graph_chunk18432_thr4096       16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --enable-piecewise-cuda-graph --piecewise-cuda-graph-tokens 1024 2048 4096 8192 12288 18432"
run_test 176 max_prefill_32768_chunk18432             16 1 136 2 0.78 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --max-prefill-tokens 32768"
run_test 177 flashinfer_allreduce_nvls_chunk16384     16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --enable-flashinfer-allreduce-fusion ${NVLS}"
run_test 178 fast_nvls_graph4_chunk18432_thr4096      16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH4} ${FAST_BACKEND} ${NVLS}"
run_test 179 symm_mem_chunk16384_thr4096              16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --enable-symm-mem"
run_test 180 tokenizer_batch_encode_chunk16384        16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --enable-tokenizer-batch-encode"
run_test 181 tokenizer_batch_encode_chunk18432_fast   16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND} --enable-tokenizer-batch-encode"
run_test 182 tokenizer_workers2_chunk16384            16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --tokenizer-worker-num 2"
run_test 183 tokenizer_workers4_chunk16384            16 1 136 2 0.82 16384 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} --tokenizer-worker-num 4"
run_test 184 tokenizer_workers2_batch_chunk18432_fast 16 1 136 2 0.80 18432 "${COMMON} --kt-gpu-prefill-token-threshold 4096 ${GRAPH2} ${FAST_BACKEND} --tokenizer-worker-num 2 --enable-tokenizer-batch-encode"
```

## Priority Order

Run all cases when possible. If the sweep is interrupted or narrowed, use this TTFT-first order:

1. `001` for the current `04_launch` baseline.
2. `014`, `016`, `019`, `021`, `022` to find the chunk/threshold direction.
3. `026` through `041` to check backend, NVLS, CUDA graph, scheduler, and tokenizer overlays on the best first-25 anchor.
4. `042+` for the deeper top-anchor probes that used to start after the repeated 2nd/3rd-anchor overlay blocks.
5. Use `KT_DYNAMIC_POST25_OVERLAY_TOP_N=3` only if you explicitly want to spend the compute to repeat `026-041` style overlays on the 2nd and 3rd anchors.

## Ranking Metrics

Rank by balanced performance, not raw lowest mean TTFT. Treat mean TTFT differences smaller than `max(250ms, 0.5%)` as noise; inside that tied TTFT band, prefer throughput and tail latency.

1. zero failures and `Successful requests: 100/100`
2. mean TTFT within `max(250ms, 0.5%)` of the fastest successful run
3. highest output tokens/sec
4. lowest P95 TTFT
5. lowest median TTFT
6. lowest mean TTFT

Keep `02_record.txt` and `04_launch.txt` unchanged. New results belong only in repo-root `results/kimi_k26/h200x2/tests/`.
