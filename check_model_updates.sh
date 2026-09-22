#!/bin/bash
# Script: check_model_updates.sh
# Purpose: List cached Hugging Face repositories whose default branch has a newer snapshot

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORKSPACE_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
DEFAULT_HF_HUB_CACHE="$WORKSPACE_DIR/models/huggingface/hub"
DEFAULT_WORKERS=16
DEFAULT_TIMEOUT=20
CHECK_INTERVAL_SECONDS=3600

STATE_DIR="$SCRIPT_DIR/tmp"
STATE_FILE="$STATE_DIR/check_model_updates.env"
LOCK_FILE="$STATE_DIR/check_model_updates.lock"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Check every Hugging Face repository in the local Hub cache and list the ones
whose current default-branch snapshot is not cached locally. Nothing is
downloaded and the cache is not modified.

Options:
  -p, --path PATH       Hugging Face Hub cache or HF_HOME directory
  -j, --workers COUNT   Concurrent Hub checks (default: $DEFAULT_WORKERS)
      --timeout SECONDS Timeout for each Hub request (default: $DEFAULT_TIMEOUT)
      --all             Show current repositories as well as updates
  -h, --help            Show this help message

Cache path priority:
  1. --path
  2. HF_HUB_CACHE
  3. HF_HOME/hub
  4. $DEFAULT_HF_HUB_CACHE

Authentication uses the normal Hugging Face configuration, including HF_TOKEN.
Each eligible run requires an interactive rate-limit confirmation; there is no
automatic-yes option. Only one Hub lookup may start per hour. The last attempt
is recorded in:
  $STATE_FILE

Exit status is nonzero if any cache entry or remote repository cannot be checked.
EOF
}

CACHE_PATH=""
WORKERS="${HF_UPDATE_CHECK_WORKERS:-$DEFAULT_WORKERS}"
TIMEOUT="${HF_UPDATE_CHECK_TIMEOUT:-$DEFAULT_TIMEOUT}"
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--path)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                print_error "$1 requires a path"
                exit 2
            fi
            CACHE_PATH="$2"
            shift 2
            ;;
        -j|--workers)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                print_error "$1 requires a worker count"
                exit 2
            fi
            WORKERS="$2"
            shift 2
            ;;
        --timeout)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                print_error "$1 requires a timeout"
                exit 2
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        --all)
            SHOW_ALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes|--auto)
            print_error "$1 cannot bypass the required Hugging Face rate-limit confirmation"
            exit 2
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use -h or --help for usage information" >&2
            exit 2
            ;;
    esac
done

# Serialize invocations so two processes cannot pass the hourly check together.
if ! mkdir -p -- "$STATE_DIR"; then
    print_error "Could not create state directory: $STATE_DIR"
    exit 1
fi

if ! command -v flock >/dev/null 2>&1; then
    print_error "Required command not found: flock"
    exit 1
fi

if ! exec 9>"$LOCK_FILE"; then
    print_error "Could not open lookup lock: $LOCK_FILE"
    exit 1
fi

if ! flock -n 9; then
    print_info "Another model-update check is already running; no Hugging Face lookup will be made."
    exit 0
fi

now_epoch="$(date +%s)"
if [[ -e "$STATE_FILE" ]]; then
    last_check_epoch="$(sed -n 's/^LAST_CHECK_EPOCH=//p' "$STATE_FILE" | head -n 1)"
    if [[ ! "$last_check_epoch" =~ ^[0-9]+$ ]]; then
        print_error "Invalid hourly-check state in $STATE_FILE; refusing to contact Hugging Face"
        exit 1
    fi

    if (( now_epoch < last_check_epoch )); then
        print_error "The hourly-check timestamp is in the future; refusing to contact Hugging Face"
        print_error "State file: $STATE_FILE"
        exit 1
    fi

    elapsed_seconds=$((now_epoch - last_check_epoch))
    if (( elapsed_seconds < CHECK_INTERVAL_SECONDS )); then
        remaining_seconds=$((CHECK_INTERVAL_SECONDS - elapsed_seconds))
        next_check_epoch=$((last_check_epoch + CHECK_INTERVAL_SECONDS))
        next_check_utc="$(date -u -d "@$next_check_epoch" '+%Y-%m-%d %H:%M:%S UTC')"
        print_info "A Hugging Face lookup already started within the past hour; no lookup will be made."
        print_info "Try again in ${remaining_seconds} second(s), after $next_check_utc."
        exit 0
    fi
