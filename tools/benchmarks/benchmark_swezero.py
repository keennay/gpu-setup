import argparse
import asyncio
import json
import os
import random
import statistics
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

HELPERS_DIR = Path(__file__).resolve().parent / "helpers"
if str(HELPERS_DIR) not in sys.path:
    sys.path.insert(0, str(HELPERS_DIR))

from benchmark_sglang_metrics import (
    SGLangBatchMetricsCollector,
    calculate_sglang_stage_throughput,
    fetch_sglang_metrics_snapshot,
    fetch_sglang_model_metadata,
    prompt_continue_without_sglang_logs,
    print_sglang_batch_throughput_report,
    print_sglang_metrics_report,
    sglang_display_model_name,
)


DEFAULT_DATASET_REPO_ID = "AlienKevin/SWE-ZERO-12M-trajectories"
DEFAULT_DATASET_CACHE_DIR = "datasets--AlienKevin--SWE-ZERO-12M-trajectories"
DEFAULT_PREFIX_INDEX_CACHE_DIR = f"{DEFAULT_DATASET_CACHE_DIR}-prefix-index"
INPUT_BAND_CHOICES = ("1k", "2k", "4k", "8k", "12k", "16k", "20k")
INPUT_BAND_RANGES = {
    "1k": (1000, 2000),
    "2k": (2000, 3000),
    "4k": (4000, 5000),
    "8k": (8000, 9000),
    "12k": (12000, 13000),
    "16k": (16000, 17000),
    "20k": (20000, 21000),
}
INPUT_BAND_HELP = "Select between " + ", ".join(INPUT_BAND_CHOICES)
FULL_PREFIX_SENTINEL = 65535


@dataclass(frozen=True)
class TokenBucket:
    name: str
    min_tokens: int
    max_tokens: int
    weight: float


INPUT_TOKEN_BUCKETS = [
    TokenBucket("short_trace", 2000, 6000, 0.25),
    TokenBucket("standard_trace", 6000, 14000, 0.50),
    TokenBucket("long_trace", 14000, 24000, 0.20),
    TokenBucket("deep_trace", 24000, 32768, 0.05),
]

OUTPUT_TOKEN_BUCKETS = [
    TokenBucket("small_patch", 80, 400, 0.60),
    TokenBucket("standard_patch", 400, 1200, 0.32),
    TokenBucket("large_patch", 1200, 3000, 0.08),
]

INPUT_BUCKET_DESCRIPTIONS = {
    "short_trace": "Short SWE-ZERO agent trajectory context",
    "standard_trace": "Typical SWE-ZERO multi-turn agent trajectory",
    "long_trace": "Long SWE-ZERO investigation with broader repo context",
    "deep_trace": "Long-tail near-cap SWE-ZERO trajectory",
}

OUTPUT_BUCKET_DESCRIPTIONS = {
    "small_patch": "Concise next agent action",
    "standard_patch": "Normal next action with moderate reasoning",
    "large_patch": "Longer next action with expanded investigation context",
}

DEFAULT_MIN_INPUT = min(bucket.min_tokens for bucket in INPUT_TOKEN_BUCKETS)
DEFAULT_MAX_INPUT = max(bucket.max_tokens for bucket in INPUT_TOKEN_BUCKETS)
DEFAULT_MIN_OUTPUT = min(bucket.min_tokens for bucket in OUTPUT_TOKEN_BUCKETS)
DEFAULT_MAX_OUTPUT = max(bucket.max_tokens for bucket in OUTPUT_TOKEN_BUCKETS)


def resolve_required_hf_hub_cache() -> tuple[Path | None, str]:
    value = os.environ.get("HF_HUB_CACHE")
    if not value:
        return None, "HF_HUB_CACHE is not set"
    return Path(value).expanduser(), ""


def is_swezero_dataset_root(path: Path) -> bool:
    data_dir = path / "data"
    return data_dir.is_dir() and any(data_dir.glob("*.parquet"))


