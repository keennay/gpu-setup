#!/usr/bin/env bash
set -euo pipefail

tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plan_dir="$(cd -- "${tool_dir}/.." && pwd)"
repo_root="${KT_REPO_ROOT:-$(cd -- "${plan_dir}/../.." && pwd)}"
repo_parent="$(cd -- "${repo_root}/.." && pwd)"
cd "${repo_root}"

KT_EXPERTS_PATH="${KT_EXPERTS_PATH:-kimi_k26/h200x2}"
KT_PYTHON_ENV="${KT_PYTHON_ENV:-${HOME}/env_qwen-ktransformers}"
KT_TEST_ENV="${KT_TEST_ENV:-${repo_root}/envs/${KT_EXPERTS_PATH}.env}"
KT_BENCHMARK_MODEL="${KT_BENCHMARK_MODEL:-kimi_k2}"
KT_BENCHMARK_PATH="${KT_BENCHMARK_PATH:-${repo_parent}/benchmarks/benchmark.py}"
KT_BENCHMARK_SEED="${KT_BENCHMARK_SEED:-52}"
KT_RECORD_NUM_PROMPTS="${KT_RECORD_NUM_PROMPTS:-100}"
KT_SWEEP_NUM_PROMPTS="${KT_SWEEP_NUM_PROMPTS:-100}"
KT_CONCURRENCY="${KT_CONCURRENCY:-2}"
KT_TIMEOUT="${KT_TIMEOUT:-3600}"
RESULTS_DIR="${RESULTS_DIR:-${repo_root}/results/${KT_EXPERTS_PATH}/tests}"
KT_PLAN_FILE="${KT_PLAN_FILE:-${plan_dir}/plan.md}"
KT_FIRST_TEST="${KT_FIRST_TEST:-001}"
KT_LAST_TEST="${KT_LAST_TEST:-999}"
MAX_TEST_ATTEMPTS="${MAX_TEST_ATTEMPTS:-3}"
GPU_CLEANUP_TIMEOUT_SECONDS="${GPU_CLEANUP_TIMEOUT_SECONDS:-180}"
GPU_CLEANUP_POLL_SECONDS="${GPU_CLEANUP_POLL_SECONDS:-5}"
GPU_CLEANUP_EXTRA_SLEEP_SECONDS="${GPU_CLEANUP_EXTRA_SLEEP_SECONDS:-10}"
KT_HOST="${KT_HOST:-0.0.0.0}"
KT_PORT="${KT_PORT:-8000}"
KT_API_KEY="${KT_API_KEY:-YOUR_API_KEY}"
KT_READY_URL="${KT_READY_URL:-http://127.0.0.1:${KT_PORT}/v1/models}"
KT_HERMES_NOTIFY="${KT_HERMES_NOTIFY:-1}"
KT_HERMES_NOTIFY_STATE="${KT_HERMES_NOTIFY_STATE:-/tmp/kimi_k26_seed${KT_BENCHMARK_SEED}_hermes_notified_tests.txt}"
KT_HERMES_START_NOTIFY_STATE="${KT_HERMES_START_NOTIFY_STATE:-/tmp/kimi_k26_seed${KT_BENCHMARK_SEED}_hermes_started_tests.txt}"
KT_HERMES_START_FROM="${KT_HERMES_START_FROM:-025}"
KT_DYNAMIC_POST25="${KT_DYNAMIC_POST25:-1}"
KT_DYNAMIC_POST25_TOP_N="${KT_DYNAMIC_POST25_TOP_N:-3}"
KT_DYNAMIC_POST25_OVERLAY_TOP_N="${KT_DYNAMIC_POST25_OVERLAY_TOP_N:-1}"
KT_DYNAMIC_POST25_START="${KT_DYNAMIC_POST25_START:-026}"
KT_DYNAMIC_POST25_SOURCE_LAST="${KT_DYNAMIC_POST25_SOURCE_LAST:-025}"

if [[ -d "${KT_PYTHON_ENV}" ]]; then
  source "${KT_PYTHON_ENV}/bin/activate"
fi

source "${repo_root}/tools/launch_config.sh"
load_launch_config "${KT_TEST_ENV}"

mkdir -p "${RESULTS_DIR}" "${repo_root}/experts/${EXPERTS_PATH}/01" "${repo_root}/experts/${EXPERTS_PATH}/02"

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

recorder_api_post() {
  local endpoint="$1"
  local out="$2"
  local response
  local rc

  set +e
  response="$(curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${KT_API_KEY}" \
    "http://127.0.0.1:${KT_PORT}/${endpoint}" \
    -d '{}' 2>&1)"
  rc=$?
  set -e

  {
    echo
    echo "RECORDER_API: ${endpoint}"
    echo "RECORDER_API_EXIT_CODE: ${rc}"
    if [[ -n "${response}" ]]; then
      echo "RECORDER_API_RESPONSE:"
      echo "${response}"
    fi
  } >> "${out}"

  return "${rc}"
}

successful_result() {
  local out="$1"
  local expected_requests="${2:-100}"
  [[ -f "${out}" ]] || return 1
  grep -q '^END_UTC:' "${out}" || return 1
  grep -q '^BENCHMARK_EXIT_CODE: 0' "${out}" || return 1
  grep -Eq "Successful requests:[[:space:]]+${expected_requests}/${expected_requests}" "${out}" || return 1
}

archive_failed_result() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  local stamp
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mv "${path}" "${path}.previous_${stamp}"
}

append_benchmark_results() {
  local live_log="$1"
  if grep -q '^RESULTS:' "${live_log}" 2>/dev/null; then
    sed -n '/^RESULTS:/,$p' "${live_log}"
  else
    echo "BENCHMARK_LIVE_LOG_TAIL:"
    tail -n 240 "${live_log}" 2>/dev/null || true
  fi
}