fi

if [[ -z "$CACHE_PATH" ]]; then
    if [[ -n "${HF_HUB_CACHE:-}" ]]; then
        CACHE_PATH="$HF_HUB_CACHE"
    elif [[ -n "${HF_HOME:-}" ]]; then
        CACHE_PATH="${HF_HOME%/}/hub"
    else
        CACHE_PATH="$DEFAULT_HF_HUB_CACHE"
    fi
fi

CACHE_PATH="${CACHE_PATH/#\~/$HOME}"

# Accept either the Hub cache itself or its HF_HOME parent with --path.
if [[ -d "$CACHE_PATH/hub" ]]; then
    if ! compgen -G "$CACHE_PATH/models--*" >/dev/null \
        && ! compgen -G "$CACHE_PATH/datasets--*" >/dev/null \
        && ! compgen -G "$CACHE_PATH/spaces--*" >/dev/null; then
        CACHE_PATH="${CACHE_PATH%/}/hub"
    fi
fi

if [[ ! -d "$CACHE_PATH" ]]; then
    print_error "Hugging Face Hub cache does not exist: $CACHE_PATH"
    print_info "Activate an environment with: source ./launch_env.sh"
    exit 1
fi

print_info "Using Hugging Face Hub cache: $CACHE_PATH"

if ! { exec 8<>/dev/tty; } 2>/dev/null; then
    print_error "An interactive terminal is required for the Hugging Face rate-limit confirmation"
    exit 1
fi

echo -e "${YELLOW}[WARNING]${NC} This check contacts Hugging Face for every cached repository." >&8
echo "It may consume your Hugging Face API request allowance and could reach its rate limits." >&8
while true; do
    printf "Do you wish to continue? [y/N]: " >&8
    if ! IFS= read -r answer <&8; then
        print_error "Could not read the required rate-limit confirmation"
        exit 1
    fi

    case "${answer,,}" in
        y|yes)
            break
            ;;
        ""|n|no)
            print_info "Cancelled; no Hugging Face lookup was made."
            exit 0
            ;;
        *)
            echo "Please answer y or n." >&8
            ;;
    esac
done

# Record the attempt immediately before the Hub-aware checker starts. This is
# intentionally retained after interruptions and remote failures.
started_epoch="$(date +%s)"
if ! state_tmp="$(mktemp "$STATE_DIR/.check_model_updates.env.XXXXXX")"; then
    print_error "Could not create temporary hourly-check state in: $STATE_DIR"
    exit 1
fi
if ! {
    printf 'LAST_CHECK_EPOCH=%s\n' "$started_epoch"
    printf 'LAST_CHECK_UTC=%s\n' "$(date -u -d "@$started_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
} >"$state_tmp"; then
    rm -f -- "$state_tmp"
    print_error "Could not write hourly-check state: $STATE_FILE"
    exit 1
fi
if ! mv -f -- "$state_tmp" "$STATE_FILE"; then
    rm -f -- "$state_tmp"
    print_error "Could not install hourly-check state: $STATE_FILE"
    exit 1
fi

python3 - "$CACHE_PATH" "$WORKERS" "$TIMEOUT" "$SHOW_ALL" <<'PY'
from __future__ import annotations

import math
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

try:
    from huggingface_hub import HfApi, scan_cache_dir