def resolve_cached_swezero_dataset() -> tuple[Path | None, list[str]]:
    hub_cache, error = resolve_required_hf_hub_cache()
    if error:
        return None, [error]

    repo_cache = hub_cache / DEFAULT_DATASET_CACHE_DIR
    snapshots_dir = repo_cache / "snapshots"
    looked = [
        f"HF_HUB_CACHE resolved to: {hub_cache}",
        f"dataset cache repo: {repo_cache}",
    ]

    if not snapshots_dir.is_dir():
        looked.append(f"snapshots directory not found: {snapshots_dir}")
        return None, looked

    refs_main = repo_cache / "refs" / "main"
    if refs_main.is_file():
        revision = refs_main.read_text().strip()
        if revision:
            snapshot = snapshots_dir / revision
            looked.append(f"refs/main snapshot: {snapshot}")
            if is_swezero_dataset_root(snapshot):
                return snapshot, looked

    snapshots = sorted(
        [path for path in snapshots_dir.iterdir() if path.is_dir()],
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for snapshot in snapshots:
        looked.append(f"snapshot candidate: {snapshot}")
        if is_swezero_dataset_root(snapshot):
            return snapshot, looked

    looked.append(f"no snapshot containing data/*.parquet found under: {snapshots_dir}")
    return None, looked


def default_prefix_index_path() -> tuple[Path | None, str]:
    hub_cache, error = resolve_required_hf_hub_cache()
    if error:
        return None, error
    return hub_cache / DEFAULT_PREFIX_INDEX_CACHE_DIR, ""


def prefix_index_build_command() -> str:
    return "python ./helpers/benchmark_build_swezero_prefix_index.py"


@dataclass
class RequestSample:
    request_id: int
    prompt: str
    messages: list[dict]
    input_len: int
    input_bucket: str
    output_len: int
    output_bucket: str
    instance_id: str
    repo: str
    exit_status: str
    shard_name: str


@dataclass(frozen=True)
class IndexedCandidate:
    approx_tokens: int
    shard_id: int
    row_in_shard: int
    prefix_end_index: int


@dataclass
class RequestResult:
    request_id: int
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_time: float = 0
    content_ttft: float = 0
    reasoning_ttft: float = 0
    input_len: int = 0
    output_len: int = 0
    input_bucket: str = ""
    output_bucket: str = ""
    finish_reason: str = ""
    success: bool = True
    error: str = None


def parse_args():
    parser = argparse.ArgumentParser(
        description="LLM Throughput Benchmark using SWE-ZERO agentic trajectories",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Example usage:
  python benchmark_swezero.py --preview-samples 2
  python benchmark_swezero.py --model kimi_k2 --num-prompts 100 --concurrency 2 --timeout 3600
  python benchmark_swezero.py --model kimi_k2 --num-prompts 1000 --seed 42
  python benchmark_swezero.py --dataset-path /path/to/SWE-ZERO-12M-trajectories --preview-samples 3
        """,
    )

    required = parser.add_argument_group("required arguments")
    required.add_argument("--model", type=str, required=False, help="Model name (required for live benchmark)")

    optional = parser.add_argument_group("optional arguments (with defaults)")
    optional.add_argument(
        "--dataset-path",
        type=str,
        default=None,
        help=(
            "Override SWE-ZERO dataset root. Default resolves "
            f"{DEFAULT_DATASET_REPO_ID} from HF_HUB_CACHE."
        ),
    )
    optional.add_argument("--api-key", type=str, default="YOUR_API_KEY", help="API key (default: YOUR_API_KEY)")
    optional.add_argument("--concurrency", type=int, default=100, help="Number of concurrent requests (default: 100)")
    optional.add_argument("--num-prompts", type=int, default=100, help="Total number of prompts to run (default: 100)")
    optional.add_argument("--base-url", type=str, default="http://localhost:8000/v1", help="API base URL (default: http://localhost:8000/v1)")
    optional.add_argument("--port", type=int, default=8000, help="API port for the default localhost base URL (default: 8000)")
    optional.add_argument("--label", dest="run_label", type=str, help="Display label for benchmark/result headers (default: model name)")
    optional.add_argument("--min-input", type=int, default=DEFAULT_MIN_INPUT, help=f"Minimum approximate input tokens (default: {DEFAULT_MIN_INPUT})")
    optional.add_argument("--max-input", type=int, default=DEFAULT_MAX_INPUT, help=f"Maximum approximate input tokens (default: {DEFAULT_MAX_INPUT})")
    optional.add_argument(
        "--input",
        dest="input_band",
        type=str,
        help=f"Use a precomputed prefix input band index. {INPUT_BAND_HELP}.",
    )
    optional.add_argument(
        "--prefix-index-path",
        type=str,
        default=None,
        help=f"Prefix input-band index path (default: HF_HUB_CACHE/{DEFAULT_PREFIX_INDEX_CACHE_DIR})",
    )
    optional.add_argument(
        "--sample-with-replacement",
        action="store_true",
        help="Allow indexed --input sampling to reuse candidates when --num-prompts exceeds the indexed pool",
    )
    optional.add_argument("--min-output", type=int, default=DEFAULT_MIN_OUTPUT, help=f"Minimum sampled max_tokens cap (default: {DEFAULT_MIN_OUTPUT})")
    optional.add_argument("--max-output", type=int, default=DEFAULT_MAX_OUTPUT, help=f"Maximum sampled max_tokens cap (default: {DEFAULT_MAX_OUTPUT})")
    optional.add_argument("--output-cap", type=int, default=None, help="Fixed max_tokens cap per request (default: sample from --min-output/--max-output)")
    optional.add_argument("--sample-output-cap", action="store_true", help=argparse.SUPPRESS)
    optional.add_argument("--temperature", "--temp", dest="temperature", type=float, default=0.2, help="Sampling temperature (default: 0.2)")
    optional.add_argument("--timeout", type=int, default=3600, help="Timeout per request in seconds (default: 3600)")
    optional.add_argument("--warmup", type=int, default=3, help="Number of warmup requests (default: 3)")
    optional.add_argument("--seed", type=int, default=None, help="Random seed for reproducible dataset sampling (default: random)")
    optional.add_argument("--exit-status", type=str, default="any", help="Filter rows by exit_status, or 'any' (default: any)")
    optional.add_argument(
        "--trajectory-mode",
        choices=("full", "prefix"),
        default="prefix",
        help="Use full trajectory or random prefix ending on a user observation (default: prefix)",
    )
    optional.add_argument(
        "--max-sample-attempts",
        type=int,
        default=2000,
        help="Maximum candidate rows to try per requested prompt before falling back (default: 2000)",
    )
    optional.add_argument("--ignore-eos", dest="ignore_eos", action="store_true", default=False, help="Force full output length by ignoring EOS (default: natural stopping)")
    optional.add_argument("--no-ignore-eos", dest="ignore_eos", action="store_false", help=argparse.SUPPRESS)
    optional.add_argument(
        "--preview-samples",
        type=int,
        default=0,
        help="Print N sampled SWE-ZERO prompts and exit without API calls (default: 0)",
    )

    args = parser.parse_args()

    errors = []
    input_range_was_explicit = any(
        arg == "--min-input"
        or arg.startswith("--min-input=")
        or arg == "--max-input"
        or arg.startswith("--max-input=")
        for arg in sys.argv[1:]
    )
    if args.run_label is not None:
        args.run_label = args.run_label.strip()
        if not args.run_label:
            errors.append("--label must not be empty")
    if args.port < 1 or args.port > 65535:
        errors.append("--port must be between 1 and 65535")
    if args.concurrency < 1:
        errors.append("--concurrency must be >= 1")
    if args.num_prompts < 1:
        errors.append("--num-prompts must be >= 1")
    if args.min_input < 1:
        errors.append("--min-input must be >= 1")
    if args.max_input < args.min_input:
        errors.append("--max-input must be >= --min-input")
    if args.min_output < 1:
        errors.append("--min-output must be >= 1")
    if args.max_output < args.min_output:
        errors.append("--max-output must be >= --min-output")
    if args.output_cap is not None and args.output_cap < 1:
        errors.append("--output-cap must be >= 1")
    if args.sample_output_cap and args.output_cap is not None:
        errors.append("--sample-output-cap cannot be combined with --output-cap")
    if args.temperature < 0:
        errors.append("--temperature/--temp must be >= 0")
    if args.max_sample_attempts < 1:
        errors.append("--max-sample-attempts must be >= 1")
    if args.preview_samples < 0:
        errors.append("--preview-samples must be >= 0")
    if args.preview_samples == 0 and not args.model:
        errors.append("--model is required unless --preview-samples is used")

    if args.dataset_path:
        dataset_root = Path(args.dataset_path).expanduser()
        if not dataset_root.exists():
            errors.append(f"--dataset-path does not exist: {dataset_root}")
        elif not is_swezero_dataset_root(dataset_root):
            errors.append(f"--dataset-path must contain a data/ directory with Parquet shards: {dataset_root}")
        else:
            args.dataset_path = str(dataset_root)
    else:
        dataset_root, lookup_notes = resolve_cached_swezero_dataset()
        if dataset_root is None:
            errors.append(
                "Unable to find default SWE-ZERO dataset in the Hugging Face Hub cache. "
                f"Expected repo cache for {DEFAULT_DATASET_REPO_ID} under HF_HUB_CACHE. "
                "Download it with: hf download AlienKevin/SWE-ZERO-12M-trajectories --repo-type dataset. "
                "Or pass --dataset-path /path/to/SWE-ZERO-12M-trajectories. "
                + " ".join(lookup_notes)
            )
        else:
            args.dataset_path = str(dataset_root)

    if args.input_band:
        args.input_band = args.input_band.strip().lower()
        if args.input_band not in INPUT_BAND_RANGES:
            errors.append(f"Invalid --input value: {args.input_band}. {INPUT_BAND_HELP}.")
        if args.trajectory_mode != "prefix":
            errors.append(
                "--input requires --trajectory-mode prefix. "
                "Reason: indexed input bands are built from prefix-mode user-ending conversation prefixes."
            )
        if input_range_was_explicit:
            errors.append("--input cannot be combined with --min-input/--max-input; it uses indexed half-open input bands.")
        if args.exit_status != "any":
            errors.append("--input currently requires --exit-status any because the prefix index is built across all exit statuses.")

        if args.input_band in INPUT_BAND_RANGES:
            lower, upper = INPUT_BAND_RANGES[args.input_band]
            args.min_input = lower
            args.max_input = upper - 1

        if not args.prefix_index_path:
            default_index_path, index_error = default_prefix_index_path()
            if index_error:
                errors.append(
                    f"--input requires HF_HUB_CACHE to locate the default prefix index. "
                    f"{index_error}. Pass --prefix-index-path or set HF_HUB_CACHE."
                )
            else:
                args.prefix_index_path = str(default_index_path)
        if args.prefix_index_path:
            index_root = Path(args.prefix_index_path)
            if not index_root.exists():
                errors.append(
                    f"Prefix index not found at {index_root}. "
                    f"Build it first with `{prefix_index_build_command()}` or pass --prefix-index-path. {INPUT_BAND_HELP}."
                )
            elif args.input_band in INPUT_BAND_RANGES:
                band_dir = index_root / f"band={args.input_band}"
                metadata_path = index_root / "metadata.json"
                if not metadata_path.is_file():
                    errors.append(f"Prefix index metadata not found at {metadata_path}.")
                else:
                    try:
                        metadata = json.loads(metadata_path.read_text())
                        band_info = (metadata.get("bands") or {}).get(args.input_band) or {}
                        candidate_count = int(band_info.get("count", 0))
                        requested_samples = args.preview_samples if args.preview_samples > 0 else args.num_prompts
                        if candidate_count < 1:
                            errors.append(f"Prefix index band {args.input_band} is empty. {INPUT_BAND_HELP}.")
                        elif requested_samples > candidate_count and not args.sample_with_replacement:
                            errors.append(
                                f"Requested {requested_samples} samples from --input {args.input_band}, "
                                f"but only {candidate_count} indexed candidates are available. "
                                f"Use --num-prompts <= {candidate_count} or pass --sample-with-replacement to allow repeats. "
                                f"{INPUT_BAND_HELP}."
                            )
                    except Exception as exc:
                        errors.append(f"Could not read prefix index metadata at {metadata_path}: {exc}")
                if not band_dir.is_dir() or not list(band_dir.glob("*.parquet")):
                    errors.append(f"Prefix index band not found at {band_dir}. {INPUT_BAND_HELP}.")
    elif args.sample_with_replacement:
        errors.append("--sample-with-replacement requires --input.")

    if errors:
        print("ERROR: Invalid arguments:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)

    if not args.model:
        args.model = "preview-only"

    return args


args = parse_args()

BASE_URL_WAS_EXPLICIT = any(arg == "--base-url" or arg.startswith("--base-url=") for arg in sys.argv[1:])
BASE_URL = args.base_url if BASE_URL_WAS_EXPLICIT else f"http://localhost:{args.port}/v1"
API_KEY = args.api_key
MODEL = args.model
RUN_LABEL = args.run_label or MODEL
DATASET_PATH = Path(args.dataset_path)
NUM_PROMPTS = args.num_prompts
CONCURRENCY = args.concurrency
PORT = args.port
TIMEOUT_PER_REQUEST = args.timeout
WARMUP_REQUESTS = args.warmup
MIN_INPUT_TOKENS = args.min_input
MAX_INPUT_TOKENS = args.max_input
TEMPERATURE = args.temperature
INPUT_BAND = args.input_band
PREFIX_INDEX_PATH = Path(args.prefix_index_path) if args.prefix_index_path else None
SAMPLE_WITH_REPLACEMENT = args.sample_with_replacement
MIN_OUTPUT_TOKENS = args.min_output
MAX_OUTPUT_TOKENS = args.max_output
OUTPUT_CAP = None if args.sample_output_cap else args.output_cap
IGNORE_EOS = args.ignore_eos
PREVIEW_SAMPLES = args.preview_samples
RANDOM_SEED = args.seed
EXIT_STATUS_FILTER = args.exit_status
TRAJECTORY_MODE = args.trajectory_mode
MAX_SAMPLE_ATTEMPTS = args.max_sample_attempts

client = None
if PREVIEW_SAMPLES == 0:
    try:
        from openai import AsyncOpenAI
    except ModuleNotFoundError:
        print("ERROR: `openai` package is not installed. Install it or run with --preview-samples.")
        sys.exit(1)

    client = AsyncOpenAI(
        base_url=BASE_URL,
        api_key=API_KEY,
        timeout=TIMEOUT_PER_REQUEST,
        max_retries=0,
    )


def seed_random():
    if RANDOM_SEED is None:
        random.seed()
    else:
        random.seed(RANDOM_SEED)


def run_header(prefix: str, label: str | None = None) -> str:
    return f"{prefix}: {label or RUN_LABEL} | Prompts: {NUM_PROMPTS} | Concurrency: {CONCURRENCY}"


def format_optional_tps(value: float | None) -> str:
    if value is None or value <= 0:
        return "N/A"
    return f"{value:.2f}"


def import_pyarrow_parquet():
    try:
        import pyarrow.parquet as pq
    except ModuleNotFoundError:
        print("ERROR: `pyarrow` is required to read SWE-ZERO Parquet shards.")
        print("Install it in this environment, for example:")
        print("  uv pip install --python /home/user/env_custom_uv/bin/python pyarrow")
        sys.exit(1)
    return pq


def load_indexed_source_rows(shard_path: str, row_ids: list[int]) -> tuple[str, dict[int, dict]]:
    import pyarrow as pa
    import pyarrow.parquet as pq

    table = pq.read_table(
        shard_path,
        columns=["instance_id", "repo", "messages", "exit_status", "duration_sec"],
    )
    selected = table.take(pa.array(row_ids, type=pa.int64()))
    return shard_path, dict(zip(row_ids, selected.to_pylist()))


def estimate_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def bucket_for_tokens(tokens: int) -> str:
    for bucket in INPUT_TOKEN_BUCKETS:
        if bucket.min_tokens <= tokens <= bucket.max_tokens:
            return bucket.name
    if tokens < INPUT_TOKEN_BUCKETS[0].min_tokens:
        return "below_range"
    return "above_range"


def pick_weighted_bucket(min_tokens: int, max_tokens: int, buckets: list[TokenBucket]) -> TokenBucket:
    candidates = []
    for bucket in buckets:
        lower = max(min_tokens, bucket.min_tokens)
        upper = min(max_tokens, bucket.max_tokens)
        if lower > upper:
            continue
        overlap = upper - lower + 1
        full_width = bucket.max_tokens - bucket.min_tokens + 1
        candidates.append((bucket, bucket.weight * (overlap / full_width)))

    if not candidates:
        raise ValueError("No token buckets overlap requested min/max input range")

    return random.choices([item[0] for item in candidates], weights=[item[1] for item in candidates], k=1)[0]


def pick_weighted_token_count(min_tokens: int, max_tokens: int, buckets: list[TokenBucket]) -> tuple[int, str]:
    candidates = []
    for bucket in buckets:
        lower = max(min_tokens, bucket.min_tokens)
        upper = min(max_tokens, bucket.max_tokens)
        if lower > upper:
            continue
        overlap = upper - lower + 1
        full_width = bucket.max_tokens - bucket.min_tokens + 1
        adjusted_weight = bucket.weight * (overlap / full_width)
        candidates.append((bucket, lower, upper, adjusted_weight))

    if not candidates:
        return random.randint(min_tokens, max_tokens), "uniform_clamped"

    chosen_bucket, lower, upper, _ = random.choices(candidates, weights=[c[3] for c in candidates], k=1)[0]
    return random.randint(lower, upper), chosen_bucket.name


def sample_output_tokens() -> tuple[int, str]:
    return pick_weighted_token_count(MIN_OUTPUT_TOKENS, MAX_OUTPUT_TOKENS, OUTPUT_TOKEN_BUCKETS)


def choose_output_cap() -> tuple[int, str]:
    if OUTPUT_CAP is not None:
        return OUTPUT_CAP, "fixed_cap"
    return sample_output_tokens()


class SweZeroSampler:
    def __init__(self, dataset_path: Path, exit_status_filter: str, trajectory_mode: str):
        self.dataset_path = dataset_path
        self.data_dir = dataset_path / "data"
        self.exit_status_filter = exit_status_filter
        self.trajectory_mode = trajectory_mode
        self.pq = import_pyarrow_parquet()
        self.shards = sorted(self.data_dir.glob("*.parquet"))
        if not self.shards:
            print(f"ERROR: No Parquet shards found under {self.data_dir}")
            print("Expected files like data/train-00000.parquet")
            sys.exit(1)

        self._shard_order = list(range(len(self.shards)))
        random.shuffle(self._shard_order)
        self._next_shard = 0
        self._rows = []
        self._current_shard_name = ""

    def _load_next_shard(self):
        while True:
            if self._next_shard >= len(self._shard_order):
                random.shuffle(self._shard_order)
                self._next_shard = 0

            shard = self.shards[self._shard_order[self._next_shard]]
            self._next_shard += 1

            table = self.pq.read_table(
                shard,
                columns=["instance_id", "repo", "messages", "exit_status", "duration_sec"],
            )
            rows = table.to_pylist()
            if self.exit_status_filter != "any":
                rows = [row for row in rows if row.get("exit_status") == self.exit_status_filter]
            if not rows:
                continue

            random.shuffle(rows)
            self._rows = rows
            self._current_shard_name = shard.name
            return

    def next_row(self) -> tuple[dict, str]:
        if not self._rows:
            self._load_next_shard()
        return self._rows.pop(), self._current_shard_name

    def select_messages(self, messages: list[dict]) -> list[dict]:
        if self.trajectory_mode == "full":
            return messages

        user_indices = [
            idx
            for idx, message in enumerate(messages)
            if message.get("role") == "user"
            and idx >= 3
            and any(prev.get("role") == "assistant" for prev in messages[:idx])
        ]
        if not user_indices:
            user_indices = [
                idx
                for idx, message in enumerate(messages)
                if message.get("role") == "user" and idx >= 1
            ]
        if not user_indices:
            return messages

        message_count = max(1, len(messages))
        weights = [((idx + 1) / message_count) ** 2 for idx in user_indices]
        end_idx = random.choices(user_indices, weights=weights, k=1)[0]
        return messages[: end_idx + 1]

    def normalize_chat_messages(self, messages: list[dict]) -> list[dict]:
        chat_messages = []
        valid_roles = {"system", "user", "assistant"}
        for message in messages:
            role = message.get("role") or "user"
            if role not in valid_roles:
                role = "user"
            content = message.get("content") or ""
            if content:
                chat_messages.append({"role": role, "content": content})

        if not chat_messages:
            return [{"role": "user", "content": "Continue the software-engineering task."}]
        return chat_messages

    def is_continuable(self, messages: list[dict]) -> bool:
        return bool(messages) and messages[-1].get("role") == "user"

    def render_transcript(self, messages: list[dict]) -> str:
        blocks = []
        for message in messages:
            role = message.get("role") or "unknown"
            content = message.get("content") or ""
            blocks.append(f"<{role}>\n{content}\n</{role}>")
        return "\n\n".join(blocks)

    def build_prompt(self, row: dict, shard_name: str, output_bucket: str) -> tuple[str, list[dict]]:
        del shard_name, output_bucket
        messages = self.select_messages(row.get("messages") or [])
        chat_messages = self.normalize_chat_messages(messages)
        return self.render_transcript(chat_messages), chat_messages

    def make_sample(
        self,
        request_id: int,
        row: dict,
        shard_name: str,
        prompt: str,
        messages: list[dict],
        approx_tokens: int,
        input_bucket: str,
        output_len: int,
        output_bucket: str,
    ) -> RequestSample:
        return RequestSample(
            request_id=request_id,
            prompt=prompt,
            messages=messages,
            input_len=approx_tokens,
            input_bucket=input_bucket,
            output_len=output_len,
            output_bucket=output_bucket,
            instance_id=row.get("instance_id") or "",
            repo=row.get("repo") or "",
            exit_status=row.get("exit_status") or "",
            shard_name=shard_name,
        )

    def sample_request(self, request_id: int, output_len: int, output_bucket: str) -> RequestSample:
        target_bucket = pick_weighted_bucket(MIN_INPUT_TOKENS, MAX_INPUT_TOKENS, INPUT_TOKEN_BUCKETS)
        fallback_in_range = None
        fallback_bucket_match = None
        fallback_continuable = None

        for _ in range(MAX_SAMPLE_ATTEMPTS):
            row, shard_name = self.next_row()
            prompt, messages = self.build_prompt(row, shard_name, output_bucket)
            approx_tokens = estimate_tokens(prompt)
            in_requested_range = MIN_INPUT_TOKENS <= approx_tokens <= MAX_INPUT_TOKENS
            bucket_matches = (
                max(MIN_INPUT_TOKENS, target_bucket.min_tokens)
                <= approx_tokens
                <= min(MAX_INPUT_TOKENS, target_bucket.max_tokens)
            )
            continuable = self.is_continuable(messages)
            candidate = (row, shard_name, prompt, messages, approx_tokens)

            if in_requested_range and fallback_in_range is None:
                fallback_in_range = candidate
            if in_requested_range and continuable and fallback_continuable is None:
                fallback_continuable = candidate
            if bucket_matches and fallback_bucket_match is None:
                fallback_bucket_match = candidate

            if bucket_matches and continuable:
                return self.make_sample(
                    request_id,
                    row,
                    shard_name,
                    prompt,
                    messages,
                    approx_tokens,
                    target_bucket.name,
                    output_len,
                    output_bucket,
                )

        if fallback_continuable is not None:
            row, shard_name, prompt, messages, approx_tokens = fallback_continuable
            return self.make_sample(
                request_id,
                row,
                shard_name,
                prompt,
                messages,
                approx_tokens,
                bucket_for_tokens(approx_tokens),
                output_len,
                output_bucket,
            )

        if fallback_bucket_match is not None:
            row, shard_name, prompt, messages, approx_tokens = fallback_bucket_match
            return self.make_sample(
                request_id,
                row,
                shard_name,
                prompt,
                messages,
                approx_tokens,
                target_bucket.name,
                output_len,
                output_bucket,
            )

        if fallback_in_range is None:
            raise RuntimeError(
                f"Could not find a SWE-ZERO prompt in input range {MIN_INPUT_TOKENS}-{MAX_INPUT_TOKENS} "
                f"after {MAX_SAMPLE_ATTEMPTS} candidate rows. Try widening --min-input/--max-input."
            )

        row, shard_name, prompt, messages, approx_tokens = fallback_in_range
        return self.make_sample(
            request_id,
            row,
            shard_name,
            prompt,
            messages,
            approx_tokens,
            bucket_for_tokens(approx_tokens),
            output_len,
            output_bucket,
        )


class SweZeroIndexedSampler:
    def __init__(
        self,
        dataset_path: Path,
        index_path: Path,
        input_band: str,
        sample_count: int,
        sample_with_replacement: bool,
    ):
        self.dataset_path = dataset_path
        self.data_dir = dataset_path / "data"
        self.index_path = index_path
        self.input_band = input_band
        self.sample_with_replacement = sample_with_replacement
        self.pq = import_pyarrow_parquet()
        self.shards = sorted(self.data_dir.glob("*.parquet"))
        if not self.shards:
            print(f"ERROR: No Parquet shards found under {self.data_dir}")
            print("Expected files like data/train-00000.parquet")
            sys.exit(1)

        self.metadata = self.load_metadata()
        self.pool_size = self.band_pool_size()
        if sample_count > self.pool_size and not sample_with_replacement:
            raise RuntimeError(
                f"Requested --num-prompts {sample_count} from --input {input_band}, "
                f"but only {self.pool_size} indexed candidates are available. "
                f"Use --num-prompts <= {self.pool_size} or pass --sample-with-replacement to allow repeats. "
                f"{INPUT_BAND_HELP}."
            )
        if sample_count > self.pool_size and sample_with_replacement:
            print(
                f"WARNING: Sampling with replacement: requested {sample_count} prompts from "
                f"{self.pool_size} indexed {input_band} candidates. Some prompts will repeat."
            )

        self.candidates = self.load_selected_candidates(sample_count)
        self._next_candidate = 0
        self._rows_needed_by_shard: dict[int, set[int]] = {}
        for candidate in self.candidates:
            self._rows_needed_by_shard.setdefault(candidate.shard_id, set()).add(candidate.row_in_shard)
        self._shard_cache: dict[int, dict[int, dict]] = {}

    def load_metadata(self) -> dict:
        metadata_path = self.index_path / "metadata.json"
        try:
            return json.loads(metadata_path.read_text())
        except Exception as exc:
            raise RuntimeError(f"Could not read prefix index metadata at {metadata_path}: {exc}") from exc

    def band_pool_size(self) -> int:
        bands = self.metadata.get("bands") or {}
        band_info = bands.get(self.input_band)
        if not band_info:
            raise RuntimeError(f"Prefix index does not contain --input {self.input_band}. {INPUT_BAND_HELP}.")
        count = int(band_info.get("count", 0))
        if count < 1:
            raise RuntimeError(f"Prefix index band {self.input_band} is empty. {INPUT_BAND_HELP}.")
        return count

    def validate_shard_map(self):
        indexed_shards = self.metadata.get("shards") or []
        if len(indexed_shards) != len(self.shards):
            raise RuntimeError(
                f"Prefix index shard count ({len(indexed_shards)}) does not match dataset shard count ({len(self.shards)}). "
                "Rebuild the prefix index for this dataset."
            )
        for idx, shard in enumerate(self.shards):
            expected = indexed_shards[idx]
            if expected != shard.name:
                raise RuntimeError(
                    f"Prefix index shard mismatch at id {idx}: index has {expected}, dataset has {shard.name}. "
                    "Rebuild the prefix index for this dataset."
                )

    def load_band_table(self):
        import pyarrow as pa

        band_dir = self.index_path / f"band={self.input_band}"
        files = sorted(band_dir.glob("*.parquet"))
        if not files:
            raise RuntimeError(f"Prefix index band not found at {band_dir}. {INPUT_BAND_HELP}.")

        columns = ["approx_tokens", "shard_id", "row_in_shard", "prefix_end_index"]
        tables = [self.pq.read_table(path, columns=columns) for path in files]
        if len(tables) == 1:
            return tables[0]
        return pa.concat_tables(tables)

    def select_positions(self, sample_count: int) -> list[int]:
        positions = []
        if self.sample_with_replacement:
            for _ in range(sample_count):
                positions.append(random.randrange(self.pool_size))
            return positions

        seen = set()
        while len(positions) < sample_count:
            position = random.randrange(self.pool_size)
            if position in seen:
                continue
            seen.add(position)
            positions.append(position)
        return positions

    def load_selected_candidates(self, sample_count: int) -> list[IndexedCandidate]:
        import pyarrow as pa

        self.validate_shard_map()
        positions = self.select_positions(sample_count)
        table = self.load_band_table()
        if table.num_rows != self.pool_size:
            raise RuntimeError(
                f"Prefix index metadata says {self.pool_size} rows for {self.input_band}, "
                f"but the Parquet index contains {table.num_rows}. Rebuild the prefix index."
            )

        selected = table.take(pa.array(positions, type=pa.int64()))
        approx_tokens = selected.column("approx_tokens").to_pylist()
        shard_ids = selected.column("shard_id").to_pylist()
        row_ids = selected.column("row_in_shard").to_pylist()
        prefix_end_indices = selected.column("prefix_end_index").to_pylist()
        return [
            IndexedCandidate(
                approx_tokens=int(approx_tokens[idx]),
                shard_id=int(shard_ids[idx]),
                row_in_shard=int(row_ids[idx]),
                prefix_end_index=int(prefix_end_indices[idx]),
            )
            for idx in range(sample_count)
        ]

    def preload_source_rows(self, *, show_progress: bool):
        tasks = [
            (shard_id, str(self.shards[shard_id]), sorted(row_ids))
            for shard_id, row_ids in self._rows_needed_by_shard.items()
        ]
        if not tasks:
            return

        worker_count = min(16, len(tasks))
        if show_progress:
            print(f"Loading indexed source rows from {len(tasks)} shards with {worker_count} workers...")

        path_to_shard_id = {str(self.shards[shard_id]): shard_id for shard_id, _, _ in tasks}
        with ThreadPoolExecutor(max_workers=worker_count) as pool:
            futures = [
                pool.submit(load_indexed_source_rows, shard_path, row_ids)
                for _, shard_path, row_ids in tasks
            ]
            for completed, future in enumerate(as_completed(futures), start=1):
                shard_path, rows = future.result()
                self._shard_cache[path_to_shard_id[shard_path]] = rows
                if show_progress and len(futures) >= 20 and (completed % max(1, len(futures) // 20) == 0):
                    print(f"\rLoaded source shards: {completed}/{len(futures)}", end="", flush=True)

        if show_progress and len(tasks) >= 20:
            print()

    def load_source_row(self, candidate: IndexedCandidate) -> tuple[dict, str]:
        import pyarrow as pa

        if candidate.shard_id < 0 or candidate.shard_id >= len(self.shards):
            raise RuntimeError(f"Indexed candidate has invalid shard_id {candidate.shard_id}. Rebuild the prefix index.")
        if candidate.shard_id not in self._shard_cache:
            row_ids = sorted(self._rows_needed_by_shard.get(candidate.shard_id, {candidate.row_in_shard}))
            table = self.pq.read_table(
                self.shards[candidate.shard_id],
                columns=["instance_id", "repo", "messages", "exit_status", "duration_sec"],
            )
            selected = table.take(pa.array(row_ids, type=pa.int64()))
            self._shard_cache[candidate.shard_id] = dict(zip(row_ids, selected.to_pylist()))

        rows = self._shard_cache[candidate.shard_id]
        if candidate.row_in_shard not in rows:
            raise RuntimeError(
                f"Indexed candidate row {candidate.row_in_shard} is outside shard {self.shards[candidate.shard_id].name}. "
                "Rebuild the prefix index."
            )
        return rows[candidate.row_in_shard], self.shards[candidate.shard_id].name

    def normalize_chat_messages(self, messages: list[dict]) -> list[dict]:
        chat_messages = []
        valid_roles = {"system", "user", "assistant"}
        for message in messages:
            role = message.get("role") or "user"
            if role not in valid_roles:
                role = "user"
            content = message.get("content") or ""
            if content:
                chat_messages.append({"role": role, "content": content})

        if not chat_messages:
            return [{"role": "user", "content": "Continue the software-engineering task."}]
        return chat_messages

    def render_transcript(self, messages: list[dict]) -> str:
        blocks = []
        for message in messages:
            role = message.get("role") or "unknown"
            content = message.get("content") or ""
            blocks.append(f"<{role}>\n{content}\n</{role}>")
        return "\n\n".join(blocks)

    def build_prompt(self, row: dict, candidate: IndexedCandidate) -> tuple[str, list[dict]]:
        messages = row.get("messages") or []
        if candidate.prefix_end_index == FULL_PREFIX_SENTINEL:
            selected_messages = messages
        else:
            selected_messages = messages[: candidate.prefix_end_index + 1]
        chat_messages = self.normalize_chat_messages(selected_messages)
        return self.render_transcript(chat_messages), chat_messages

    def sample_request(self, request_id: int, output_len: int, output_bucket: str) -> RequestSample:
        if self._next_candidate >= len(self.candidates):
            raise RuntimeError("Indexed sampler exhausted its selected candidates.")

        candidate = self.candidates[self._next_candidate]
        self._next_candidate += 1
        row, shard_name = self.load_source_row(candidate)
        prompt, messages = self.build_prompt(row, candidate)
        approx_tokens = estimate_tokens(prompt)

        lower, upper = INPUT_BAND_RANGES[self.input_band]
        if not (lower <= approx_tokens < upper):
            raise RuntimeError(
                f"Indexed candidate for {self.input_band} rendered to {approx_tokens} approximate tokens, "
                f"outside expected range {lower}-{upper - 1}. Rebuild the prefix index."
            )

        return RequestSample(
            request_id=request_id,
            prompt=prompt,
            messages=messages,
            input_len=approx_tokens,
            input_bucket=self.input_band,
            output_len=output_len,
            output_bucket=output_bucket,
            instance_id=row.get("instance_id") or "",
            repo=row.get("repo") or "",
            exit_status=row.get("exit_status") or "",
            shard_name=shard_name,
        )


def print_bucket_profile(buckets: list[TokenBucket], descriptions: dict[str, str]):
    for bucket in buckets:
        print(
            f"  {bucket.name:<18} "
            f"{bucket.min_tokens:>5}-{bucket.max_tokens:<5} "
            f"w={bucket.weight:.2f}  {descriptions.get(bucket.name, '')}"
        )


def build_request_samples(sample_count: int, *, show_progress: bool) -> list[RequestSample]:
    if INPUT_BAND:
        sampler = SweZeroIndexedSampler(
            DATASET_PATH,
            PREFIX_INDEX_PATH,
            INPUT_BAND,
            sample_count,
            SAMPLE_WITH_REPLACEMENT,
        )
    else:
        sampler = SweZeroSampler(DATASET_PATH, EXIT_STATUS_FILTER, TRAJECTORY_MODE)
    samples = []

    if show_progress:
        if INPUT_BAND:
            print(
                f"Sampling {sample_count} prompts from prefix index {PREFIX_INDEX_PATH} "
                f"({INPUT_BAND}, {sampler.pool_size} candidates)..."
            )
        else:
            print(f"Sampling {sample_count} prompts from {DATASET_PATH} ({len(sampler.shards)} parquet shards)...")

    if INPUT_BAND:
        sampler.preload_source_rows(show_progress=show_progress)

    for idx in range(sample_count):
        output_len, output_bucket = choose_output_cap()
        sample = sampler.sample_request(idx, output_len, output_bucket)
        samples.append(sample)

        if show_progress and sample_count >= 20 and (idx + 1) % max(1, sample_count // 20) == 0:
            print(f"\rSampled prompts: {idx + 1}/{sample_count}", end="", flush=True)

    if show_progress and sample_count >= 20:
        print()

    return samples


def print_sample_preview():
    print("\n" + "=" * 80)
    print(f"SWE-ZERO SAMPLE PREVIEW ({PREVIEW_SAMPLES} samples)")
    print("=" * 80)
    print(f"Dataset path:     {DATASET_PATH}")
    print(f"Trajectory mode:  {TRAJECTORY_MODE}")
    print(f"Exit status:      {EXIT_STATUS_FILTER}")
    print(f"Seed:             {RANDOM_SEED if RANDOM_SEED is not None else '(random)'}")
    if INPUT_BAND:
        lower, upper = INPUT_BAND_RANGES[INPUT_BAND]
        print(f"Indexed input:    {INPUT_BAND} (>={lower} <{upper})")
        print(f"Prefix index:     {PREFIX_INDEX_PATH}")
    print(f"Input clamp:      {MIN_INPUT_TOKENS} - {MAX_INPUT_TOKENS}")
    if OUTPUT_CAP is not None:
        print(f"Output cap:       {OUTPUT_CAP}")
    else:
        print(f"Output cap sampling: enabled ({MIN_OUTPUT_TOKENS} - {MAX_OUTPUT_TOKENS})")
    print("\nInput bucket profile:")
    print_bucket_profile(INPUT_TOKEN_BUCKETS, INPUT_BUCKET_DESCRIPTIONS)
    if OUTPUT_CAP is None:
        print("\nOutput bucket profile:")
        print_bucket_profile(OUTPUT_TOKEN_BUCKETS, OUTPUT_BUCKET_DESCRIPTIONS)

    samples = build_request_samples(PREVIEW_SAMPLES, show_progress=False)

    for idx, sample in enumerate(samples):
        preview_chars = min(len(sample.prompt), 3200)

        print("\n" + "-" * 80)
        print(f"Sample {idx + 1}/{PREVIEW_SAMPLES}")
        print(f"Input tokens approximate: {sample.input_len} ({sample.input_bucket})")
        print(f"Output tokens target:     {sample.output_len} ({sample.output_bucket})")
        print(f"Repo:                     {sample.repo}")
        print(f"Instance:                 {sample.instance_id}")
        print(f"Exit status:              {sample.exit_status}")
        print(f"Shard:                    {sample.shard_name}")
        print(f"Chat messages:            {len(sample.messages)}")
        print("-" * 80)
        print(sample.prompt[:preview_chars])
        if len(sample.prompt) > preview_chars:
            print("\n...[truncated for preview]...")


def _value_has_text(value) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value)
    if isinstance(value, list):
        for part in value:
            if isinstance(part, str) and part:
                return True
            if isinstance(part, dict):
                if part.get("text") or part.get("content") or part.get("reasoning") or part.get("reasoning_content"):
                    return True
            else:
                for attr in ("text", "content", "reasoning", "reasoning_content"):
                    text = getattr(part, attr, None)
                    if isinstance(text, str) and text:
                        return True
        return False
    return False


def _delta_has_text(delta, attrs: tuple[str, ...]) -> bool:
    for attr in attrs:
        value = getattr(delta, attr, None)
        if _value_has_text(value):
            return True
    return False


async def run_single_request_streaming(sample: RequestSample, progress: dict) -> RequestResult:
    start = time.perf_counter()
    content_ttft = 0
    reasoning_ttft = 0
    completion_tokens = 0
    prompt_tokens = 0
    finish_reason = ""

    try:
        request_params = {
            "model": MODEL,
            "messages": sample.messages,
            "max_tokens": sample.output_len,
            "temperature": TEMPERATURE,
            "stream": True,
            "stream_options": {"include_usage": True},
        }

        if IGNORE_EOS:
            request_params["extra_body"] = {"ignore_eos": True}

        stream = await client.chat.completions.create(**request_params)

        async for chunk in stream:
            if chunk.choices:
                delta = chunk.choices[0].delta
                observed_at = None
                if content_ttft == 0 and _delta_has_text(delta, ("content",)):
                    observed_at = time.perf_counter()
                    content_ttft = observed_at - start
                if reasoning_ttft == 0 and _delta_has_text(delta, ("reasoning", "reasoning_content")):
                    if observed_at is None:
                        observed_at = time.perf_counter()
                    reasoning_ttft = observed_at - start
                chunk_finish_reason = chunk.choices[0].finish_reason
                if chunk_finish_reason:
                    finish_reason = chunk_finish_reason
            if chunk.usage:
                prompt_tokens = chunk.usage.prompt_tokens
                completion_tokens = chunk.usage.completion_tokens

        end = time.perf_counter()
        is_abort = finish_reason in {"abort", "error"}

        result = RequestResult(
            request_id=sample.request_id,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_time=end - start,
            content_ttft=content_ttft,
            reasoning_ttft=reasoning_ttft,
            input_len=sample.input_len,
            output_len=sample.output_len,
            input_bucket=sample.input_bucket,
            output_bucket=sample.output_bucket,
            finish_reason=finish_reason,
            success=not is_abort,
            error=f"finish_reason:{finish_reason}" if is_abort else None,
        )
    except asyncio.TimeoutError:
        result = RequestResult(
            request_id=sample.request_id,
            success=False,
            error="timeout",
            input_len=sample.input_len,
            output_len=sample.output_len,
            input_bucket=sample.input_bucket,
            output_bucket=sample.output_bucket,
            finish_reason=finish_reason,
        )
    except Exception as exc:
        result = RequestResult(
            request_id=sample.request_id,
            success=False,
            error=str(exc)[:120],
            input_len=sample.input_len,
            output_len=sample.output_len,
            input_bucket=sample.input_bucket,
            output_bucket=sample.output_bucket,
            finish_reason=finish_reason,
        )

    progress["completed"] += 1
    if not result.success:
        progress["failed"] += 1

    elapsed = time.perf_counter() - progress["start_time"]
    rate = progress["completed"] / elapsed if elapsed > 0 else 0
    print(
        f"\rProgress: {progress['completed']}/{NUM_PROMPTS} | Failed: {progress['failed']} | Rate: {rate:.2f} req/s",
        end="",
        flush=True,
    )
    return result


async def warmup():
    print(f"Warming up with {WARMUP_REQUESTS} requests...")
    for i in range(WARMUP_REQUESTS):
        try:
            request_params = {
                "model": MODEL,
                "messages": [{"role": "user", "content": f"Warmup request {uuid.uuid4()}. Print ok."}],
                "max_tokens": 50,
                "temperature": TEMPERATURE,
                "stream": True,
                "stream_options": {"include_usage": True},
            }
            if IGNORE_EOS:
                request_params["extra_body"] = {"ignore_eos": True}

            stream = await client.chat.completions.create(**request_params)
            async for _ in stream:
                pass
            print(f"\rWarmup: {i + 1}/{WARMUP_REQUESTS}", end="", flush=True)
        except Exception as exc:
            print(f"\rWarmup {i + 1} failed: {exc}", end="", flush=True)
    print(" Done!")


def summarize_bucket_counts(results: list[RequestResult], attr: str, expected_buckets: list[TokenBucket]) -> list[str]:
    counts = {}
    for item in results:
        key = getattr(item, attr)
        counts[key] = counts.get(key, 0) + 1
    lines = []
    for bucket in expected_buckets:
        count = counts.get(bucket.name, 0)
        pct = (count / len(results) * 100) if results else 0
        lines.append(f"  {bucket.name:<18} {count:>4} ({pct:>5.1f}%)")
    for key in sorted(set(counts) - {bucket.name for bucket in expected_buckets}):
        count = counts[key]
        pct = (count / len(results) * 100) if results else 0
        lines.append(f"  {key:<18} {count:>4} ({pct:>5.1f}%)")
    return lines


def summarize_finish_reasons(results: list[RequestResult]) -> list[str]:
    counts = {}
    for item in results:
        key = item.finish_reason or "(none)"
        counts[key] = counts.get(key, 0) + 1
    lines = []
    total = len(results)
    for reason, count in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        pct = (count / total * 100) if total else 0
        lines.append(f"  {reason:<18} {count:>4} ({pct:>5.1f}%)")
    return lines


async def run_benchmark():
    if client is None:
        print("ERROR: Client not initialized. Use --preview-samples for preview mode or provide --model for benchmark mode.")
        return

    samples = build_request_samples(NUM_PROMPTS, show_progress=True)

    print("\n" + "=" * 60)
    print()
    print("NOTE: For accurate benchmarks, start server with:")
    print("  SGLang: --disable-radix-cache")
    print("  vLLM:   --no-enable-prefix-caching")
    print()
    print("=" * 60 + "\n")

    await warmup()
    sglang_model_metadata = fetch_sglang_model_metadata(BASE_URL, API_KEY)
    display_model = sglang_display_model_name(sglang_model_metadata, MODEL)
    display_run_label = RUN_LABEL if args.run_label else display_model
    sglang_batch_collector = SGLangBatchMetricsCollector(BASE_URL)
    sglang_batch_collector.start()
    if not sglang_batch_collector.has_log_source:
        if not prompt_continue_without_sglang_logs(sglang_batch_collector.process):
            sglang_batch_collector.stop()
            return
    sglang_metrics_start = fetch_sglang_metrics_snapshot(BASE_URL, API_KEY)

    progress = {"completed": 0, "failed": 0, "start_time": time.perf_counter()}
    sglang_log_sources = ", ".join(sglang_batch_collector.process.source_paths) or "N/A"
    sampling_policy = (
        "indexed user-ending prefixes"
        if INPUT_BAND
        else "random user-ending prefixes"
        if TRAJECTORY_MODE == "prefix"
        else "full trajectories"
    )

    print(f"\n{'=' * 60}")
    print(run_header("SWE-ZERO BENCHMARK", display_run_label))
    print(f"{'=' * 60}")
    print()
    print(f"SGLang Version:      {sglang_model_metadata.sglang_version}")
    print(f"Model:               {display_model}")
    print(f"Dataset path:        {DATASET_PATH}")
    print(f"Trajectory mode:     {TRAJECTORY_MODE}")
    print(f"Exit status:         {EXIT_STATUS_FILTER}")
    print(f"Seed:                {RANDOM_SEED if RANDOM_SEED is not None else '(random)'}")
    if INPUT_BAND:
        lower, upper = INPUT_BAND_RANGES[INPUT_BAND]
        print(f"Indexed input:       {INPUT_BAND} (>={lower} <{upper})")
        print(f"Prefix index:        {PREFIX_INDEX_PATH}")
        print(f"Sample replacement:  {SAMPLE_WITH_REPLACEMENT}")
    print(f"Port:                {PORT}")
    print(f"Base URL:            {BASE_URL}")
    print(f"SGLang log source:   {sglang_log_sources}")
    print("Streaming:           True")
    print("Prompt format:       SWE-ZERO chat roles")
    print(f"Sampling policy:     {sampling_policy}")
    print("Radix cache:         disabled (expected)")
    print(f"Total requests:      {NUM_PROMPTS}")
    print(f"Concurrency:         {CONCURRENCY} (simulating {CONCURRENCY} agents)")
    print(f"Input tokens clamp:  {MIN_INPUT_TOKENS} - {MAX_INPUT_TOKENS} (approx chars/4)")
    if OUTPUT_CAP is not None:
        print(f"Output cap:          {OUTPUT_CAP}")
    else:
        print(f"Output cap sampling: enabled ({MIN_OUTPUT_TOKENS} - {MAX_OUTPUT_TOKENS})")
    print(f"Temperature:         {TEMPERATURE}")
    print("Input profile (pre-clamp):")
    print_bucket_profile(INPUT_TOKEN_BUCKETS, INPUT_BUCKET_DESCRIPTIONS)
    if OUTPUT_CAP is None:
        print("Output profile (pre-clamp):")
        print_bucket_profile(OUTPUT_TOKEN_BUCKETS, OUTPUT_BUCKET_DESCRIPTIONS)
    print(f"Timeout per request: {TIMEOUT_PER_REQUEST}s")
    print(f"ignore_eos:          {IGNORE_EOS} {'(forces full output)' if IGNORE_EOS else '(natural stopping)'}")
    print()
    print(f"{'=' * 60}\n")

    semaphore = asyncio.Semaphore(CONCURRENCY)

    async def bounded_request(sample: RequestSample):
        async with semaphore:
            return await run_single_request_streaming(sample, progress)

    try:
        overall_start = time.perf_counter()
        results = await asyncio.gather(*[bounded_request(sample) for sample in samples])
        overall_end = time.perf_counter()
        await asyncio.sleep(0.5)
        sglang_metrics_end = fetch_sglang_metrics_snapshot(BASE_URL, API_KEY)
    finally:
        sglang_batch_report = sglang_batch_collector.stop()

    print(f"\n\n{'=' * 60}")

    successful = [r for r in results if r.success]
    failed = [r for r in results if not r.success]

    if not successful:
        print("\nAll requests failed!")
        for result in failed[:10]:
            print(f"  Request {result.request_id}: {result.error}")
        print_sglang_batch_throughput_report(sglang_batch_report)
        return

    total_prompt_tokens = sum(r.prompt_tokens for r in successful)
    total_completion_tokens = sum(r.completion_tokens for r in successful)
    total_tokens = total_prompt_tokens + total_completion_tokens
    total_wall_time = overall_end - overall_start

    latencies = [r.total_time for r in successful]
    content_ttfts = [r.content_ttft for r in successful if r.content_ttft > 0]
    reasoning_ttfts = [r.reasoning_ttft for r in successful if r.reasoning_ttft > 0]
    tps_per_request = [r.completion_tokens / r.total_time for r in successful if r.total_time > 0]

    def percentile(data, p):
        if not data:
            return 0
        sorted_data = sorted(data)
        idx = int(p * len(sorted_data))
        idx = min(idx, len(sorted_data) - 1)
        return sorted_data[idx]

    avg_input = statistics.mean([r.input_len for r in successful])
    avg_output = statistics.mean([r.output_len for r in successful])
    actual_avg_input = statistics.mean([r.prompt_tokens for r in successful])
    actual_avg_output = statistics.mean([r.completion_tokens for r in successful])
    sglang_stage_throughput = calculate_sglang_stage_throughput(
        MODEL,
        sglang_model_metadata,
        sglang_metrics_start,
        sglang_metrics_end,
    )

    print(run_header("RESULTS", display_run_label))
    print(f"{'=' * 60}")
    print()
    print(f"Successful requests:       {len(successful)}/{NUM_PROMPTS}")
    print(f"Failed requests:           {len(failed)}")
    print(f"Requests Seed:             {RANDOM_SEED if RANDOM_SEED is not None else '(random)'}")
    print(f"Avg input tokens (approx): {avg_input:.0f}")
    print(f"Avg input tokens (actual): {actual_avg_input:.0f}")
    print(f"Avg output tokens (cfg):   {avg_output:.0f}")
    print(f"Avg output tokens (actual): {actual_avg_output:.0f}")
    print(f"Total prompt tokens:       {total_prompt_tokens:,}")
    print(f"Total completion tokens:   {total_completion_tokens:,}")
    print(f"Total wall time:           {total_wall_time:.2f}s")

    print(f"\n{'=' * 60}")
    print()
    print("REQUEST MIX (successful):")
    print("Input buckets:")
    for line in summarize_bucket_counts(successful, "input_bucket", INPUT_TOKEN_BUCKETS):
        print(line)
    print("Output buckets:")
    for line in summarize_bucket_counts(successful, "output_bucket", OUTPUT_TOKEN_BUCKETS):
        print(line)
    print("Finish reasons (all):")
    for line in summarize_finish_reasons(results):
        print(line)

    print(f"\n{'=' * 60}")
    print()
    print("THROUGHPUT:")
    print(f"  Requests/sec:          {len(successful) / total_wall_time:.2f}")
    print(f"  SGLang Prefill tokens/sec: {format_optional_tps(sglang_stage_throughput.prefill_tokens_per_sec)}")
    print(f"  SGLang Decode tokens/sec:  {format_optional_tps(sglang_stage_throughput.decode_tokens_per_sec)}")
    print(f"  End-to-end Output tokens/sec: {total_completion_tokens / total_wall_time:.2f}")
    print(f"  Total tokens/sec:             {total_tokens / total_wall_time:.2f}")

    def print_ttft_stats(label: str, ttft_values: list[float]):
        print(f"{label}:")
        if not ttft_values:
            print("  Mean:                  N/A")
            print("  Median:                N/A")
            print("  P95:                   N/A")
            print("  P99:                   N/A")
            return

        print(f"  Mean:                  {statistics.mean(ttft_values) * 1000:.0f}ms")
        print(f"  Median:                {statistics.median(ttft_values) * 1000:.0f}ms")
        print(f"  P95:                   {percentile(ttft_values, 0.95) * 1000:.0f}ms")
        print(f"  P99:                   {percentile(ttft_values, 0.99) * 1000:.0f}ms")

    print(f"\n{'=' * 60}")
    print()
    print("TIME TO FIRST TOKEN (client-observed):")
    print_ttft_stats("Content", content_ttfts)
    print_ttft_stats("Reasoning", reasoning_ttfts)

    print("\nEND-TO-END LATENCY (client-observed):")
    print(f"  Mean:                  {statistics.mean(latencies):.2f}s")
    print(f"  Median:                {statistics.median(latencies):.2f}s")
    print(f"  P95:                   {percentile(latencies, 0.95):.2f}s")
    print(f"  P99:                   {percentile(latencies, 0.99):.2f}s")

    print("\nPER-REQUEST OUTPUT TPS (client-observed):")
    print(f"  Mean:                  {statistics.mean(tps_per_request):.2f}")
    print(f"  Std dev:               {statistics.stdev(tps_per_request) if len(tps_per_request) > 1 else 0:.2f}")
    print(f"  Min:                   {min(tps_per_request):.2f}")
    print(f"  Max:                   {max(tps_per_request):.2f}")

    print_sglang_metrics_report(
        BASE_URL,
        API_KEY,
        MODEL,
        sglang_metrics_start,
        sglang_metrics_end,
        metadata=sglang_model_metadata,
    )
    print_sglang_batch_throughput_report(sglang_batch_report)

    if failed:
        print("\nFAILED REQUESTS (first 10):")
        for result in failed[:10]:
            print(f"  Request {result.request_id}: {result.error}")
        if len(failed) > 10:
            print(f"  ... and {len(failed) - 10} more")


if __name__ == "__main__":
    seed_random()
    if PREVIEW_SAMPLES > 0:
        print_sample_preview()
    else:
        asyncio.run(run_benchmark())