result_metrics_line() {
  local result_file="$1"
  local test_name="$2"
  python - "${result_file}" "${test_name}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
test_name = sys.argv[2]
txt = path.read_text(errors="replace")

chunk = re.search(r"--chunked-prefill-size\s+(\S+)", txt)
threshold = re.search(r"--kt-gpu-prefill-token-threshold\s+(\S+)", txt)
output = re.search(r"^  Output tokens/sec:\s*([0-9.]+)", txt, re.M)
ttft = re.search(
    r"^Reasoning:\n  Mean:\s*([0-9]+)ms\n  Median:\s*([0-9]+)ms\n  P95:\s*([0-9]+)ms",
    txt,
    re.M,
)
if not ttft:
    sys.exit(1)

def seconds(ms):
    return f"{int(ms) / 1000:.3f}s"

print(
    "\t".join(
        [
            test_name,
            chunk.group(1) if chunk else "n/a",
            threshold.group(1) if threshold else "n/a",
            output.group(1) if output else "n/a",
            seconds(ttft.group(1)),
            seconds(ttft.group(2)),
            seconds(ttft.group(3)),
            ttft.group(1),
        ]
    )
)
PY
}

best_result_metrics_line() {
  python - "${RESULTS_DIR}" "${KT_SWEEP_NUM_PROMPTS}" <<'PY'
import re
import sys
from pathlib import Path

results_dir = Path(sys.argv[1])
expected_requests = sys.argv[2]
rows = []

for path in sorted(results_dir.glob("test*.txt")):
    txt = path.read_text(errors="replace")
    if "BENCHMARK_EXIT_CODE: 0" not in txt:
        continue
    if not re.search(rf"Successful requests:\s+{expected_requests}/{expected_requests}", txt):
        continue
    ttft = re.search(
        r"^Reasoning:\n  Mean:\s*([0-9]+)ms\n  Median:\s*([0-9]+)ms\n  P95:\s*([0-9]+)ms",
        txt,
        re.M,
    )
    if not ttft:
        continue
    mean_ms = int(ttft.group(1))
    median_ms = int(ttft.group(2))
    p95_ms = int(ttft.group(3))
    chunk = re.search(r"--chunked-prefill-size\s+(\S+)", txt)
    threshold = re.search(r"--kt-gpu-prefill-token-threshold\s+(\S+)", txt)
    output = re.search(r"^  Output tokens/sec:\s*([0-9.]+)", txt, re.M)
    output_toks = float(output.group(1)) if output else 0.0
    rows.append(
        {
            "mean_ms": mean_ms,
            "median_ms": median_ms,
            "p95_ms": p95_ms,
            "output_toks": output_toks,
            "output_text": output.group(1) if output else "n/a",
            "test_name": path.stem,
            "chunk": chunk.group(1) if chunk else "n/a",
            "threshold": threshold.group(1) if threshold else "n/a",
        }
    )

if not rows:
    sys.exit(1)

min_mean = min(row["mean_ms"] for row in rows)
ttft_tolerance_ms = max(250, int(min_mean * 0.005))
eligible = [row for row in rows if row["mean_ms"] <= min_mean + ttft_tolerance_ms]
best = sorted(
    eligible,
    key=lambda row: (
        -row["output_toks"],
        row["p95_ms"],
        row["median_ms"],
        row["mean_ms"],
        row["test_name"],
    ),
)[0]

print(
    "\t".join(
        [
            best["test_name"],
            best["chunk"],
            best["threshold"],
            best["output_text"],
            f'{best["mean_ms"] / 1000:.3f}s',
            f'{best["median_ms"] / 1000:.3f}s',
            f'{best["p95_ms"] / 1000:.3f}s',
        ]
    )
)
PY
}

hermes_send_discord() {
  local message="$1"

  if [[ "${KT_HERMES_NOTIFY}" != "1" ]]; then
    return 0
  fi
  if ! command -v hermes >/dev/null 2>&1; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HERMES_NOTIFY_SKIP hermes_not_found"
    return 0
  fi

  if hermes send --quiet --to discord "${message}" >/dev/null 2>&1; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HERMES_NOTIFY_SENT ${message}"
  else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HERMES_NOTIFY_FAIL ${message}"
  fi
}

