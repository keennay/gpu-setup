import argparse
import asyncio
import random
import statistics
import sys
import time
import uuid
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

@dataclass(frozen=True)
class TokenBucket:
    name: str
    min_tokens: int
    max_tokens: int
    weight: float


INPUT_TOKEN_BUCKETS = [
    TokenBucket("small_bugfix", 2000, 6000, 0.45),
    TokenBucket("feature_task", 6000, 14000, 0.30),
    TokenBucket("refactor", 14000, 28000, 0.18),
    TokenBucket("deep_repo_context", 28000, 45000, 0.07),
]

OUTPUT_TOKEN_BUCKETS = [
    TokenBucket("small_patch", 80, 400, 0.45),
    TokenBucket("standard_patch", 400, 1200, 0.38),
    TokenBucket("large_patch", 1200, 3000, 0.17),
]

INPUT_BUCKET_DESCRIPTIONS = {
    "small_bugfix": "Focused fix with limited repo context",
    "feature_task": "Typical coding task spanning several modules",
    "refactor": "Broad change touching multiple subsystems",
    "deep_repo_context": "Large context window with long-tail repo state",
}

OUTPUT_BUCKET_DESCRIPTIONS = {
    "small_patch": "Concise patch and targeted tests",
    "standard_patch": "Normal patch with moderate explanation",
    "large_patch": "Large patch with expanded rationale/tests",
}

OUTPUT_BUCKET_EXPECTATIONS = {
    "small_patch": "Prefer concise output: minimal patch scope and short rationale.",
    "standard_patch": "Provide a complete patch, tests, and short implementation notes.",
    "large_patch": "Provide a broad patch with detailed tests, migration notes, and risk checks.",
}

PROMPT_SHAPES = {
    "small_bugfix": {"repo_files": (10, 20), "relevant_files": (1, 3), "failure_blocks": (1, 2), "constraints": (3, 4), "acceptance": (2, 4)},
    "feature_task": {"repo_files": (18, 35), "relevant_files": (3, 6), "failure_blocks": (2, 3), "constraints": (4, 5), "acceptance": (4, 6)},
    "refactor": {"repo_files": (30, 55), "relevant_files": (5, 10), "failure_blocks": (3, 5), "constraints": (5, 7), "acceptance": (6, 9)},
    "deep_repo_context": {"repo_files": (45, 75), "relevant_files": (8, 16), "failure_blocks": (4, 7), "constraints": (6, 8), "acceptance": (8, 12)},
}

CODING_TASK_INTROS = [
    "You are an autonomous coding agent operating in a production monorepo. Implement the request using only the provided context.\n{output_expectation}",
    "Act as a software engineer fixing and extending an existing codebase. Produce concrete code changes only after analyzing context.\n{output_expectation}",
    "You are responsible for unblocking CI by implementing the required code changes and tests in this repository.\n{output_expectation}",
]

ISSUE_SCOPES = [
    "retry handling",
    "cache invalidation",
    "request deduplication",
    "websocket reconnect flow",
    "pagination cursor logic",
    "permission checks",
    "background job scheduling",
    "idempotency enforcement",
    "feature flag gating",
    "transaction boundaries",
]

ISSUE_ACTIONS = [
    "Fix regression",
    "Implement missing behavior",
    "Stabilize flaky path",
    "Prevent race condition",
    "Remove duplicate side effects",
    "Enforce validation",
]

SERVICES = [
    "API gateway",
    "checkout service",
    "billing worker",
    "auth service",
    "search indexer",
    "notifications pipeline",
    "session manager",
    "rate-limit middleware",
    "artifact sync service",
]

SYMPTOMS = [
    "Requests intermittently return stale data after cache refresh.",
    "Concurrent updates can write duplicate records.",
    "A refactor introduced inconsistent error mapping.",
    "The new code path bypasses validation under load.",
    "Tests pass locally but fail in CI with timing-sensitive assertions.",
    "A rollout gate is ignored for one execution path.",
]

IMPACTS = [
    "Increased support tickets and user-visible retries.",
    "Intermittent 500s during peak traffic windows.",
    "Data consistency alerts in nightly validation jobs.",
    "Latency spikes due to repeated fallback calls.",
    "Deployment blocked by failing integration tests.",
]

AGENT_CONSTRAINTS = [
    "Do not change public API response shapes.",
    "Keep backward compatibility with Python 3.10 runtime.",
    "Avoid introducing new third-party dependencies.",
    "Preserve existing feature-flag behavior for disabled tenants.",
    "Ensure idempotent behavior for retryable operations.",
    "Keep DB migration-free unless absolutely required.",
    "Maintain current logging field names used by dashboards.",
    "Keep changes compatible with Linux and macOS CI runners.",
]

