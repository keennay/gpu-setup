---
name: "LLM Inference Bench Setup"
description: "Sets up llm-inference-bench and env_custom-uv, enables context sweeps beyond 128K, and benchmarks a running SGLang or vLLM instance using a supplied model context limit and launcher-derived output naming; reports completion or early failure."
alwaysApply: false
---

# LLM Inference Bench Setup

Use this skill to prepare and run `llm_decode_bench.py` against an **already running** SGLang or vLLM instance, normally after an inference launch script has reached API readiness.

Skill directory: `llm-inference-bench-creation-and-update`.

## Scope and required inputs

The caller MUST supply, for each model/run:

- `launch_script`: the inference script used to start this instance, wherever it is located.
- `model_context_limit`: the explicit context limit in tokens for this model/run. Never infer it from a model name, GPU memory, or a previous model's benchmark. Normalize supplied units before calculating: `k`/`K` = 1,024 tokens; `m`/`M` = 1,048,576 tokens. A bare integer is an exact token count, not a rounded marketing label.
- `gpu_type`: the supplied filename label, such as `h200`. Do not guess this label from the machine's inventory.

Read the launch script and any referenced configuration needed to obtain GPU quantity, server port, API key, host, and served model name. Resolve actual launch arguments/interactive selections from the known invocation or launch logs rather than assuming defaults were used. Request only required inputs that remain unavailable; do not start a guessed benchmark.

This skill does not create or retune an inference recipe, change an engine environment, perform a GPU-memory sweep, restart the inference server, or stop it after the benchmark. Changes are confined to the benchmark checkout, its custom Python environment, and benchmark output. Broader recipe work requires a separate explicit request and the applicable recipe/source skills.

Creating, updating, or inspecting this skill is **not** authorization to run a benchmark or create benchmark result files. Execute the run workflow only when the caller explicitly requests a benchmark against a running instance and the required inputs are available.

## 1. Check the benchmark directory first

Before any benchmark import, patch, help command, or run, check:

```text
$HOME/llm-inference-bench
```

- If the directory is absent, clone exactly `https://github.com/local-inference-lab/llm-inference-bench.git` into that path, not into the current recipes directory and not into a nested `llm-inference-bench/llm-inference-bench` directory.
- If it exists, reuse it and preserve local changes. Do not automatically pull, reset, clean, reclone, or overwrite it.
- If the path is a file/broken link, or the directory lacks `llm_decode_bench.py`, report a setup failure; do not delete the conflicting path.
- Use the checkout's own `README.md`, dependency declarations when present, and `llm_decode_bench.py` as the authority for its installed CLI and behavior. Inspect the current source rather than assuming upstream line numbers are stable.

## 2. Prepare the exact custom UV environment

Use only:

```text
$HOME/env_custom-uv/bin/python
```

Reuse `$HOME/env_custom-uv` if usable. If absent, create it with `uv venv` and Python 3.10 or newer. The hyphenated `env_custom-uv` path is intentional: do not substitute `env_custom_uv`, a system interpreter, or the inference server's environment. Do not replace an existing unusable directory automatically.

The upstream benchmark documents `httpx`, `rich`, and `psutil`. Ensure these imports work in this environment, installing missing dependencies with `uv pip install --python "$HOME/env_custom-uv/bin/python" ...`. Resolve any additional demonstrated missing package against the current checkout's dependency instructions, install into this same environment, and recheck imports. Do not unnecessarily upgrade already working packages or install into an engine environment. `uv` and `git` must be available; report an unresolved setup prerequisite rather than continuing with another environment.

The following setup sequence is idempotent for a valid existing checkout/environment. With OMP tools, run conditional shell blocks through Eval/subprocess rather than a complex Bash tool call.

```bash
set -e
BENCH_REPO="$HOME/llm-inference-bench"
BENCH_ENV="$HOME/env_custom-uv"

if [ ! -d "$BENCH_REPO" ]; then
    if [ -e "$BENCH_REPO" ] || [ -L "$BENCH_REPO" ]; then
        printf '%s\n' "Setup failed: $BENCH_REPO exists but is not a usable directory." >&2
        exit 1
    fi
    git clone https://github.com/local-inference-lab/llm-inference-bench.git "$BENCH_REPO"
fi
if [ ! -f "$BENCH_REPO/llm_decode_bench.py" ]; then
    printf '%s\n' "Setup failed: llm_decode_bench.py is missing from $BENCH_REPO." >&2
    exit 1
fi

if [ ! -e "$BENCH_ENV" ] && [ ! -L "$BENCH_ENV" ]; then
    uv venv --python '>=3.10' "$BENCH_ENV"
fi
if [ ! -x "$BENCH_ENV/bin/python" ]; then
    printf '%s\n' "Setup failed: $BENCH_ENV is not a usable Python environment." >&2
    exit 1
fi
"$BENCH_ENV/bin/python" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else "Python 3.10+ is required")'
uv pip install --python "$BENCH_ENV/bin/python" httpx rich psutil
"$BENCH_ENV/bin/python" -c 'import httpx, rich, psutil'
```