arg_value() {
  local flag="$1"
  shift

  while (( $# > 0 )); do
    if [[ "$1" == "${flag}" ]]; then
      shift
      if (( $# > 0 )); then
        printf '%s\n' "$1"
        return 0
      fi
      return 1
    fi
    shift
  done
  return 1
}

arg_present() {
  local flag="$1"
  shift

  while (( $# > 0 )); do
    if [[ "$1" == "${flag}" ]]; then
      return 0
    fi
    shift
  done
  return 1
}

join_by() {
  local sep="$1"
  shift

  if (( $# == 0 )); then
    return 0
  fi

  printf '%s' "$1"
  shift || true
  while (( $# > 0 )); do
    printf '%s%s' "${sep}" "$1"
    shift
  done
}

test_start_explainer() {
  local label="$1"
  local kt_cpuinfer="$2"
  local kt_threadpool_count="$3"
  local kt_num_gpu_experts="$4"
  local kt_deferred="$5"
  local mem_fraction_static="$6"
  local chunked_prefill_size="$7"
  local extra_args="$8"
  local -a args=()
  local -a notes=()
  local threshold graph_max max_run max_total max_prefill prefill_max_requests schedule prefill_backend decode_backend sampling_backend tokenizer_workers

  read -r -a args <<< "${extra_args}"
  threshold="$(arg_value --kt-gpu-prefill-token-threshold "${args[@]}" || true)"
  graph_max="$(arg_value --cuda-graph-max-bs "${args[@]}" || true)"
  max_run="$(arg_value --max-running-requests "${args[@]}" || true)"
  max_total="$(arg_value --max-total-tokens "${args[@]}" || true)"
  max_prefill="$(arg_value --max-prefill-tokens "${args[@]}" || true)"
  prefill_max_requests="$(arg_value --prefill-max-requests "${args[@]}" || true)"
  schedule="$(arg_value --schedule-policy "${args[@]}" || true)"
  prefill_backend="$(arg_value --prefill-attention-backend "${args[@]}" || true)"
  decode_backend="$(arg_value --decode-attention-backend "${args[@]}" || true)"
  sampling_backend="$(arg_value --sampling-backend "${args[@]}" || true)"
  tokenizer_workers="$(arg_value --tokenizer-worker-num "${args[@]}" || true)"

  [[ -n "${graph_max}" ]] && notes+=("cuda_graph_max_bs=${graph_max}")
  arg_present --disable-cuda-graph "${args[@]}" && notes+=("cuda_graph=off")
  arg_present --disable-cuda-graph-padding "${args[@]}" && notes+=("graph_padding=off")
  arg_present --enable-piecewise-cuda-graph "${args[@]}" && notes+=("piecewise_graph")
  arg_present --disable-custom-all-reduce "${args[@]}" && notes+=("fast_backend/no_custom_allreduce")
  arg_present --enable-nccl-nvls "${args[@]}" && notes+=("NVLS")
  arg_present --enable-flashinfer-allreduce-fusion "${args[@]}" && notes+=("flashinfer_allreduce")
  arg_present --kt-enable-dynamic-expert-update "${args[@]}" && notes+=("dynamic_expert_update")
  arg_present --enable-symm-mem "${args[@]}" && notes+=("symm_mem")
  arg_present --enable-tokenizer-batch-encode "${args[@]}" && notes+=("tokenizer_batch_encode")
  [[ -n "${prefill_backend}" ]] && notes+=("prefill=${prefill_backend}")
  [[ -n "${decode_backend}" ]] && notes+=("decode=${decode_backend}")
  [[ -n "${sampling_backend}" ]] && notes+=("sampling=${sampling_backend}")
  [[ -n "${max_run}" ]] && notes+=("max_run=${max_run}")
  [[ -n "${max_total}" ]] && notes+=("max_total=${max_total}")
  [[ -n "${max_prefill}" ]] && notes+=("max_prefill=${max_prefill}")
  [[ -n "${prefill_max_requests}" ]] && notes+=("prefill_max_requests=${prefill_max_requests}")
  [[ -n "${schedule}" ]] && notes+=("schedule=${schedule}")
  [[ -n "${tokenizer_workers}" ]] && notes+=("tokenizer_workers=${tokenizer_workers}")

  printf 'label=%s; chunk=%s; threshold=%s; mem=%s; gpu_experts=%s; cpuinfer=%s; threadpools=%s; deferred=%s' \
    "${label}" \
    "${chunked_prefill_size}" \
    "${threshold:-n/a}" \
    "${mem_fraction_static}" \
    "${kt_num_gpu_experts}" \
    "${kt_cpuinfer}" \
    "${kt_threadpool_count}" \
    "${kt_deferred}"

  if (( ${#notes[@]} > 0 )); then
    printf '; flags=%s' "$(join_by ', ' "${notes[@]}")"
  fi
}

mark_start_notified() {
  local id="$1"
  local key="test${id}"
  local fd

  mkdir -p "$(dirname "${KT_HERMES_START_NOTIFY_STATE}")"
  touch "${KT_HERMES_START_NOTIFY_STATE}"

  if command -v flock >/dev/null 2>&1; then
    exec {fd}>"${KT_HERMES_START_NOTIFY_STATE}.lock"
    flock -x "${fd}" || return 1
    if grep -qx "${key}" "${KT_HERMES_START_NOTIFY_STATE}" 2>/dev/null; then
      flock -u "${fd}" || true
      return 1
    fi
    printf '%s\n' "${key}" >> "${KT_HERMES_START_NOTIFY_STATE}"
    flock -u "${fd}" || true
    return 0
  fi

  if grep -qx "${key}" "${KT_HERMES_START_NOTIFY_STATE}" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "${key}" >> "${KT_HERMES_START_NOTIFY_STATE}"
}

notify_test_start() {
  local id="$1"
  local label="$2"
  local kt_cpuinfer="$3"
  local kt_threadpool_count="$4"
  local kt_num_gpu_experts="$5"
  local kt_deferred="$6"
  local mem_fraction_static="$7"
  local chunked_prefill_size="$8"
  local extra_args="$9"
  local id_num start_from_num explainer

  id_num=$((10#${id}))
  start_from_num=$((10#${KT_HERMES_START_FROM}))
  if (( id_num < start_from_num )); then
    return 0
  fi

  if ! mark_start_notified "${id}"; then
    return 0
  fi

  explainer="$(test_start_explainer \
    "${label}" \
    "${kt_cpuinfer}" \
    "${kt_threadpool_count}" \
    "${kt_num_gpu_experts}" \
    "${kt_deferred}" \
    "${mem_fraction_static}" \
    "${chunked_prefill_size}" \
    "${extra_args}")"
  hermes_send_discord "Starting test${id} | ${explainer}"
}

notify_test_success() {
  local id="$1"
  local out="$2"
  local metrics
  local best
  local test_name chunk threshold output_toks mean_ttft median_ttft p95 mean_ms

  mkdir -p "$(dirname "${KT_HERMES_NOTIFY_STATE}")"
  touch "${KT_HERMES_NOTIFY_STATE}"
  if grep -qx "test${id}" "${KT_HERMES_NOTIFY_STATE}" 2>/dev/null; then
    return 0
  fi

  metrics="$(result_metrics_line "${out}" "test${id}" 2>/dev/null)" || {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HERMES_NOTIFY_SKIP metrics_parse_failed test${id}"
    return 0
  }
  IFS=$'\t' read -r test_name chunk threshold output_toks mean_ttft median_ttft p95 mean_ms <<< "${metrics}"
  hermes_send_discord "${test_name}: Complete | Chunk: ${chunk} | Threshold: ${threshold} | Output Toks/s: ${output_toks} | Mean TTFT: ${mean_ttft} | Median TTFT: ${median_ttft} | P95: ${p95}"

  best="$(best_result_metrics_line 2>/dev/null)" || {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] HERMES_NOTIFY_SKIP best_parse_failed test${id}"
    return 0
  }
  IFS=$'\t' read -r test_name chunk threshold output_toks mean_ttft median_ttft p95 <<< "${best}"
  hermes_send_discord "Best So far is ${test_name} | Chunk: ${chunk} | Threshold: ${threshold} | Output Toks/s: ${output_toks} | Mean TTFT: ${mean_ttft} | Median TTFT: ${median_ttft} | P95: ${p95}"
  printf 'test%s\n' "${id}" >> "${KT_HERMES_NOTIFY_STATE}"
}

notify_test_failure_attempt() {
  local id="$1"
  local attempt="$2"

  hermes_send_discord "Fail ${attempt}/${MAX_TEST_ATTEMPTS} test${id}"
}

latest_combined_expert() {
  local dir="$1"
  find "${dir}" -maxdepth 1 -type f -name 'expert_distribution_recorder_*.pt' -size -100M 2>/dev/null \
    | sort -V \
    | tail -n 1
}

write_seed_profile() {
  local out="${RESULTS_DIR}/seed${KT_BENCHMARK_SEED}_profile.txt"
  python - "$KT_BENCHMARK_PATH" "$KT_BENCHMARK_SEED" > "${out}" <<'PY'
import importlib.util
import random
import statistics
import sys
from collections import Counter

path = sys.argv[1]
seed = int(sys.argv[2])
sys.argv = ["benchmark.py", "--preview-samples", "1", "--seed", str(seed)]
spec = importlib.util.spec_from_file_location("bench_sampler", path)
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)

bench.RANDOM_SEED = seed
bench.seed_random()
rows = []
for _ in range(100):
    input_len, input_bucket = bench.sample_input_tokens()
    output_len, output_bucket = bench.sample_output_tokens()
    prompt = bench.generate_unique_prompt(input_len, input_bucket, output_bucket)
    random.uniform(0.15, 0.45)
    rows.append((input_len, output_len, input_bucket, output_bucket, max(1, len(prompt) // 4)))

input_counts = Counter(row[2] for row in rows)
output_counts = Counter(row[3] for row in rows)
print(f"SEED: {seed}")
print(f"AVG_INPUT_TARGET: {statistics.mean(row[0] for row in rows):.0f}")
print(f"AVG_INPUT_APPROX: {statistics.mean(row[4] for row in rows):.0f}")
print(f"AVG_OUTPUT_TARGET: {statistics.mean(row[1] for row in rows):.0f}")
print("INPUT_MIX:")
for name in ["small_bugfix", "feature_task", "refactor", "deep_repo_context"]:
    print(f"  {name}: {input_counts[name]}")
print("OUTPUT_MIX:")
for name in ["small_patch", "standard_patch", "large_patch"]:
    print(f"  {name}: {output_counts[name]}")
PY
}

run_record_stage() {
  local stage="$1"
  local script="$2"
  local combine_dir="$3"
  local out="${RESULTS_DIR}/${stage}_seed${KT_BENCHMARK_SEED}.txt"
  local server_log="${RESULTS_DIR}/${stage}_seed${KT_BENCHMARK_SEED}.server.log"

  if successful_result "${out}" "${KT_RECORD_NUM_PROMPTS}" && [[ -n "$(latest_combined_expert "${combine_dir}")" ]]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SKIP ${stage} already completed successfully"
    return 0
  fi
  archive_failed_result "${out}"
  archive_failed_result "${server_log}"

  local -a server_cmd=(bash "${script}" "${KT_TEST_ENV}")
  local -a benchmark_cmd=(
    python "${KT_BENCHMARK_PATH}"
      --num-prompts "${KT_RECORD_NUM_PROMPTS}"
      --concurrency "${KT_CONCURRENCY}"
      --timeout "${KT_TIMEOUT}"
      --seed "${KT_BENCHMARK_SEED}"
      --model "${KT_BENCHMARK_MODEL}"
      --label "${KT_EXPERTS_PATH} | ${stage}_seed${KT_BENCHMARK_SEED}"
  )
  local live_log="/tmp/kimi_k26_${stage}_seed${KT_BENCHMARK_SEED}.benchmark.live.log"
  local api_log="/tmp/kimi_k26_${stage}_seed${KT_BENCHMARK_SEED}.recorder_api.log"
  : > "${live_log}"
  : > "${api_log}"

  cleanup_server
  local start_utc
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  "${server_cmd[@]}" > "${server_log}" 2>&1 &
  local server_pid=$!
  if ! wait_for_server "${server_pid}" "${out}" "${server_log}"; then
    cleanup_server
    echo "BENCHMARK_EXIT_CODE: 97" >> "${out}"
    return 1
  fi

  if ! recorder_api_post start_expert_distribution_record "${api_log}"; then
    cleanup_server
    {
      echo "STAGE: ${stage}"
      echo "START_UTC: ${start_utc}"
      echo "SEED: ${KT_BENCHMARK_SEED}"
      echo "LIVE_BENCHMARK_LOG: ${live_log}"
      echo "SERVER_LOG: ${server_log}"
      cat "${api_log}"
      echo
      echo "BENCHMARK_EXIT_CODE: 96"
      echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${out}"
    return 1
  fi

  set +e
  "${benchmark_cmd[@]}" > "${live_log}" 2>&1
  local benchmark_rc=$?
  set -e

  local recorder_rc=0
  recorder_api_post stop_expert_distribution_record "${api_log}" || recorder_rc=$?
  recorder_api_post dump_expert_distribution_record "${api_log}" || recorder_rc=$?

  cleanup_server
  {
    echo "STAGE: ${stage}"
    echo "START_UTC: ${start_utc}"
    echo "SEED: ${KT_BENCHMARK_SEED}"
    echo "LIVE_BENCHMARK_LOG: ${live_log}"
    echo "SERVER_LOG: ${server_log}"
    echo
    echo "SERVER_COMMAND:"
    printf '%q ' "${server_cmd[@]}"
    echo
    echo
    echo "BENCHMARK_COMMAND:"
    printf '%q ' "${benchmark_cmd[@]}"
    echo
    cat "${api_log}"
    echo
    echo "BENCHMARK_RESULTS:"
    append_benchmark_results "${live_log}"
    echo "BENCHMARK_EXIT_CODE: ${benchmark_rc}"
    echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "${out}"

  if (( benchmark_rc != 0 )); then
    return "${benchmark_rc}"
  fi
  if (( recorder_rc != 0 )); then
    return "${recorder_rc}"
  fi

  python "${repo_root}/tools/combine_expert_distrbution_recordings.py" "${combine_dir}" >> "${out}" 2>&1
}

refresh_latest_expert_location() {
  local recorder_dir="${repo_root}/experts/${EXPERTS_PATH}/02"
  latest_expert_location="$(latest_combined_expert "${recorder_dir}")"
  if [[ -z "${latest_expert_location}" ]]; then
    echo "No combined expert_distribution_recorder_*.pt files found in ${recorder_dir}" >&2
    exit 1
  fi
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

  if successful_result "${out}" "${KT_SWEEP_NUM_PROMPTS}"; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SKIP test${id}_${label} already completed successfully"
    return 0
  fi

  archive_failed_result "${out}"
  archive_failed_result "${server_log}"

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
      --num-prompts "${KT_SWEEP_NUM_PROMPTS}"
      --concurrency "${KT_CONCURRENCY}"
      --timeout "${KT_TIMEOUT}"
      --seed "${KT_BENCHMARK_SEED}"
      --model "${KT_BENCHMARK_MODEL}"
      --label "${KT_EXPERTS_PATH} | test${id}_${label} | seed${KT_BENCHMARK_SEED}"
  )

  notify_test_start \
    "${id}" \
    "${label}" \
    "${kt_cpuinfer}" \
    "${kt_threadpool_count}" \
    "${kt_num_gpu_experts}" \
    "${kt_deferred}" \
    "${mem_fraction_static}" \
    "${chunked_prefill_size}" \
    "${extra_args}"

  local attempt
  for attempt in $(seq 1 "${MAX_TEST_ATTEMPTS}"); do
    local safe_label="${label//[^A-Za-z0-9_.-]/_}"
    local live_log="/tmp/kimi_k26_test${id}_${safe_label}_attempt${attempt}_seed${KT_BENCHMARK_SEED}.benchmark.live.log"
    : > "${live_log}"
    cleanup_server
    if (( attempt > 1 )); then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] RETRY test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      sleep 20
    fi
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"

    local start_utc
    start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    "${cmd[@]}" > "${server_log}" 2>&1 &
    local server_pid=$!
    if ! wait_for_server "${server_pid}" "${out}" "${server_log}"; then
      cleanup_server
      echo "ATTEMPT_RESULT: READY_FAIL" >> "${out}"
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] READY_FAIL test${id}_${label} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      notify_test_failure_attempt "${id}" "${attempt}"
      if (( attempt == MAX_TEST_ATTEMPTS )); then
        echo "BENCHMARK_EXIT_CODE: 98" >> "${out}"
        echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${out}"
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FINAL_READY_FAIL_CONTINUE test${id}_${label}"
        return 0
      fi
      archive_failed_result "${out}"
      archive_failed_result "${server_log}"
      continue
    fi

    set +e
    "${benchmark_cmd[@]}" > "${live_log}" 2>&1
    local benchmark_rc=$?
    set -e

    cleanup_server
    {
      echo "TEST: test${id}_${label}"
      echo "ATTEMPT: ${attempt}/${MAX_TEST_ATTEMPTS}"
      echo "START_UTC: ${start_utc}"
      echo "SEED: ${KT_BENCHMARK_SEED}"
      echo "EXPERT_FILE: ${latest_expert_location}"
      echo "LIVE_BENCHMARK_LOG: ${live_log}"
      echo "SERVER_LOG: ${server_log}"
      echo
      echo "SGLANG_COMMAND:"
      printf '%q ' "${cmd[@]}"
      echo
      echo
      echo "BENCHMARK_COMMAND:"
      printf '%q ' "${benchmark_cmd[@]}"
      echo
      echo
      echo "BENCHMARK_RESULTS:"
      append_benchmark_results "${live_log}"
      echo "BENCHMARK_EXIT_CODE: ${benchmark_rc}"
      echo "END_UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${out}"

    if (( benchmark_rc == 0 )) && successful_result "${out}" "${KT_SWEEP_NUM_PROMPTS}"; then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DONE test${id}_${label} benchmark_rc=${benchmark_rc} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
      notify_test_success "${id}" "${out}"
      return 0
    fi

    echo "ATTEMPT_RESULT: BENCHMARK_FAIL rc=${benchmark_rc}" >> "${out}"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] BENCHMARK_FAIL test${id}_${label} benchmark_rc=${benchmark_rc} attempt=${attempt}/${MAX_TEST_ATTEMPTS}"
    notify_test_failure_attempt "${id}" "${attempt}"
    if (( attempt == MAX_TEST_ATTEMPTS )); then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FINAL_BENCHMARK_FAIL_CONTINUE test${id}_${label} benchmark_rc=${benchmark_rc}"
      return 0
    fi
    archive_failed_result "${out}"
    archive_failed_result "${server_log}"
  done
}

write_seed_profile
run_record_stage record01 "${repo_root}/02_record.sh" "${repo_root}/experts/${EXPERTS_PATH}/01"
run_record_stage record02 "${repo_root}/03_record.sh" "${repo_root}/experts/${EXPERTS_PATH}/02"
refresh_latest_expert_location

COMMON="--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 131072"
GRAPH2="--cuda-graph-max-bs 2 --cuda-graph-bs 1 2"
GRAPH4="--cuda-graph-max-bs 4 --cuda-graph-bs 1 2 4"
GRAPH8="--cuda-graph-max-bs 8 --cuda-graph-bs 1 2 4 8"
FAST_BACKEND="--disable-custom-all-reduce"
NVLS="--enable-nccl-nvls"
FLASHINFER_BACKEND="--prefill-attention-backend flashinfer --decode-attention-backend flashinfer --sampling-backend flashinfer"
TRITON_PREFILL_BACKEND="--prefill-attention-backend triton --decode-attention-backend fa3 --sampling-backend flashinfer"

dynamic_post25_anchors() {
  python - "${RESULTS_DIR}" "${KT_SWEEP_NUM_PROMPTS}" "${KT_DYNAMIC_POST25_TOP_N}" "${KT_DYNAMIC_POST25_SOURCE_LAST}" <<'PY'
import re
import sys
from pathlib import Path

results_dir = Path(sys.argv[1])
expected_requests = sys.argv[2]
top_n = int(sys.argv[3])
source_last = int(sys.argv[4])
rows = []

def flag_value(txt, flag):
    match = re.search(rf"{re.escape(flag)}\s+(\S+)", txt)
    return match.group(1) if match else ""

for path in sorted(results_dir.glob("test*.txt")):
    try:
        test_num = int(path.stem[4:])
    except ValueError:
        continue
    if not (1 <= test_num <= source_last):
        continue

    txt = path.read_text(errors="replace")
    if "BENCHMARK_EXIT_CODE: 0" not in txt:
        continue
    if not re.search(rf"Successful requests:\s+{expected_requests}/{expected_requests}", txt):
        continue

    ttft = re.search(
        r"^Reasoning:\n  Mean:\s*([0-9]+)ms\n  Median:\s*([0-9]+)ms\n  P95:\s*([0-9]+)ms\n  P99:\s*([0-9]+)ms",
        txt,
        re.M,
    )
    if not ttft:
        continue

    output = re.search(r"^  Output tokens/sec:\s*([0-9.]+)", txt, re.M)
    test = re.search(r"^TEST:\s*(\S+)", txt, re.M)
    label = (test.group(1) if test else path.stem).removeprefix(f"test{test_num:03d}_")
    rows.append(
        {
            "test_num": test_num,
            "source_test": f"test{test_num:03d}",
            "label": label,
            "mean_ms": int(ttft.group(1)),
            "median_ms": int(ttft.group(2)),
            "p95_ms": int(ttft.group(3)),
            "p99_ms": int(ttft.group(4)),
            "output": output.group(1) if output else "n/a",
            "cpuinfer": flag_value(txt, "--kt-cpuinfer"),
            "threadpools": flag_value(txt, "--kt-threadpool-count"),
            "gpu_experts": flag_value(txt, "--kt-num-gpu-experts"),
            "deferred": flag_value(txt, "--kt-max-deferred-experts-per-token"),
            "mem": flag_value(txt, "--mem-fraction-static"),
            "chunk": flag_value(txt, "--chunked-prefill-size"),
            "threshold": flag_value(txt, "--kt-gpu-prefill-token-threshold"),
        }
    )

if rows:
    min_mean = min(row["mean_ms"] for row in rows)
    ttft_tolerance_ms = max(250, int(min_mean * 0.005))
    rows.sort(
        key=lambda row: (
            0 if row["mean_ms"] <= min_mean + ttft_tolerance_ms else 1,
            -float(row["output"] if row["output"] != "n/a" else 0),
            row["p95_ms"],
            row["median_ms"],
            row["mean_ms"],
            row["test_num"],
        )
    )
for rank, row in enumerate(rows[:top_n], start=1):
    required = ["cpuinfer", "threadpools", "gpu_experts", "deferred", "mem", "chunk", "threshold"]
    if any(not row[key] for key in required):
        continue
    print(
        "\t".join(
            [
                str(rank),
                row["source_test"],
                row["label"],
                row["cpuinfer"],
                row["threadpools"],
                row["gpu_experts"],
                row["deferred"],
                row["mem"],
                row["chunk"],
                row["threshold"],
                str(row["mean_ms"]),
                str(row["median_ms"]),
                str(row["p95_ms"]),
                row["output"],
            ]
        )
    )
PY
}

safe_label_part() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

adjust_mem_fraction() {
  local mem="$1"
  local delta="$2"

  awk -v mem="${mem}" -v delta="${delta}" 'BEGIN {
    value = mem + delta
    if (value < 0.70) value = 0.70
    if (value > 0.90) value = 0.90
    printf "%.2f", value
  }'
}

piecewise_tokens_for_chunk() {
  local chunk="$1"
  local -a tokens=(1024 2048 4096 8192 12288 16384)
  local token
  local found=0

  for token in "${tokens[@]}"; do
    if [[ "${token}" == "${chunk}" ]]; then
      found=1
      break
    fi
  done

  if (( found == 0 )); then
    tokens+=("${chunk}")
  fi

  printf '%s ' "${tokens[@]}"
}

run_dynamic_post25_case() {
  local id="$1"
  local label="$2"
  local kt_cpuinfer="$3"
  local kt_threadpool_count="$4"
  local kt_num_gpu_experts="$5"
  local kt_deferred="$6"
  local mem_fraction_static="$7"
  local chunked_prefill_size="$8"
  local extra_args="$9"
  local id_num

  id_num=$((10#${id}))
  if (( id_num < first_test_num || id_num > last_test_num )); then
    return 0
  fi

  run_test \
    "${id}" \
    "${label}" \
    "${kt_cpuinfer}" \
    "${kt_threadpool_count}" \
    "${kt_num_gpu_experts}" \
    "${kt_deferred}" \
    "${mem_fraction_static}" \
    "${chunked_prefill_size}" \
    "${extra_args}"
}

dynamic_post25_assign_next_id() {
  local target_var="$1"
  printf -v "${target_var}" '%03d' "${dynamic_post25_id}"
  dynamic_post25_id=$((dynamic_post25_id + 1))
}

run_dynamic_post25_overlay_set() {
  local rank="$1"
  local source_test="$2"
  local source_label="$3"
  local kt_cpuinfer="$4"
  local kt_threadpool_count="$5"
  local kt_num_gpu_experts="$6"
  local kt_deferred="$7"
  local mem_fraction_static="$8"
  local chunked_prefill_size="$9"
  local threshold="${10}"
  local source_num="${source_test#test}"
  local source_part
  local base_extra
  local piecewise_tokens
  local id

  source_part="$(safe_label_part "r${rank}_${source_num}")"
  base_extra="${COMMON} --kt-gpu-prefill-token-threshold ${threshold}"
  piecewise_tokens="$(piecewise_tokens_for_chunk "${chunked_prefill_size}")"

  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_fast_backend" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} ${FAST_BACKEND}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_nvls" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} ${NVLS}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_fast_nvls" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} ${FAST_BACKEND} ${NVLS}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_flashinfer" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} ${FLASHINFER_BACKEND}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_triton_prefill" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} ${TRITON_PREFILL_BACKEND}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_graph4" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH4}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_graph8" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH8}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_graph_off" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} --disable-cuda-graph"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_graph4_fast" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH4} ${FAST_BACKEND}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_disable_graph_padding" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --disable-cuda-graph-padding"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_piecewise_graph" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --enable-piecewise-cuda-graph --piecewise-cuda-graph-tokens ${piecewise_tokens}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_prefill_max_requests1" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --prefill-max-requests 1"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_prefill_max_requests2" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --prefill-max-requests 2"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_schedule_fcfs" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --schedule-policy fcfs"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_dynamic_expert_update" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --kt-enable-dynamic-expert-update"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_tokenizer_batch_encode" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --enable-tokenizer-batch-encode"

  # This keeps shellcheck quiet for source_label while preserving it in the TSV summary.
  [[ -n "${source_label}" ]]
}

run_dynamic_post25_top_anchor_deep_dive() {
  local rank="$1"
  local source_test="$2"
  local kt_cpuinfer="$3"
  local kt_threadpool_count="$4"
  local kt_num_gpu_experts="$5"
  local kt_deferred="$6"
  local mem_fraction_static="$7"
  local chunked_prefill_size="$8"
  local threshold="$9"
  local source_num="${source_test#test}"
  local source_part
  local base_extra
  local mem_down
  local mem_up
  local id

  source_part="$(safe_label_part "r${rank}_${source_num}")"
  base_extra="${COMMON} --kt-gpu-prefill-token-threshold ${threshold}"
  mem_down="$(adjust_mem_fraction "${mem_fraction_static}" -0.02)"
  mem_up="$(adjust_mem_fraction "${mem_fraction_static}" 0.02)"

  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_exp128" "${kt_cpuinfer}" "${kt_threadpool_count}" 128 "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_exp112" "${kt_cpuinfer}" "${kt_threadpool_count}" 112 "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_exp096" "${kt_cpuinfer}" "${kt_threadpool_count}" 96 "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_mem_down" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_down}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_mem_up" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_up}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_cpu08" 8 "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_cpu12" 12 "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_cpu20" 20 "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_cpu24" 24 "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_deferred3" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" 3 "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_deferred4" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" 4 "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_threadpool2" "${kt_cpuinfer}" 2 "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_maxrun1" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 1 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold ${threshold} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_maxrun3_graph4" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 3 --max-total-tokens 131072 --kt-gpu-prefill-token-threshold ${threshold} ${GRAPH4}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_max_total_98304" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 98304 --kt-gpu-prefill-token-threshold ${threshold} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_max_total_196608" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "--tool-call-parser kimi_k2 --reasoning-parser kimi_k2 --max-running-requests 2 --max-total-tokens 196608 --kt-gpu-prefill-token-threshold ${threshold} ${GRAPH2}"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_max_prefill_32768" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_down}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --max-prefill-tokens 32768"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_attention_fa3" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --attention-backend fa3 --sampling-backend flashinfer --disable-custom-all-reduce"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_flashinfer_allreduce" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --enable-flashinfer-allreduce-fusion"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_symm_mem" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --enable-symm-mem"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_tokenizer_workers2" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --tokenizer-worker-num 2"
  dynamic_post25_assign_next_id id; run_dynamic_post25_case "${id}" "${source_part}_tokenizer_workers4" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${base_extra} ${GRAPH2} --tokenizer-worker-num 4"
}

run_dynamic_post25() {
  local -a anchors=()
  local anchor_file="${RESULTS_DIR}/dynamic_post25_anchors_seed${KT_BENCHMARK_SEED}.tsv"
  local row rank source_test source_label kt_cpuinfer kt_threadpool_count kt_num_gpu_experts kt_deferred mem_fraction_static chunked_prefill_size threshold mean_ms median_ms p95_ms output_toks
  local top_rank top_source_test top_source_label top_cpuinfer top_threadpool top_gpu_experts top_deferred top_mem top_chunk top_threshold top_mean_ms top_median_ms top_p95_ms top_output_toks

  mapfile -t anchors < <(dynamic_post25_anchors)
  if (( ${#anchors[@]} == 0 )); then
    echo "No successful first-${KT_DYNAMIC_POST25_SOURCE_LAST} anchors available for dynamic post-25 sweep" >&2
    return 2
  fi

  {
    echo -e "rank\tsource_test\tsource_label\tcpuinfer\tthreadpools\tgpu_experts\tdeferred\tmem\tchunk\tthreshold\tmean_ms\tmedian_ms\tp95_ms\toutput_toks_per_s"
    printf '%s\n' "${anchors[@]}"
  } > "${anchor_file}"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DYNAMIC_POST25 anchors=${#anchors[@]} anchor_file=${anchor_file}"

  dynamic_post25_id=$((10#${KT_DYNAMIC_POST25_START}))
  for row in "${anchors[@]}"; do
    IFS=$'\t' read -r rank source_test source_label kt_cpuinfer kt_threadpool_count kt_num_gpu_experts kt_deferred mem_fraction_static chunked_prefill_size threshold mean_ms median_ms p95_ms output_toks <<< "${row}"
    if [[ "${rank}" == "1" ]]; then
      top_rank="${rank}"
      top_source_test="${source_test}"
      top_source_label="${source_label}"
      top_cpuinfer="${kt_cpuinfer}"
      top_threadpool="${kt_threadpool_count}"
      top_gpu_experts="${kt_num_gpu_experts}"
      top_deferred="${kt_deferred}"
      top_mem="${mem_fraction_static}"
      top_chunk="${chunked_prefill_size}"
      top_threshold="${threshold}"
      top_mean_ms="${mean_ms}"
      top_median_ms="${median_ms}"
      top_p95_ms="${p95_ms}"
      top_output_toks="${output_toks}"
    fi
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DYNAMIC_POST25_ANCHOR rank=${rank} source=${source_test} chunk=${chunked_prefill_size} threshold=${threshold} mem=${mem_fraction_static} mean_ms=${mean_ms}"
    if (( 10#${rank} <= KT_DYNAMIC_POST25_OVERLAY_TOP_N )); then
      run_dynamic_post25_overlay_set "${rank}" "${source_test}" "${source_label}" "${kt_cpuinfer}" "${kt_threadpool_count}" "${kt_num_gpu_experts}" "${kt_deferred}" "${mem_fraction_static}" "${chunked_prefill_size}" "${threshold}"
    else
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DYNAMIC_POST25_SKIP_OVERLAY rank=${rank} source=${source_test} reason=overlay_top_n_${KT_DYNAMIC_POST25_OVERLAY_TOP_N}"
    fi
  done

  if [[ -n "${top_source_test:-}" ]]; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DYNAMIC_POST25_DEEP_DIVE source=${top_source_test} chunk=${top_chunk} threshold=${top_threshold} mean_ms=${top_mean_ms}"
    run_dynamic_post25_top_anchor_deep_dive "${top_rank}" "${top_source_test}" "${top_cpuinfer}" "${top_threadpool}" "${top_gpu_experts}" "${top_deferred}" "${top_mem}" "${top_chunk}" "${top_threshold}"
    [[ -n "${top_source_label}" && -n "${top_median_ms}" && -n "${top_p95_ms}" && -n "${top_output_toks}" ]]
  fi
}

if [[ ! "${KT_FIRST_TEST}" =~ ^[0-9][0-9][0-9]$ ]] || [[ ! "${KT_LAST_TEST}" =~ ^[0-9][0-9][0-9]$ ]]; then
  echo "KT_FIRST_TEST and KT_LAST_TEST must be three-digit test ids, got ${KT_FIRST_TEST}-${KT_LAST_TEST}" >&2
  exit 2
fi

if [[ ! -f "${KT_PLAN_FILE}" ]]; then
  echo "Plan file not found: ${KT_PLAN_FILE}" >&2
  exit 2
fi

first_test_num=$((10#${KT_FIRST_TEST}))
last_test_num=$((10#${KT_LAST_TEST}))
if (( first_test_num > last_test_num )); then
  echo "KT_FIRST_TEST must be <= KT_LAST_TEST, got ${KT_FIRST_TEST}-${KT_LAST_TEST}" >&2
  exit 2
fi

mapfile -t PLAN_RUN_TESTS < <(awk '/^run_test [0-9][0-9][0-9] / {print NR "\t" $0}' "${KT_PLAN_FILE}")
if (( ${#PLAN_RUN_TESTS[@]} < 100 )); then
  echo "Expected at least 100 run_test lines in ${KT_PLAN_FILE}, found ${#PLAN_RUN_TESTS[@]}" >&2
  exit 2
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PLAN_FILE ${KT_PLAN_FILE} tests=${#PLAN_RUN_TESTS[@]} range=${KT_FIRST_TEST}-${KT_LAST_TEST}"

for plan_entry in "${PLAN_RUN_TESTS[@]}"; do
  plan_line_no="${plan_entry%%$'\t'*}"
  plan_line="${plan_entry#*$'\t'}"
  if [[ ! "${plan_line}" =~ ^run_test[[:space:]]+([0-9][0-9][0-9])[[:space:]] ]]; then
    echo "Invalid run_test line ${plan_line_no}: ${plan_line}" >&2
    exit 2
  fi
  plan_test_id="${BASH_REMATCH[1]}"
  plan_test_num=$((10#${plan_test_id}))
  if [[ "${KT_DYNAMIC_POST25}" == "1" ]] && (( plan_test_num >= 10#${KT_DYNAMIC_POST25_START} )); then
    continue
  fi
  if (( plan_test_num < first_test_num || plan_test_num > last_test_num )); then
    continue
  fi

  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PLAN_RUN test${plan_test_id} line=${plan_line_no}"
  set +e
  eval "${plan_line}"
  plan_rc=$?
  set -e
  if (( plan_rc != 0 )); then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] PLAN_FAIL test${plan_test_id} line=${plan_line_no} rc=${plan_rc}" >&2
    exit "${plan_rc}"
  fi
done

if [[ "${KT_DYNAMIC_POST25}" == "1" ]] && (( last_test_num >= 10#${KT_DYNAMIC_POST25_START} )); then
  run_dynamic_post25
fi