ACCEPTANCE_CHECKS = [
    "All affected unit tests pass.",
    "Integration test for retry flow passes.",
    "No new lint or type-check violations.",
    "Concurrency edge case is covered by a deterministic test.",
    "Failure path returns the expected error code and message.",
    "Metrics labels remain unchanged for existing dashboards.",
    "Feature-flag-off behavior remains unchanged.",
    "Existing snapshot tests remain stable.",
]

FILE_CATALOG = [
    "src/agent/planner.py",
    "src/agent/executor.py",
    "src/agent/state/store.py",
    "src/agent/state/events.py",
    "src/server/http/app.py",
    "src/server/http/middleware/auth.py",
    "src/server/http/middleware/rate_limit.py",
    "src/server/http/routes/sessions.py",
    "src/server/http/routes/checkout.py",
    "src/server/http/routes/search.py",
    "src/server/http/routes/notifications.py",
    "src/server/http/routes/feature_flags.py",
    "src/server/http/schemas/payloads.py",
    "src/server/http/schemas/errors.py",
    "src/services/cache/redis_client.py",
    "src/services/cache/invalidation.py",
    "src/services/cache/ttl_policy.py",
    "src/services/billing/invoice_runner.py",
    "src/services/billing/retry_policy.py",
    "src/services/billing/events.py",
    "src/services/search/index_manager.py",
    "src/services/search/query_builder.py",
    "src/services/search/ranker.py",
    "src/services/checkout/cart.py",
    "src/services/checkout/discounts.py",
    "src/services/checkout/payment_intents.py",
    "src/services/auth/tokens.py",
    "src/services/auth/session_store.py",
    "src/services/auth/permissions.py",
    "src/services/notifications/dispatcher.py",
    "src/services/notifications/retry_queue.py",
    "src/services/notifications/providers/email.py",
    "src/services/notifications/providers/sms.py",
    "src/repository/orders.py",
    "src/repository/users.py",
    "src/repository/audit_log.py",
    "src/repository/feature_flags.py",
    "src/repository/session_events.py",
    "src/lib/concurrency/locks.py",
    "src/lib/concurrency/pool.py",
    "src/lib/retry/backoff.py",
    "src/lib/retry/policies.py",
    "src/lib/observability/logging.py",
    "src/lib/observability/metrics.py",
    "src/lib/observability/tracing.py",
    "src/lib/config/runtime.py",
    "src/lib/config/loader.py",
    "src/lib/errors/mapping.py",
    "src/lib/errors/codes.py",
    "src/lib/serialization/json_codec.py",
    "src/lib/validation/request_rules.py",
    "src/lib/validation/schema_registry.py",
    "src/jobs/sync_artifacts.py",
    "src/jobs/rebuild_index.py",
    "src/jobs/reconcile_sessions.py",
    "src/jobs/cleanup_stale_locks.py",
    "src/cli/seed_test_data.py",
    "src/cli/replay_events.py",
    "src/cli/run_migrations.py",
    "src/config/defaults.yaml",
    "src/config/production.yaml",
    "src/config/development.yaml",
    "src/config/feature_flags.yaml",
    "tests/unit/test_retry_policy.py",
    "tests/unit/test_cache_invalidation.py",
    "tests/unit/test_permission_checks.py",
    "tests/unit/test_checkout_totals.py",
    "tests/unit/test_session_store.py",
    "tests/integration/test_checkout_flow.py",
    "tests/integration/test_auth_refresh.py",
    "tests/integration/test_feature_flag_rollout.py",
    "tests/integration/test_search_reindex.py",
    "tests/e2e/test_notifications_pipeline.py",
    "tests/e2e/test_multi_tenant_isolation.py",
    "web/src/pages/checkout.tsx",
    "web/src/pages/sessions.tsx",
    "web/src/lib/api.ts",
    "web/src/lib/queryClient.ts",
    "web/src/components/FeatureBanner.tsx",
    "scripts/ci/run_lint.sh",
    "scripts/ci/run_tests.sh",
    "scripts/ci/verify_schema.sh",
    "docker/Dockerfile.api",
    "docker/Dockerfile.worker",
    "k8s/deploy/api-deployment.yaml",
    "k8s/deploy/worker-deployment.yaml",
]