except ImportError as exc:
    print(f"[ERROR] Missing Hugging Face Hub tooling: {exc}", file=sys.stderr)
    print(
        "[INFO] Activate an environment with 'source ./launch_env.sh' first.",
        file=sys.stderr,
    )
    raise SystemExit(1)


cache_dir = Path(sys.argv[1])
show_all = sys.argv[4].lower() == "true"

try:
    workers = int(sys.argv[2])
    if workers < 1:
        raise ValueError
except ValueError:
    print("[ERROR] --workers must be a positive integer", file=sys.stderr)
    raise SystemExit(2)

try:
    timeout = float(sys.argv[3])
    if timeout <= 0 or not math.isfinite(timeout):
        raise ValueError
except ValueError:
    print("[ERROR] --timeout must be a positive number", file=sys.stderr)
    raise SystemExit(2)

checked_at = datetime.now(timezone.utc)


def one_line(value: object, limit: int = 300) -> str:
    message = " ".join(str(value).split())
    if len(message) <= limit:
        return message
    return message[: limit - 3] + "..."


try:
    cache_info = scan_cache_dir(cache_dir)
except Exception as exc:
    print(f"[ERROR] Could not scan {cache_dir}: {one_line(exc)}", file=sys.stderr)
    raise SystemExit(1)

repos = sorted(cache_info.repos, key=lambda repo: (repo.repo_type, repo.repo_id.casefold()))
warnings = list(cache_info.warnings)

if not repos:
    print("No cached Hugging Face repositories were found.")
    if warnings:
        print("\nCache entries that could not be read:", file=sys.stderr)
        for warning in warnings:
            print(f"  - {one_line(warning)}", file=sys.stderr)
    raise SystemExit(1 if warnings else 0)

print(f"Checking {len(repos)} cached repositories against the Hub...")

thread_state = threading.local()


def get_api() -> HfApi:
    if not hasattr(thread_state, "api"):
        thread_state.api = HfApi()
    return thread_state.api


def format_age(modified: datetime) -> str:
    seconds = max(0, int((checked_at - modified).total_seconds()))
    for unit_seconds, unit_name in (
        (86_400, "day"),
        (3_600, "hour"),
        (60, "minute"),
    ):
        if seconds >= unit_seconds:
            value = seconds // unit_seconds
            suffix = "" if value == 1 else "s"
            return f"{value} {unit_name}{suffix} ago"

    suffix = "" if seconds == 1 else "s"
    return f"{seconds} second{suffix} ago"


CHANGE_CATEGORY_ORDER = (
    "weights",
    "tokenizer",
    "config",
    "template",
    "code",
    "data",
    "metadata",
    "other",
)

WEIGHT_SUFFIXES = (
    ".safetensors",
    ".bin",
    ".pt",
    ".pth",
    ".ckpt",
    ".gguf",
    ".onnx",
    ".h5",
    ".msgpack",
)
DATA_SUFFIXES = (
    ".arrow",
    ".csv",
    ".jsonl",
    ".ndjson",
    ".parquet",
    ".tar",
    ".tar.gz",
    ".tsv",
    ".webdataset",
    ".zip",
)
CODE_SUFFIXES = (
    ".c",
    ".cc",
    ".cpp",
    ".cu",
    ".go",
    ".h",
    ".hpp",
    ".java",
    ".js",
    ".py",
    ".rs",
    ".sh",
    ".ts",
)


def change_category(filename: str, repo_type: str) -> str:
    lowered = filename.lower()
    basename = lowered.rsplit("/", 1)[-1]

    if lowered.endswith(WEIGHT_SUFFIXES):
        return "weights"
    if any(
        marker in basename
        for marker in ("tokenizer", "vocab", "merges", "special_tokens", "sentencepiece", "spiece")
    ):
        return "tokenizer"
    if "chat_template" in basename or lowered.endswith((".jinja", ".jinja2")):
        return "template"
    if "config" in basename or basename.startswith("configuration_"):
        return "config"
    if lowered.endswith(CODE_SUFFIXES):
        return "code"
    if repo_type == "dataset" or lowered.endswith(DATA_SUFFIXES):
        return "data"
    if lowered.endswith((".json", ".md", ".rst", ".toml", ".txt", ".yaml", ".yml")):
        return "metadata"
    if basename in (".gitattributes", ".gitignore", "license", "notice"):
        return "metadata"
    return "other"