## 3. Calculate the model-specific context lists

Recalculate for **every model/run**. The ordered standard points start at 8K and double:

```text
8k,16k,32k,64k,128k,256k,512k,1024k,...
```

Include **256k**. Do not skip it between 128k and 512k. Keep every standard point up to the endpoint, then append the exact endpoint if it is not already present. Do not insert 0K, duplicate endpoints, round an endpoint upward, or cap the ladder at 128K/1024K when the supplied limit is larger.

Use precisely:

```text
decode_contexts = context_points(model_context_limit - 4096 - 1024)
prefill_contexts = context_points(model_context_limit)
```

The decode reserve is 4,096 generation tokens plus 1,024 safety tokens. Do not subtract it from the prefill sweep. Both formulas use the same `model_context_limit`.

Reference calculation, with integer token counts:

```python
def context_points(limit: int) -> list[int]:
    if limit < 8 * 1024:
        raise ValueError("Context budget cannot support the required 8K starting point")
    points = []
    point = 8 * 1024
    while point <= limit:
        points.append(point)
        point *= 2
    if points[-1] != limit:
        points.append(limit)
    return points


def context_csv(points: list[int]) -> str:
    return ",".join(f"{point // 1024}k" if point % 1024 == 0 else str(point) for point in points)


def benchmark_contexts(model_context_limit: int) -> tuple[str, str]:
    decode_contexts = context_points(model_context_limit - 4096 - 1024)
    prefill_contexts = context_points(model_context_limit)
    return context_csv(decode_contexts), context_csv(prefill_contexts)
```

If the decode budget is below 8,192 tokens, report that this sweep cannot run as specified; do not silently introduce a smaller starting point. For a non-K-aligned limit, keep the final point as an exact decimal token count.

Required examples:

| Model context limit | `--contexts` | `--prefill-contexts` |
| --- | --- | --- |
| 131072 (128K) | `8k,16k,32k,64k,123k` | `8k,16k,32k,64k,128k` |
| 262144 (256K) | `8k,16k,32k,64k,128k,251k` | `8k,16k,32k,64k,128k,256k` |
| 524288 (512K) | `8k,16k,32k,64k,128k,256k,507k` | `8k,16k,32k,64k,128k,256k,512k` |
| 1048576 (1M / 1024K) | `8k,16k,32k,64k,128k,256k,512k,1019k` | `8k,16k,32k,64k,128k,256k,512k,1024k` |

## 4. Enable long contexts in the benchmark checkout

Inspect and, where necessary, edit **`$HOME/llm-inference-bench/llm_decode_bench.py`**, not an installed engine module or the inference recipe.

Both `--contexts` and `--prefill-contexts` MUST accept comma-separated integer/K-suffixed values beyond 128K, including 256k, 512k, 1019k, and 1024k. Reuse existing flags and token parsing; do not add duplicate arguments. Current upstream `parse_token_value` already handles arbitrary K-suffixed values, so parser acceptance alone does not prove that the requested rows will run.

Inspect argument parsing, prefill/decode list construction, prompt generation, scheduling, and JSON output for fixed ceilings or silent row filtering. A known upstream prefill ceiling inside `run_benchmark` is:

```python
max_prefill = min(131072, server_context_length - 64) if server_context_length > 0 else 131072
```

When this implementation is present, replace that assignment with:

```python
max_prefill = (
    server_context_length
    if server_context_length > 0
    else max(context_lengths + PREFILL_CANDIDATES, default=0)
)
```

This removes the hard-coded 128K ceiling and retains the exact model-limit endpoint in the prefill selection. Merely removing `min(131072, ...)` while retaining `server_context_length - 64` still drops the required 256k/1024k endpoint and is incomplete. When server metadata is unavailable, use the explicitly requested points rather than a fixed 128K fallback.

Adapt the minimal change to the actual checkout if upstream has moved this code. If long-context support is already correct, preserve it; do not reapply or duplicate a patch. Leave unrelated 131072 values, scoring profiles, timeouts, benchmark defaults, concurrency, calibration, request generation, and engine/KV safety checks unchanged. Do not globally replace the number 131072.

Verify, before the load test:

- The actual parser accepts both generated argument lists and all required flags.
- Both decode and prefill selections retain their requested final endpoints, including a prefill point equal to the model limit.
- There is no remaining fixed 128K truncation on the exercised path.
- The edited Python compiles and the benchmark's `--help` works in the custom environment.

The benchmark can offer to auto-update itself before parsing arguments. **Decline the update with `n`**: accepting it can overwrite the local long-context change. Do not add an invented no-update flag. If the checkout is intentionally updated later, reinspect and revalidate the support before benchmarking.

### Full-limit prefill caveat

`--token-targeting estimate` requests approximate prompt sizes; a row label is not proof of an exact token count. Prefill probes still generate a first token, and tokenizer/chat-template overhead can cause a full-limit request to be rejected. Preserve the requested prefill endpoint and existing request safety behavior. Report actual `prompt_tokens` when available and any context-limit rejection. Do not silently reduce the endpoint, switch token-targeting modes, disable validation, or label a skipped/rejected row successful.

## 5. Resolve the running instance and output filename

Read the launcher without executing or sourcing it merely to obtain variables: sourcing a recipe can start another inference server.

For `/workspace/scripts/recipes` conventions:

- GPU quantity normally comes from `DEFAULT_TENSOR_PARALLEL_SIZE`; the resolved launch may use `TENSOR_PARALLEL_SIZE_VALUE` after an argument/interactive override.
- Port normally comes from `DEFAULT_PORT`; the resolved launch uses `INFERENCE_PORT`.
- `API_KEY` can contain the entire fragment `--api-key YOUR_API_KEY`; pass only the key value to the benchmark, not the fragment.
- `SERVED_MODEL_NAME` identifies the API model, which may differ from `MODEL_REPO`.

For other launchers, read their equivalent explicit GPU count/device selection and `--tp`/`--tensor-parallel-size`, port, and authentication configuration. GPU quantity must describe GPUs used by **this launched script/instance**, not all GPUs installed in the machine, a draft-model count, or requested benchmark concurrency. Resolve explicit launch overrides and more complex parallel layouts from the script/invocation/logs; do not guess a count from an unrelated process.

Match the actual port and API key. Use 8000 and `YOUR_API_KEY` only when they match the launch. If authentication is explicitly disabled, pass an empty key rather than inventing one. Use `--host` for a non-default endpoint and `--model` for the exact served model when auto-detection would be ambiguous. Never log a real API key in the final command/report; redact it there while passing the real value to the process.

Confirm authenticated `/v1/models` readiness and the intended served model before sending benchmark traffic. Cross-check the supplied model context against the configured running limit when it is available. A smaller running limit is a configuration mismatch to report, not permission to silently shrink the supplied sweep or restart/retune the server.

Create the output directory next to the **launch script**, not next to the benchmark program and not relative to the current shell directory:

```text
<launch-script-directory>/llm-inference-bench/<launch-script-stem>_<gpu-type>x<gpu-qty>.json
```

Remove only the launch script's final extension; preserve its other spelling, capitalization, punctuation, and variant suffixes. Validate `gpu_type` as a filename label without path separators (for example, `[A-Za-z0-9][A-Za-z0-9._-]*`) and GPU quantity as a positive integer.

Reference path construction once these inputs are resolved:

```python
import re
from pathlib import Path


def benchmark_output_path(launch_script: str, gpu_type: str, gpu_qty: int) -> Path:
    if not isinstance(gpu_type, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", gpu_type):
        raise ValueError("A supplied, filename-safe GPU type is required")
    if type(gpu_qty) is not int or gpu_qty < 1:
        raise ValueError("GPU quantity must be a positive integer resolved from the launch script")
    script = Path(launch_script).expanduser().absolute()
    return script.parent / "llm-inference-bench" / f"{script.stem}_{gpu_type}x{gpu_qty}.json"
```

Create the returned path's parent before launch. For example:

```text
/workspace/scripts/recipes/vllm_Qwen_Qwen3.8-27B-FP8.sh
  + gpu_type=h200, gpu_qty=1
  -> /workspace/scripts/recipes/llm-inference-bench/vllm_Qwen_Qwen3.8-27B-FP8_h200x1.json
```

If an output already exists, preserve it before replacing it, using a clearly identified backup. Keep the requested final filename unchanged, do not silently resume a previous benchmark, and never treat stale JSON as evidence for a new run. Record run start time and the intended output path.

## 6. Run the real benchmark

Use the custom environment's explicit interpreter, not whichever `python3` happens to be active. Required arguments are:

```bash
"$HOME/env_custom-uv/bin/python" "$HOME/llm-inference-bench/llm_decode_bench.py" \
  --port "$PORT" \
  --api-key "$API_KEY_VALUE" \
  --prefill-contexts "$PREFILL_CONTEXTS" \
  --contexts "$DECODE_CONTEXTS" \
  --max-tokens 4096 \
  --token-targeting estimate \
  --output "$OUTPUT"
```

`PORT`, `API_KEY_VALUE`, both context strings, and `OUTPUT` must already be resolved by the steps above. Preserve the upstream standard concurrency and duration unless the caller explicitly asks otherwise. Do not add `--skip-prefill`, `--prefill-only`, `--standalone-prefill`, reduced contexts, or a short benchmark as a substitute for the requested run.

The current default prefill mode combines nonzero decode scout contexts with the supplied `--prefill-contexts`. Consequently a 1M run can also contain a 1019K integrated-prefill row in addition to the requested prefill ladder ending at 1024K; this is not a reason to remove either endpoint or change measurement mode.

Concrete 256K example, only when these launcher values match the instance:

```bash
"$HOME/env_custom-uv/bin/python" "$HOME/llm-inference-bench/llm_decode_bench.py" \
  --port 8000 \
  --api-key YOUR_API_KEY \
  --prefill-contexts 8k,16k,32k,64k,128k,256k \
  --contexts 8k,16k,32k,64k,128k,251k \
  --max-tokens 4096 \
  --token-targeting estimate \
  --output /workspace/scripts/recipes/llm-inference-bench/vllm_Qwen_Qwen3.8-27B-FP8_h200x1.json
```

Under OMP, run the interactive/long-lived benchmark through a supervised `hub start` process with its actual interpreter and argument vector. Observe logs/TUI, decline self-updates and stale-run resume prompts, retain process output, and wait for completion. Process creation is not success. Do not kill the inference server when the benchmark exits or fails. Sequentially benchmark distinct models/configurations; concurrent load tests against one instance contaminate results.

## 7. Decide success versus early failure

Always inspect **both process outcome and fresh benchmark results**. Current upstream can return exit code 0 after a connection failure with `No results collected.`, and can save partial JSON after interruption. Neither exit code 0 nor `Results saved` alone proves success.

Inspect the current checkout's output schema. Known fields include `metadata`, `results`, `prefill`, `event_log`, and `startup_diagnostics.args`. Decode cells can contain `failure_reason`, `num_errors`, `loop_detected`, `capacity_limited`, and negative `aggregate_tps` sentinels. Some capacity-skipped cells are omitted from exported `results`, so reconcile coverage with logs/events and the expected context/concurrency matrix; do not simply demand that the number of JSON rows equals the raw matrix size.

Classify the run explicitly:

- **SUCCESS**: normal completion; fresh, parseable JSON at the requested path matching this model and invocation; actual decode measurements cover every requested context at runnable concurrency; every requested prefill context has a valid sample, including the final endpoint; no unexplained missing work, request errors, or loop-invalid measurements. Report legitimate capacity/concurrency skips explicitly instead of calling them measured cells.
- **FAILED EARLY**: setup/dependency/patch/readiness failure, authentication or connection failure, context rejection, crash, interruption, timeout, or exit before the requested sweep finishes. Give the failing stage, exit code when launched, exact first relevant error, last completed context/concurrency if any, and whether partial JSON/checkpoint files exist. If not launched, state that clearly.
- **FAILED / COMPLETED WITH ERRORS**: the process finished, but required contexts/prefill endpoints are missing or only skipped, measurements are invalid, or request/loop errors remain. Distinguish this from an early exit; do not present it as an unqualified success.

If estimated full-limit prefill fails, report that failure rather than quietly omitting the endpoint. Keep genuine partial output for diagnosis; do not invent an empty success JSON, rewrite error measurements into successful ones, or delete a user's benchmark checkout/environment after a failed run.

## Final report

Lead with **SUCCESS**, **FAILED EARLY**, or **FAILED / COMPLETED WITH ERRORS**, followed by:

- Inference launch script, served model/engine, supplied context limit, host/port, and GPU label/count with its launcher source.
- Exact decode and prefill argument lists and the fixed `--max-tokens 4096 --token-targeting estimate` settings.
- Checkout reused/cloned, long-context edit applied/already supported, environment reused/created, and packages installed.
- Actual command with any real API key redacted, exit status, and whether the run completed normally.
- Absolute JSON output path and whether it is fresh, valid, complete, or partial; any preserved prior-output backup.
- Highest requested versus successfully measured decode/prefill contexts, relevant actual prompt-token counts, and any skipped or failed cells.
- For failure: stage, first relevant error, progress reached, and partial-output/checkpoint location or explicit absence.

Do not claim that a benchmark ran when only setup, parser checks, or command preparation were performed.