CODE_SNIPPETS_BY_LANG = {
    "python": [
        "def apply_retry(policy, operation):\n    attempt = 0\n    last_error = None\n    while attempt <= policy.max_attempts:\n        try:\n            return operation()\n        except Exception as err:\n            last_error = err\n            if attempt == policy.max_attempts:\n                raise\n            time.sleep(policy.backoff(attempt))\n            attempt += 1\n    raise last_error",
        "async def invalidate_user_cache(cache, user_id):\n    keys = [f\"user:{user_id}\", f\"permissions:{user_id}\"]\n    for key in keys:\n        await cache.delete(key)\n    await cache.publish(\"cache.invalidate\", {\"user_id\": user_id})",
        "class SessionStore:\n    def __init__(self, db, ttl_seconds):\n        self.db = db\n        self.ttl_seconds = ttl_seconds\n\n    def save(self, session):\n        expires_at = int(time.time()) + self.ttl_seconds\n        self.db.upsert(\"sessions\", {\"id\": session.id, \"expires_at\": expires_at})",
    ],
    "typescript": [
        "export async function fetchCheckoutTotal(cartId: string): Promise<number> {\n  const response = await api.get(`/checkout/${cartId}/total`);\n  if (!response.ok) throw new Error(\"checkout total failed\");\n  const body = await response.json();\n  return body.totalCents;\n}",
        "type FeatureContext = { tenantId: string; flag: string };\n\nexport function isFeatureEnabled(flags: Record<string, boolean>, ctx: FeatureContext): boolean {\n  const key = `${ctx.tenantId}:${ctx.flag}`;\n  return Boolean(flags[key] ?? flags[ctx.flag]);\n}",
        "export function dedupeById<T extends { id: string }>(items: T[]): T[] {\n  const seen = new Set<string>();\n  return items.filter((item) => {\n    if (seen.has(item.id)) return false;\n    seen.add(item.id);\n    return true;\n  });\n}",
    ],
    "go": [
        "func EnqueueRetry(queue Queue, payload []byte, max int) error {\n    for attempt := 0; attempt < max; attempt++ {\n        if err := queue.Publish(payload); err == nil {\n            return nil\n        }\n        time.Sleep(time.Duration(attempt+1) * 50 * time.Millisecond)\n    }\n    return errors.New(\"retry publish exhausted\")\n}",
        "func ResolveTenant(headers map[string]string) (string, error) {\n    tenant, ok := headers[\"X-Tenant-ID\"]\n    if !ok || tenant == \"\" {\n        return \"\", fmt.Errorf(\"missing tenant header\")\n    }\n    return tenant, nil\n}",
    ],
    "rust": [
        "pub fn normalize_error(code: &str) -> &'static str {\n    match code {\n        \"timeout\" => \"ERR_TIMEOUT\",\n        \"rate_limited\" => \"ERR_RATE_LIMIT\",\n        \"unauthorized\" => \"ERR_UNAUTHORIZED\",\n        _ => \"ERR_INTERNAL\",\n    }\n}",
        "pub fn stable_partition<T: Clone, F>(items: &[T], pred: F) -> (Vec<T>, Vec<T>)\nwhere\n    F: Fn(&T) -> bool,\n{\n    let mut pass = Vec::new();\n    let mut fail = Vec::new();\n    for item in items {\n        if pred(item) { pass.push(item.clone()); } else { fail.push(item.clone()); }\n    }\n    (pass, fail)\n}",
    ],
    "yaml": [
        "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: api-service\nspec:\n  template:\n    spec:\n      containers:\n        - name: api\n          image: registry.local/api:latest\n          env:\n            - name: FEATURE_FLAG_REFRESH_INTERVAL\n              value: \"30s\"",
        "services:\n  api:\n    command: [\"./scripts/ci/run_tests.sh\"]\n    environment:\n      - PYTHONUNBUFFERED=1\n      - ENABLE_RETRY_ASSERTIONS=true",
    ],
    "json": [
        "{\n  \"featureFlags\": {\n    \"checkout.newRetryPath\": true,\n    \"notifications.strictTenantIsolation\": false\n  },\n  \"cache\": {\n    \"ttlSeconds\": 120,\n    \"refreshJitterMs\": 250\n  }\n}",
        "{\n  \"name\": \"agent-service\",\n  \"scripts\": {\n    \"lint\": \"eslint .\",\n    \"typecheck\": \"tsc --noEmit\",\n    \"test\": \"vitest run\"\n  }\n}",
    ],
    "bash": [
        "set -euo pipefail\npytest tests/unit -q\npytest tests/integration -q -k \"not flaky\"\n",
        "set -euo pipefail\nnpm run lint\nnpm run typecheck\nnpm run test -- --runInBand\n",
    ],
    "text": [
        "TODO:\n- Reproduce issue with deterministic input\n- Add regression test first\n- Apply minimal patch\n- Validate under retry + timeout path\n",
    ],
}

EXT_TO_LANG = {
    "py": "python",
    "ts": "typescript",
    "tsx": "typescript",
    "js": "typescript",
    "go": "go",
    "rs": "rust",
    "yaml": "yaml",
    "yml": "yaml",
    "json": "json",
    "sh": "bash",
}