def remote_file_identity(sibling: object) -> str | None:
    lfs_info = getattr(sibling, "lfs", None)
    lfs_sha = getattr(lfs_info, "sha256", None)
    return lfs_sha or getattr(sibling, "blob_id", None)


def local_file_identity(local_file: Path) -> str | None:
    if not local_file.is_symlink():
        return None
    try:
        return local_file.readlink().name
    except OSError:
        return None


def preferred_comparison_snapshot(repo: object, remote_sha: str) -> Path | None:
    revisions = [revision for revision in repo.revisions if revision.commit_hash != remote_sha]
    if not revisions:
        revisions = list(repo.revisions)
    if not revisions:
        return None

    for ref_name in ("main", "master"):
        matching = [revision for revision in revisions if ref_name in revision.refs]
        if matching:
            return max(matching, key=lambda revision: revision.last_modified).snapshot_path

    return max(revisions, key=lambda revision: revision.last_modified).snapshot_path


def classify_snapshot_changes(repo: object, remote_info: object, remote_sha: str) -> str:
    local_snapshot = preferred_comparison_snapshot(repo, remote_sha)
    if local_snapshot is None:
        return "unknown"

    remote_files = {
        sibling.rfilename: sibling
        for sibling in (remote_info.siblings or ())
        if getattr(sibling, "rfilename", None)
    }
    changed_files: set[str] = set()

    for filename, sibling in remote_files.items():
        local_file = local_snapshot / filename
        if not local_file.exists():
            changed_files.add(filename)
            continue

        remote_identity = remote_file_identity(sibling)
        local_identity = local_file_identity(local_file)
        if remote_identity and local_identity:
            if remote_identity != local_identity:
                changed_files.add(filename)
            continue

        expected_size = getattr(sibling, "size", None)
        try:
            local_size = local_file.stat().st_size
        except OSError:
            changed_files.add(filename)
            continue
        if expected_size is not None and expected_size != local_size:
            changed_files.add(filename)

    try:
        local_files = {
            str(path.relative_to(local_snapshot))
            for path in local_snapshot.rglob("*")
            if path.is_file() or path.is_symlink()
        }
    except OSError:
        local_files = set()
    changed_files.update(local_files - set(remote_files))

    if not changed_files:
        return "commit only"

    categories = {
        change_category(filename, repo.repo_type)
        for filename in changed_files
    }
    return ", ".join(category for category in CHANGE_CATEGORY_ORDER if category in categories)


def snapshot_is_complete(repo: object, remote_info: object, remote_sha: str) -> bool:
    snapshot_path = repo.repo_path / "snapshots" / remote_sha
    if not snapshot_path.is_dir():
        return False

    for sibling in remote_info.siblings or ():
        filename = getattr(sibling, "rfilename", None)
        if not filename:
            continue

        local_file = snapshot_path / filename
        try:
            local_size = local_file.stat().st_size
        except OSError:
            return False

        expected_size = getattr(sibling, "size", None)
        if expected_size is not None and local_size != expected_size:
            return False

    return True