DEFAULT_MIN_INPUT = min(bucket.min_tokens for bucket in INPUT_TOKEN_BUCKETS)
DEFAULT_MAX_INPUT = max(bucket.max_tokens for bucket in INPUT_TOKEN_BUCKETS)
DEFAULT_MIN_OUTPUT = min(bucket.min_tokens for bucket in OUTPUT_TOKEN_BUCKETS)
DEFAULT_MAX_OUTPUT = max(bucket.max_tokens for bucket in OUTPUT_TOKEN_BUCKETS)


def parse_args():
    parser = argparse.ArgumentParser(
        description="LLM Throughput Benchmark (coding-agent workload)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Example usage:
  python benchmark.py --model glm-4.7-fp8
  python benchmark.py --model glm-4.5-air --concurrency 500 --num-prompts 500
  python benchmark.py --model glm-4.7-fp8 --port 8001
  python benchmark.py --model glm-4.7-fp8 --api-key MY_REAL_KEY --base-url http://remote:8000/v1
  python benchmark.py --model qwen3.5-27b --label "Qwen3.5-27B"
  python benchmark.py --preview-samples 2
        """,
    )

    required = parser.add_argument_group("required arguments")
    required.add_argument("--model", type=str, required=False, help="Model name (required for live benchmark)")

    optional = parser.add_argument_group("optional arguments (with defaults)")
    optional.add_argument("--api-key", type=str, default="YOUR_API_KEY", help="API key (default: YOUR_API_KEY)")
    optional.add_argument("--concurrency", type=int, default=100, help="Number of concurrent requests (default: 100)")
    optional.add_argument("--num-prompts", type=int, default=100, help="Total number of prompts to run (default: 100)")
    optional.add_argument("--base-url", type=str, default="http://localhost:8000/v1", help="API base URL (default: http://localhost:8000/v1)")
    optional.add_argument("--port", type=int, default=8000, help="API port for the default localhost base URL (default: 8000)")
    optional.add_argument("--label", dest="run_label", type=str, help="Display label for benchmark/result headers (default: model name)")
    optional.add_argument("--min-input", type=int, default=DEFAULT_MIN_INPUT, help=f"Minimum input tokens (default: {DEFAULT_MIN_INPUT})")
    optional.add_argument("--max-input", type=int, default=DEFAULT_MAX_INPUT, help=f"Maximum input tokens (default: {DEFAULT_MAX_INPUT})")
    optional.add_argument("--min-output", type=int, default=DEFAULT_MIN_OUTPUT, help=f"Minimum sampled max_tokens cap (default: {DEFAULT_MIN_OUTPUT})")
    optional.add_argument("--max-output", type=int, default=DEFAULT_MAX_OUTPUT, help=f"Maximum sampled max_tokens cap (default: {DEFAULT_MAX_OUTPUT})")
    optional.add_argument("--output-cap", type=int, default=None, help="Fixed max_tokens cap per request (default: sample from --min-output/--max-output)")
    optional.add_argument("--sample-output-cap", action="store_true", help=argparse.SUPPRESS)
    optional.add_argument("--temperature", "--temp", dest="temperature", type=float, default=0.2, help="Sampling temperature (default: 0.2)")
    optional.add_argument("--timeout", type=int, default=3600, help="Timeout per request in seconds (default: 3600)")
    optional.add_argument("--warmup", type=int, default=3, help="Number of warmup requests (default: 3)")
    optional.add_argument("--seed", type=int, default=None, help="Random seed for reproducible prompt sampling (default: random)")
    optional.add_argument("--ignore-eos", dest="ignore_eos", action="store_true", default=False, help="Force full output length by ignoring EOS (default: natural stopping)")
    optional.add_argument("--no-ignore-eos", dest="ignore_eos", action="store_false", help=argparse.SUPPRESS)
    optional.add_argument(
        "--preview-samples",
        type=int,
        default=0,
        help="Print N generated coding-agent prompts and exit without API calls (default: 0)",
    )

    args = parser.parse_args()

    errors = []
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
    if args.preview_samples < 0:
        errors.append("--preview-samples must be >= 0")
    if args.preview_samples == 0 and not args.model:
        errors.append("--model is required unless --preview-samples is used")

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
NUM_PROMPTS = args.num_prompts
CONCURRENCY = args.concurrency
PORT = args.port
TIMEOUT_PER_REQUEST = args.timeout
WARMUP_REQUESTS = args.warmup
MIN_INPUT_TOKENS = args.min_input
MAX_INPUT_TOKENS = args.max_input
MIN_OUTPUT_TOKENS = args.min_output
MAX_OUTPUT_TOKENS = args.max_output
OUTPUT_CAP = None if args.sample_output_cap else args.output_cap
TEMPERATURE = args.temperature
IGNORE_EOS = args.ignore_eos
PREVIEW_SAMPLES = args.preview_samples
RANDOM_SEED = args.seed

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


def run_header(prefix: str, label: str | None = None) -> str:
    return f"{prefix}: {label or RUN_LABEL} | Prompts: {NUM_PROMPTS} | Concurrency: {CONCURRENCY}"


def format_optional_tps(value: float | None) -> str:
    if value is None or value <= 0:
        return "N/A"
    return f"{value:.2f}"


def seed_random():
    if RANDOM_SEED is None:
        random.seed()
    else:
        random.seed(RANDOM_SEED)


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


def language_for_path(path: str) -> str:
    ext = path.rsplit(".", 1)[-1] if "." in path else ""
    return EXT_TO_LANG.get(ext, "text")


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


def sample_input_tokens() -> tuple[int, str]:
    return pick_weighted_token_count(MIN_INPUT_TOKENS, MAX_INPUT_TOKENS, INPUT_TOKEN_BUCKETS)


def sample_output_tokens() -> tuple[int, str]:
    return pick_weighted_token_count(MIN_OUTPUT_TOKENS, MAX_OUTPUT_TOKENS, OUTPUT_TOKEN_BUCKETS)


def choose_output_cap() -> tuple[int, str]:
    if OUTPUT_CAP is not None:
        return OUTPUT_CAP, "fixed_cap"
    return sample_output_tokens()


def generate_ticket_section(input_bucket: str) -> str:
    severity_weights = {
        "small_bugfix": [0.2, 0.55, 0.25],
        "feature_task": [0.25, 0.5, 0.25],
        "refactor": [0.35, 0.45, 0.2],
        "deep_repo_context": [0.45, 0.4, 0.15],
    }
    severity = random.choices(["P1", "P2", "P3"], weights=severity_weights.get(input_bucket, [0.25, 0.5, 0.25]), k=1)[0]
    ticket_id = f"{random.choice(['ENG', 'BUG', 'PLAT', 'OPS'])}-{random.randint(1000, 9999)}"
    service = random.choice(SERVICES)
    action = random.choice(ISSUE_ACTIONS)
    scope = random.choice(ISSUE_SCOPES)
    symptom = random.choice(SYMPTOMS)
    impact = random.choice(IMPACTS)
    repro_count = random.randint(2, 4) + (1 if input_bucket in {"refactor", "deep_repo_context"} else 0)

    repro_steps = []
    for idx in range(repro_count):
        if idx == 0:
            repro_steps.append(f"{idx + 1}. Deploy latest main branch for {service}.")
        elif idx == repro_count - 1:
            repro_steps.append(f"{idx + 1}. Observe mismatch in metrics and assertion failures.")
        else:
            repro_steps.append(f"{idx + 1}. Execute workload replay with retry + timeout enabled.")

    return (
        f"## Ticket\n"
        f"ID: {ticket_id}\n"
        f"Title: {action} in {service} ({scope})\n"
        f"Severity: {severity}\n"
        f"Symptom: {symptom}\n"
        f"Impact: {impact}\n"
        f"Reproduction:\n"
        + "\n".join(repro_steps)
    )


def generate_repo_tree_section(repo_files: list[str]) -> str:
    return "## Repository Snapshot\n```text\n" + "\n".join(repo_files) + "\n```"


def get_snippet_for_path(path: str) -> str:
    lang = language_for_path(path)
    pool = CODE_SNIPPETS_BY_LANG.get(lang, CODE_SNIPPETS_BY_LANG["text"])
    return random.choice(pool)


def generate_relevant_files_section(relevant_files: list[str]) -> str:
    blocks = ["## Relevant Files"]
    for path in relevant_files:
        language = language_for_path(path)
        snippet = get_snippet_for_path(path)
        start_line = random.randint(10, 240)
        end_line = start_line + max(3, len(snippet.splitlines()) - 1)
        blocks.append(f"### {path}:{start_line}-{end_line}\n```{language}\n{snippet}\n```")
    return "\n\n".join(blocks)


def generate_test_failure_block(repo_files: list[str]) -> str:
    test_targets = [p for p in repo_files if "/test" in p or p.startswith("tests/")]
    target = random.choice(test_targets) if test_targets else random.choice(repo_files)
    test_name = random.choice(
        [
            "test_retries_are_idempotent",
            "test_cache_invalidation_after_write",
            "test_feature_flag_rollout_respected",
            "test_checkout_total_stable_under_replay",
            "test_permissions_denied_for_missing_scope",
        ]
    )
    expected = random.choice(["200", "ERR_RATE_LIMIT", "single write", "cache miss", "enabled=false path"])
    actual = random.choice(["500", "ERR_INTERNAL", "duplicate write", "stale cache hit", "enabled=true path"])
    duration = random.randint(1200, 6800)
    return (
        "```text\n"
        f"$ pytest {target} -k {test_name}\n"
        f"E AssertionError: expected {expected}, got {actual}\n"
        f"E at {target}::{test_name}\n"
        f"===================== {random.randint(1, 5)} failed, {random.randint(40, 200)} passed in {duration}ms =====================\n"
        "```"
    )


def generate_traceback_block(repo_files: list[str]) -> str:
    path = random.choice(repo_files)
    line = random.randint(20, 300)
    request_id = f"req_{uuid.uuid4().hex[:10]}"
    err = random.choice(
        [
            "KeyError: tenant_id",
            "RuntimeError: optimistic lock conflict",
            "ValueError: invalid cursor format",
            "TimeoutError: upstream read timed out",
            "AssertionError: duplicate side effect detected",
        ]
    )
    return (
        "```text\n"
        f"request_id={request_id}\n"
        f"Traceback (most recent call last):\n"
        f"  File \"{path}\", line {line}, in handle_request\n"
        f"    result = await service.execute(payload)\n"
        f"  File \"{path}\", line {line + 7}, in execute\n"
        f"    return reducer.apply(state, event)\n"
        f"{err}\n"
        "```"
    )


def generate_lint_block(repo_files: list[str]) -> str:
    target_files = random.sample(repo_files, k=min(len(repo_files), random.randint(2, 4)))
    lines = ["```text", "$ ./scripts/ci/run_lint.sh"]
    for path in target_files:
        lines.append(
            f"{path}:{random.randint(5, 180)}:{random.randint(1, 30)} "
            f"{random.choice(['E722', 'E501', 'F401', 'F821'])} "
            f"{random.choice(['line too long', 'unused import', 'undefined name', 'bare except'])}"
        )
    lines.append("```")
    return "\n".join(lines)


def generate_typecheck_block(repo_files: list[str]) -> str:
    target = random.choice(repo_files)
    line = random.randint(10, 220)
    return (
        "```text\n"
        "$ npm run typecheck\n"
        f"{target}({line}, {random.randint(2, 20)}): "
        f"error TS{random.choice(['2322', '2339', '2345', '2532'])}: "
        f"{random.choice(['Type mismatch in return value', 'Property does not exist', 'Argument type is incompatible', 'Object is possibly undefined'])}\n"
        "```"
    )


def generate_diagnostics_section(input_bucket: str, repo_files: list[str]) -> str:
    shape = PROMPT_SHAPES[input_bucket]
    block_count = random.randint(*shape["failure_blocks"])
    generators = [generate_test_failure_block, generate_traceback_block, generate_lint_block, generate_typecheck_block]
    blocks = [random.choice(generators)(repo_files) for _ in range(block_count)]
    return "## Failing Signals\n" + "\n\n".join(blocks)


def generate_constraints_section(input_bucket: str) -> str:
    count = random.randint(*PROMPT_SHAPES[input_bucket]["constraints"])
    selected = random.sample(AGENT_CONSTRAINTS, k=min(count, len(AGENT_CONSTRAINTS)))
    return "## Constraints\n" + "\n".join(f"- {constraint}" for constraint in selected)


def generate_acceptance_section(input_bucket: str) -> str:
    count = random.randint(*PROMPT_SHAPES[input_bucket]["acceptance"])
    selected = random.sample(ACCEPTANCE_CHECKS, k=min(count, len(ACCEPTANCE_CHECKS)))
    return "## Acceptance Criteria\n" + "\n".join(f"- {criterion}" for criterion in selected)


def generate_response_contract(output_bucket: str) -> str:
    response_shape = [
        "1. Unified diff patch with file paths.",
        "2. Tests added/updated (or exact commands if no test changes required).",
        "3. Brief rationale of root cause and fix strategy.",
        "4. Risk check listing possible regressions.",
    ]
    if output_bucket == "small_patch":
        response_shape.append("5. Keep explanation short and focus on the minimal viable fix.")
    elif output_bucket == "large_patch":
        response_shape.append("5. Include migration notes and follow-up validation steps.")
    else:
        response_shape.append("5. Include commands to run lint + tests locally.")
    return "## Response Contract\n" + "\n".join(response_shape)


def generate_commit_history_block(repo_files: list[str]) -> str:
    entries = []
    for _ in range(random.randint(4, 8)):
        sha = "".join(random.choices("abcdef0123456789", k=7))
        message = random.choice(
            [
                "tighten retry guard in checkout flow",
                "move auth fallback to middleware",
                "normalize cache invalidation payload",
                "stabilize flaky integration assertion",
                "introduce feature flag helper for tenant overrides",
                "refactor session upsert path",
            ]
        )
        entries.append(f"{sha} {message} ({random.choice(repo_files)})")
    return "## Additional Context: Recent Commits\n```text\n" + "\n".join(entries) + "\n```"


def generate_ci_log_block(_: list[str]) -> str:
    lines = [
        "## Additional Context: CI Excerpt",
        "```text",
        "[build] running lint + unit + integration matrix",
        f"[lint] completed with {random.randint(0, 4)} warnings",
        f"[unit] passed={random.randint(220, 380)} failed={random.randint(0, 5)}",
        f"[integration] passed={random.randint(30, 70)} failed={random.randint(0, 3)}",
        f"[e2e] passed={random.randint(8, 20)} failed={random.randint(0, 2)}",
        f"[timing] p95={random.randint(120, 450)}ms p99={random.randint(350, 1200)}ms",
        "```",
    ]
    return "\n".join(lines)


def generate_dependency_block(_: list[str]) -> str:
    deps = [
        f"redis=={random.choice(['5.0.1', '5.0.6', '5.1.0'])}",
        f"fastapi=={random.choice(['0.112.0', '0.113.1', '0.114.0'])}",
        f"pydantic=={random.choice(['2.8.2', '2.9.1', '2.10.0'])}",
        f"pytest=={random.choice(['8.2.1', '8.3.0', '8.3.3'])}",
        f"typescript=={random.choice(['5.4.5', '5.5.4', '5.6.2'])}",
    ]
    return "## Additional Context: Dependency Snapshot\n```text\n" + "\n".join(deps) + "\n```"


def generate_runtime_metrics_block(repo_files: list[str]) -> str:
    hot_paths = random.sample(repo_files, k=min(len(repo_files), random.randint(3, 6)))
    rows = []
    for path in hot_paths:
        rows.append(
            f"{path} | calls/min={random.randint(50, 1200)} | "
            f"error_rate={random.uniform(0.01, 3.0):.2f}% | p95={random.randint(10, 420)}ms"
        )
    return "## Additional Context: Runtime Metrics\n```text\n" + "\n".join(rows) + "\n```"


def generate_additional_context_block(input_bucket: str, repo_files: list[str]) -> str:
    del input_bucket
    generators = [
        generate_commit_history_block,
        generate_ci_log_block,
        generate_dependency_block,
        generate_runtime_metrics_block,
    ]
    return random.choice(generators)(repo_files)


def build_coding_agent_prompt(input_bucket: str, output_bucket: str) -> tuple[str, list[str]]:
    shape = PROMPT_SHAPES[input_bucket]
    repo_count = min(len(FILE_CATALOG), random.randint(*shape["repo_files"]))
    repo_files = sorted(random.sample(FILE_CATALOG, k=repo_count))

    relevant_count = min(len(repo_files), random.randint(*shape["relevant_files"]))
    relevant_files = random.sample(repo_files, k=relevant_count)

    sections = [
        random.choice(CODING_TASK_INTROS).format(
            output_expectation=OUTPUT_BUCKET_EXPECTATIONS.get(output_bucket, OUTPUT_BUCKET_EXPECTATIONS["standard_patch"])
        ),
        generate_ticket_section(input_bucket),
        generate_repo_tree_section(repo_files),
        generate_relevant_files_section(relevant_files),
        generate_diagnostics_section(input_bucket, repo_files),
        generate_constraints_section(input_bucket),
        generate_acceptance_section(input_bucket),
        generate_response_contract(output_bucket),
    ]
    return "\n\n".join(sections), repo_files


def generate_unique_prompt(target_tokens: int, input_bucket: str, output_bucket: str) -> str:
    if RANDOM_SEED is None:
        request_uuid = uuid.uuid4()
        timestamp = time.time_ns()
    else:
        request_uuid = uuid.UUID(int=random.getrandbits(128))
        timestamp = random.getrandbits(63)

    unique_prefix = (
        f"[Request ID: {request_uuid}] "
        f"[Timestamp: {timestamp}] "
        f"[Random: {random.random()}] "
        f"[Input Bucket: {input_bucket}] "
        f"[Output Bucket: {output_bucket}]\n\n"
    )

    target_chars = max(1200, target_tokens * 4)
    prompt_body, repo_files = build_coding_agent_prompt(input_bucket, output_bucket)
    parts = [prompt_body]
    total_len = len(unique_prefix) + len(prompt_body)

    while total_len < target_chars:
        block = generate_additional_context_block(input_bucket, repo_files)
        parts.append(block)
        total_len += len(block) + 2

    return unique_prefix + "\n\n".join(parts)


def print_bucket_profile(buckets: list[TokenBucket], descriptions: dict[str, str]):
    for bucket in buckets:
        print(
            f"  {bucket.name:<18} "
            f"{bucket.min_tokens:>5}-{bucket.max_tokens:<5} "
            f"w={bucket.weight:.2f}  {descriptions.get(bucket.name, '')}"
        )


def print_sample_preview():
    print("\n" + "=" * 80)
    print(f"CODING-AGENT SAMPLE PREVIEW ({PREVIEW_SAMPLES} samples)")
    print("=" * 80)
    print(f"Input clamp:  {MIN_INPUT_TOKENS} - {MAX_INPUT_TOKENS}")
    if OUTPUT_CAP is not None:
        print(f"Output cap: {OUTPUT_CAP}")
    else:
        print(f"Output cap sampling: enabled ({MIN_OUTPUT_TOKENS} - {MAX_OUTPUT_TOKENS})")
    print("\nInput bucket profile:")
    print_bucket_profile(INPUT_TOKEN_BUCKETS, INPUT_BUCKET_DESCRIPTIONS)
    if OUTPUT_CAP is None:
        print("\nOutput bucket profile:")
        print_bucket_profile(OUTPUT_TOKEN_BUCKETS, OUTPUT_BUCKET_DESCRIPTIONS)

    for idx in range(PREVIEW_SAMPLES):
        input_len, input_bucket = sample_input_tokens()
        output_len, output_bucket = choose_output_cap()
        prompt = generate_unique_prompt(input_len, input_bucket, output_bucket)
        approx_tokens = max(1, len(prompt) // 4)
        preview_chars = min(len(prompt), 3200)

        print("\n" + "-" * 80)
        print(f"Sample {idx + 1}/{PREVIEW_SAMPLES}")
        print(f"Input tokens target:      {input_len} ({input_bucket})")
        print(f"Input tokens approximate: {approx_tokens}")
        print(f"Output tokens target:     {output_len} ({output_bucket})")
        print("-" * 80)
        print(prompt[:preview_chars])
        if len(prompt) > preview_chars:
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


async def run_single_request_streaming(request_id: int, progress: dict) -> RequestResult:
    input_len, input_bucket = sample_input_tokens()
    output_len, output_bucket = choose_output_cap()
    prompt = generate_unique_prompt(input_len, input_bucket, output_bucket)

    start = time.perf_counter()
    content_ttft = 0
    reasoning_ttft = 0
    completion_tokens = 0
    prompt_tokens = 0
    finish_reason = ""

    try:
        request_params = {
            "model": MODEL,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": output_len,
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
            request_id=request_id,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_time=end - start,
            content_ttft=content_ttft,
            reasoning_ttft=reasoning_ttft,
            input_len=input_len,
            output_len=output_len,
            input_bucket=input_bucket,
            output_bucket=output_bucket,
            finish_reason=finish_reason,
            success=not is_abort,
            error=f"finish_reason:{finish_reason}" if is_abort else None,
        )
    except asyncio.TimeoutError:
        result = RequestResult(
            request_id=request_id,
            success=False,
            error="timeout",
            input_len=input_len,
            output_len=output_len,
            input_bucket=input_bucket,
            output_bucket=output_bucket,
            finish_reason=finish_reason,
        )
    except Exception as exc:
        result = RequestResult(
            request_id=request_id,
            success=False,
            error=str(exc)[:120],
            input_len=input_len,
            output_len=output_len,
            input_bucket=input_bucket,
            output_bucket=output_bucket,
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
    if "uniform_clamped" in counts:
        count = counts["uniform_clamped"]
        pct = (count / len(results) * 100) if results else 0
        lines.append(f"  {'uniform_clamped':<18} {count:>4} ({pct:>5.1f}%)")
    expected_names = {bucket.name for bucket in expected_buckets} | {"uniform_clamped"}
    for key in sorted(counts):
        if key not in expected_names:
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

    seed_random()

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

    print(f"\n{'=' * 60}")
    print(run_header("BENCHMARK", display_run_label))
    print(f"{'=' * 60}")
    print()
    print(f"SGLang Version:      {sglang_model_metadata.sglang_version}")
    print(f"Model:               {display_model}")
    print(f"Port:                {PORT}")
    print(f"Base URL:            {BASE_URL}")
    print(f"SGLang log source:   {sglang_log_sources}")
    print("Streaming:           True")
    print("Radix cache:         disabled (expected)")
    print(f"Total requests:      {NUM_PROMPTS}")
    print(f"Concurrency:         {CONCURRENCY} (simulating {CONCURRENCY} agents)")
    print(f"Input tokens clamp:  {MIN_INPUT_TOKENS} - {MAX_INPUT_TOKENS}")
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

    async def bounded_request(i: int):
        async with semaphore:
            return await run_single_request_streaming(i, progress)

    try:
        overall_start = time.perf_counter()
        results = await asyncio.gather(*[bounded_request(i) for i in range(NUM_PROMPTS)])
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
    print(f"Avg input tokens (cfg):    {avg_input:.0f}")
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