def check_repo(repo: object) -> dict[str, str]:
    local_shas = {revision.commit_hash for revision in repo.revisions}
    if not local_shas:
        raise RuntimeError("no local snapshots found")

    remote_info = get_api().repo_info(
        repo.repo_id,
        repo_type=repo.repo_type,
        timeout=timeout,
        files_metadata=True,
    )
    remote_sha = remote_info.sha
    if not remote_sha:
        raise RuntimeError("the Hub response did not include a snapshot commit")

    remote_modified = remote_info.last_modified
    if remote_modified is None:
        remote_age = "unknown"
    else:
        remote_modified = remote_modified.astimezone(timezone.utc)
        remote_age = format_age(remote_modified)

    has_remote_snapshot = remote_sha in local_shas
    is_current = has_remote_snapshot and snapshot_is_complete(repo, remote_info, remote_sha)
    changes = "none" if is_current else classify_snapshot_changes(repo, remote_info, remote_sha)
    return {
        "status": "current" if is_current else ("incomplete" if has_remote_snapshot else "update"),
        "type": repo.repo_type,
        "repo": repo.repo_id,
        "changes": changes,
        "age": remote_age,
    }


results: list[dict[str, str]] = []
failures: list[tuple[str, str, str]] = []
show_progress = sys.stderr.isatty()

with ThreadPoolExecutor(max_workers=min(workers, len(repos))) as executor:
    future_repos = {executor.submit(check_repo, repo): repo for repo in repos}
    for completed, future in enumerate(as_completed(future_repos), start=1):
        repo = future_repos[future]
        try:
            results.append(future.result())
        except Exception as exc:
            failures.append((repo.repo_type, repo.repo_id, one_line(exc)))

        if show_progress:
            print(
                f"\rChecked {completed}/{len(repos)} repositories",
                end="",
                file=sys.stderr,
                flush=True,
            )

if show_progress:
    print(file=sys.stderr)

results.sort(key=lambda item: (item["type"], item["repo"].casefold()))
pending = [item for item in results if item["status"] != "current"]
displayed = results if show_all else pending

if displayed:
    print("\nRepositories needing snapshot downloads:" if not show_all else "\nRepository status:")
    status_width = max(len("STATUS"), *(len(item["status"]) for item in displayed))
    repo_width = max(len("REPOSITORY"), *(len(item["repo"]) for item in displayed))
    changes_width = max(len("CHANGES"), *(len(item["changes"]) for item in displayed))
    age_width = max(len("AGE"), *(len(item["age"]) for item in displayed))
    print(
        f"{'STATUS':<{status_width}} {'TYPE':<8} {'REPOSITORY':<{repo_width}} "
        f"{'CHANGES':<{changes_width}} {'AGE':<{age_width}}"
    )
    print(
        f"{'-' * status_width} {'-' * 8} {'-' * repo_width} "
        f"{'-' * changes_width} {'-' * age_width}"
    )
    for item in displayed:
        print(
            f"{item['status']:<{status_width}} {item['type']:<8} {item['repo']:<{repo_width}} "
            f"{item['changes']:<{changes_width}} {item['age']:<{age_width}}"
        )
elif not pending:
    print("\nAll checked repositories already have the current Hub snapshot.")

if failures or warnings:
    # Keep stderr diagnostics after the stdout table when output is redirected.
    sys.stdout.flush()

if failures:
    print("\nRepositories that could not be checked:", file=sys.stderr)
    for repo_type, repo_id, error in sorted(failures, key=lambda item: (item[0], item[1].casefold())):
        print(f"  - {repo_type} {repo_id}: {error}", file=sys.stderr)

if warnings:
    print("\nCache entries that could not be read:", file=sys.stderr)
    for warning in warnings:
        print(f"  - {one_line(warning)}", file=sys.stderr)

current_count = sum(item["status"] == "current" for item in results)
update_count = sum(item["status"] == "update" for item in results)
incomplete_count = sum(item["status"] == "incomplete" for item in results)
print(
    "\nSummary: "
    f"{update_count} update(s), "
    f"{incomplete_count} incomplete snapshot(s), "
    f"{current_count} current, "
    f"{len(failures)} remote check failure(s), "
    f"{len(warnings)} cache warning(s)."
)

raise SystemExit(1 if failures or warnings else 0)
PY
