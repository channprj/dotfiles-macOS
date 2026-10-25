#!/usr/bin/env python3
"""Install shared agent skills from a requirements-style manifest."""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from urllib.parse import urlparse

DEFAULT_MANIFEST_CANDIDATES = ("skills.txt", "agents/skills.txt")
LOCK_FILE = Path.home() / ".agents" / ".skill-lock.json"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_MANIFEST = SCRIPT_DIR / "skills.txt"
DEFAULT_INVENTORY = SCRIPT_DIR / "skills.inventory.tsv"
DEFAULT_SOURCES = SCRIPT_DIR / "skill-sources.tsv"
DEFAULT_LOCAL_SKILLS = SCRIPT_DIR / "local-skills"
GSTACK_SOURCE = "garrytan/gstack"
SKIP_POOL_NAMES = {".DS_Store", ".system", "skills", "compound-engineering"}
AGENT_SKILL_DIRS = {
    "claude": ".claude/skills",
    "codex": ".codex/skills",
    "cursor": ".cursor/skills",
    "grok": ".grok/skills",
}


class SkillsError(RuntimeError):
    """Raised when the manifest or environment is invalid."""


@dataclass(frozen=True)
class ManifestEntry:
    line_no: int
    add_args: tuple[str, ...]
    kind: str = "npx"
    file_name: str = ""
    file_path: str = ""
    agents: tuple[str, ...] = ()


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "install":
            if args.requirement and args.path:
                raise SkillsError("pass either a positional manifest path or -r/--requirement, not both")
            manifest_path = find_manifest(args.requirement or args.path)
            entries = parse_manifest(manifest_path)
            if not entries:
                raise SkillsError(f"No installable entries found in {manifest_path}")
            run_install(entries, manifest_path, dry_run=args.dry_run)
            return 0

        if args.command == "freeze":
            text = freeze_manifest(args.format, args.lock_file)
            if args.output:
                write_output(Path(args.output), text)
                print(f"Wrote manifest to {args.output}")
            else:
                sys.stdout.write(text)
            return 0

        if args.command == "snapshot":
            manifest_text, inventory_text, summary = build_snapshot(
                lock_file=Path(args.lock_file),
                pool=Path(args.pool),
                sources=Path(args.sources),
                local_skills=Path(args.local_skills),
            )
            if args.dry_run:
                sys.stdout.write(manifest_text)
                sys.stdout.write(inventory_text)
                return 0
            write_output(Path(args.manifest), manifest_text)
            write_output(Path(args.inventory), inventory_text)
            print(summary)
            return 0

        if args.command == "self-test":
            self_test()
            return 0

        parser.print_help()
        return 1
    except SkillsError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Install shared agent skills into ~/.agents/skills."
    )
    subparsers = parser.add_subparsers(dest="command")
    subparsers.required = True

    install_parser = subparsers.add_parser(
        "install",
        help="Install skills from a skills.txt-style manifest.",
    )
    install_parser.add_argument(
        "path",
        nargs="?",
        help="Optional manifest path. Same as -r/--requirement.",
    )
    install_parser.add_argument(
        "-r",
        "--requirement",
        help="Manifest file to install, like pip install -r.",
    )
    install_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the npx commands without running them.",
    )

    freeze_parser = subparsers.add_parser(
        "freeze",
        help="Export installed shared skills as a manifest.",
    )
    freeze_parser.add_argument(
        "-o",
        "--output",
        help="Write the generated manifest to a file instead of stdout.",
    )
    freeze_parser.add_argument(
        "--format",
        choices=("npx", "github"),
        default="npx",
        help="Output format. 'npx' is compact; 'github' is one exact skill path per line.",
    )
    freeze_parser.add_argument(
        "--lock-file",
        default=str(LOCK_FILE),
        help="Path to the npx skills lock file. Defaults to ~/.agents/.skill-lock.json.",
    )

    snapshot_parser = subparsers.add_parser(
        "snapshot",
        help="Rewrite skills.txt and skills.inventory.tsv from this machine.",
    )
    snapshot_parser.add_argument("--lock-file", default=str(LOCK_FILE))
    snapshot_parser.add_argument("--pool", default=str(Path.home() / ".agents" / "skills"))
    snapshot_parser.add_argument("--sources", default=str(DEFAULT_SOURCES))
    snapshot_parser.add_argument("--local-skills", default=str(DEFAULT_LOCAL_SKILLS))
    snapshot_parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    snapshot_parser.add_argument("--inventory", default=str(DEFAULT_INVENTORY))
    snapshot_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the manifest and inventory without writing them.",
    )

    subparsers.add_parser(
        "self-test",
        help="Check snapshot grouping without reading the live skill pool.",
    )

    return parser


def find_manifest(explicit_path: str | None) -> Path:
    cwd = Path.cwd()

    if explicit_path:
        path = Path(explicit_path).expanduser()
        if not path.is_absolute():
            path = cwd / path
        if not path.is_file():
            raise SkillsError(f"Manifest not found: {path}")
        return path.resolve()

    for base in (cwd, *cwd.parents):
        for candidate in DEFAULT_MANIFEST_CANDIDATES:
            path = base / candidate
            if path.is_file():
                return path.resolve()

    raise SkillsError(
        "Could not find a manifest. Pass -r/--requirement or create "
        "skills.txt or agents/skills.txt."
    )


def parse_manifest(path: Path) -> list[ManifestEntry]:
    entries: list[ManifestEntry] = []

    for line_no, logical_line in iter_logical_lines(path):
        tokens = shlex.split(logical_line, posix=True)
        if not tokens:
            continue

        directive = tokens[0]
        if directive == "npx":
            entries.append(parse_npx_entry(path, line_no, tokens))
            continue
        if directive == "github":
            entries.append(parse_github_entry(path, line_no, tokens))
            continue
        if directive == "file":
            entries.append(parse_file_entry(path, line_no, tokens))
            continue

        raise SkillsError(
            f"{path}:{line_no}: unsupported directive {directive!r}. "
            "Use 'npx' or 'github'."
        )

    return entries


def iter_logical_lines(path: Path) -> list[tuple[int, str]]:
    logical_lines: list[tuple[int, str]] = []
    buffer: list[str] = []
    start_line = 0

    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = raw_line.strip()

        if not buffer and (not stripped or stripped.startswith("#")):
            continue

        if not buffer:
            start_line = line_no

        if raw_line.rstrip().endswith("\\"):
            buffer.append(raw_line.rstrip()[:-1].strip())
            continue

        buffer.append(raw_line.strip())
        logical_line = " ".join(part for part in buffer if part)
        buffer.clear()

        if logical_line and not logical_line.startswith("#"):
            logical_lines.append((start_line, logical_line))

    if buffer:
        raise SkillsError(f"{path}:{start_line}: dangling line continuation")

    return logical_lines


def parse_npx_entry(path: Path, line_no: int, tokens: list[str]) -> ManifestEntry:
    add_args = tokens[1:]
    if add_args[:2] == ["skills", "add"]:
        add_args = add_args[2:]

    if not add_args:
        raise SkillsError(f"{path}:{line_no}: npx entry is missing a package or URL")

    disallowed_flags = {"-g", "--global", "-y", "--yes", "-a", "--agent", "-l", "--list"}
    for token in add_args:
        if token in disallowed_flags:
            raise SkillsError(
                f"{path}:{line_no}: {token} is managed by this script; omit it from the manifest"
            )

    return ManifestEntry(line_no=line_no, add_args=tuple(add_args))


def parse_github_entry(path: Path, line_no: int, tokens: list[str]) -> ManifestEntry:
    if len(tokens) < 2:
        raise SkillsError(f"{path}:{line_no}: github entry is missing a repo or URL")

    repo_or_url = tokens[1]
    skill_path: str | None = None
    ref = "main"

    index = 2
    while index < len(tokens):
        token = tokens[index]
        if token == "--ref":
            index += 1
            if index >= len(tokens):
                raise SkillsError(f"{path}:{line_no}: --ref requires a value")
            ref = tokens[index]
        elif token == "--path":
            index += 1
            if index >= len(tokens):
                raise SkillsError(f"{path}:{line_no}: --path requires a value")
            skill_path = tokens[index]
        elif token.startswith("-"):
            raise SkillsError(f"{path}:{line_no}: unsupported github option {token}")
        elif skill_path is None:
            skill_path = token
        else:
            raise SkillsError(
                f"{path}:{line_no}: unexpected token {token!r}; use 'github owner/repo path/to/skill'"
            )
        index += 1

    target_url = build_github_target(repo_or_url, skill_path, ref, path, line_no)
    return ManifestEntry(line_no=line_no, add_args=(target_url,))


def build_github_target(
    repo_or_url: str,
    skill_path: str | None,
    ref: str,
    manifest_path: Path,
    line_no: int,
) -> str:
    if repo_or_url.startswith("https://") or repo_or_url.startswith("http://"):
        parsed = urlparse(repo_or_url)
        host = parsed.netloc.lower()
        if host not in {"github.com", "www.github.com"}:
            raise SkillsError(
                f"{manifest_path}:{line_no}: only github.com URLs are supported in github entries"
            )

        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) < 2:
            raise SkillsError(f"{manifest_path}:{line_no}: invalid GitHub URL: {repo_or_url}")

        owner = parts[0]
        repo = parts[1][:-4] if parts[1].endswith(".git") else parts[1]

        if len(parts) >= 5 and parts[2] == "tree":
            if skill_path is not None:
                raise SkillsError(
                    f"{manifest_path}:{line_no}: skill path must not be repeated when the URL already points to /tree/..."
                )
            return repo_or_url.rstrip("/")

        if skill_path is None:
            raise SkillsError(
                f"{manifest_path}:{line_no}: github repo URLs need a skill path unless they already point to /tree/<ref>/<path>"
            )
        return f"https://github.com/{owner}/{repo}/tree/{ref}/{clean_skill_path(skill_path)}"

    repo = repo_or_url.strip("/")
    if repo.endswith(".git"):
        repo = repo[:-4]
    if repo.count("/") != 1:
        raise SkillsError(
            f"{manifest_path}:{line_no}: github repo must be in owner/repo format"
        )
    if skill_path is None:
        raise SkillsError(
            f"{manifest_path}:{line_no}: github owner/repo entries need a skill path"
        )
    return f"https://github.com/{repo}/tree/{ref}/{clean_skill_path(skill_path)}"


def clean_skill_path(path: str) -> str:
    return path.strip().lstrip("/")


def parse_file_entry(path: Path, line_no: int, tokens: list[str]) -> ManifestEntry:
    if len(tokens) < 3:
        raise SkillsError(f"{path}:{line_no}: file entry needs a name and a path")

    name = tokens[1]
    relative_path = tokens[2]
    agents: list[str] = []
    index = 3
    while index < len(tokens):
        token = tokens[index]
        if token != "--agent":
            raise SkillsError(f"{path}:{line_no}: unsupported file option {token}")
        index += 1
        if index >= len(tokens):
            raise SkillsError(f"{path}:{line_no}: --agent requires a value")
        agent = tokens[index]
        if agent not in AGENT_SKILL_DIRS:
            known = ", ".join(sorted(AGENT_SKILL_DIRS))
            raise SkillsError(f"{path}:{line_no}: unknown agent {agent!r}; use one of {known}")
        agents.append(agent)
        index += 1

    if not agents:
        raise SkillsError(f"{path}:{line_no}: file entry needs at least one --agent")

    return ManifestEntry(
        line_no=line_no,
        add_args=(),
        kind="file",
        file_name=name,
        file_path=relative_path,
        agents=tuple(agents),
    )


def run_install(entries: list[ManifestEntry], manifest_path: Path, dry_run: bool) -> None:
    if any(entry.kind == "npx" for entry in entries) and shutil.which("npx") is None:
        raise SkillsError("npx was not found in PATH")

    total = len(entries)
    for index, entry in enumerate(entries, start=1):
        if entry.kind == "file":
            print(f"[{index}/{total}] file {entry.file_name}")
            install_file(entry, manifest_path, dry_run=dry_run)
            continue

        command = [
            "npx",
            "--yes",
            "skills",
            "add",
            *entry.add_args,
            "-g",
            "--agent",
            "universal",
            "-y",
            "--full-depth",
        ]
        print(f"[{index}/{total}] {shell_join(command)}")

        if dry_run:
            continue

        try:
            subprocess.run(command, check=True)
        except subprocess.CalledProcessError as exc:
            raise SkillsError(
                f"{manifest_path}:{entry.line_no}: install failed with exit code {exc.returncode}"
            ) from exc


def freeze_manifest(format_name: str, lock_file: str) -> str:
    lock_path = Path(lock_file).expanduser()
    if not lock_path.is_absolute():
        lock_path = Path.cwd() / lock_path
    if not lock_path.is_file():
        raise SkillsError(f"Lock file not found: {lock_path}")

    data = json.loads(lock_path.read_text(encoding="utf-8"))
    skills = data.get("skills")
    if not isinstance(skills, dict) or not skills:
        raise SkillsError(f"No installed skills found in {lock_path}")

    header = [
        "# Shared agent skills manifest",
        f"# Generated by agents/install_skills.py freeze on {datetime.now().astimezone().date().isoformat()}",
        "# Install with: python3 agents/install_skills.py install -r agents/skills.txt",
        "",
    ]

    if format_name == "github":
        body = format_github_manifest(skills)
    else:
        body = format_npx_manifest(skills)

    return "\n".join(header + body) + "\n"


def format_npx_manifest(skills: dict[str, dict[str, object]]) -> list[str]:
    by_source: dict[str, list[str]] = defaultdict(list)

    for skill_name, meta in sorted(skills.items()):
        source = source_name(meta)
        if not source:
            raise SkillsError(f"Missing source metadata for skill {skill_name}")
        by_source[source].append(skill_name)

    rendered: list[str] = []
    for source in sorted(by_source):
        skill_names = sorted(set(by_source[source]))
        rendered.append(render_npx_entry(source, skill_names))
        rendered.append("")

    if rendered:
        rendered.pop()
    return rendered


def format_github_manifest(skills: dict[str, dict[str, object]]) -> list[str]:
    lines: list[str] = []

    for skill_name in sorted(skills):
        meta = skills[skill_name]
        source = source_name(meta)
        skill_path = meta.get("skillPath")
        if not source or not isinstance(skill_path, str):
            raise SkillsError(f"Missing source metadata for skill {skill_name}")
        skill_dir = PurePosixPath(skill_path).parent.as_posix()
        lines.append(shell_join(["github", source, skill_dir]))

    return lines


def source_name(meta: dict[str, object]) -> str | None:
    source = meta.get("source")
    if isinstance(source, str) and source:
        return source

    source_url = meta.get("sourceUrl")
    if not isinstance(source_url, str) or not source_url:
        return None

    parsed = urlparse(source_url)
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 2:
        return None

    owner = parts[0]
    repo = parts[1][:-4] if parts[1].endswith(".git") else parts[1]
    return f"{owner}/{repo}"


def render_npx_entry(source: str, skill_names: list[str]) -> str:
    if len(skill_names) == 1:
        return shell_join(["npx", source, "--skill", skill_names[0]])

    lines = [f"npx {shlex.quote(source)} \\"]
    for index, skill_name in enumerate(skill_names):
        suffix = " \\" if index < len(skill_names) - 1 else ""
        lines.append(f"  --skill {shlex.quote(skill_name)}{suffix}")
    return "\n".join(lines)


def shell_join(parts: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def write_output(path: Path, text: str) -> None:
    output_path = path.expanduser()
    if not output_path.is_absolute():
        output_path = Path.cwd() / output_path
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="utf-8")


def install_file(entry: ManifestEntry, manifest_path: Path, dry_run: bool) -> None:
    source = (manifest_path.parent / entry.file_path).resolve()
    if not (source / "SKILL.md").is_file():
        raise SkillsError(f"{manifest_path}:{entry.line_no}: {source} has no SKILL.md")

    for agent in entry.agents:
        dest = Path.home() / AGENT_SKILL_DIRS[agent] / entry.file_name
        print(f"  copy {source} -> {dest}")
        if dry_run:
            continue
        if dest.exists() or dest.is_symlink():
            print(f"  already present: {dest}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, dest)


def load_lock_skills(lock_file: Path) -> dict[str, dict[str, object]]:
    lock_path = lock_file.expanduser()
    if not lock_path.is_file():
        raise SkillsError(f"Lock file not found: {lock_path}")
    data = json.loads(lock_path.read_text(encoding="utf-8"))
    skills = data.get("skills")
    if not isinstance(skills, dict) or not skills:
        raise SkillsError(f"No installed skills found in {lock_path}")
    return skills


def read_source_map(path: Path) -> dict[str, tuple[str, str]]:
    if not path.is_file():
        return {}

    mapped: dict[str, tuple[str, str]] = {}
    for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        columns = stripped.split("\t")
        if len(columns) != 3:
            raise SkillsError(f"{path}:{line_no}: expected skill, source, and skillPath")
        name, source, skill_path = columns
        if not name or not source or not skill_path:
            raise SkillsError(f"{path}:{line_no}: blank skill, source, or skillPath")
        mapped[name] = (source, skill_path)
    return mapped


def discover_file_skills(local_skills: Path) -> list[tuple[str, str]]:
    if not local_skills.is_dir():
        return []

    found: list[tuple[str, str]] = []
    for child in sorted(local_skills.iterdir()):
        if child.is_dir() and (child / "SKILL.md").is_file():
            found.append((child.name, f"local-skills/{child.name}"))
    return found


def skills_for_snapshot(
    locked: dict[str, dict[str, object]],
    pool: Path,
    source_map: dict[str, tuple[str, str]],
) -> dict[str, dict[str, object]]:
    skills = dict(locked)
    if not pool.is_dir():
        raise SkillsError(f"Skill pool not found: {pool}")

    gstack_root = pool / "gstack"
    for child in sorted(pool.iterdir()):
        if child.name in skills or child.name in SKIP_POOL_NAMES:
            continue
        if child.is_symlink() or not (child / "SKILL.md").is_file():
            continue

        twin = gstack_root / child.name / "SKILL.md"
        if twin.is_file():
            skills[child.name] = {
                "source": GSTACK_SOURCE,
                "skillPath": f"{child.name}/SKILL.md",
            }
            continue

        extra = source_map.get(child.name)
        if extra is None:
            continue
        source, skill_path = extra
        skills[child.name] = {"source": source, "skillPath": skill_path}

    return skills


def render_snapshot_manifest(
    skills: dict[str, dict[str, object]],
    file_skills: list[tuple[str, str]],
) -> str:
    today = datetime.now().astimezone().date().isoformat()
    header = [
        "# Shared agent skills manifest",
        f"# Generated by agents/install_skills.py snapshot on {today}",
        "# Install on another machine from this repo:",
        "#   python3 agents/install_skills.py install",
        "# Refresh this file after installing or removing shared skills:",
        "#   python3 agents/install_skills.py snapshot",
        "#",
        "# npx lines reinstall ~/.agents/skills from upstream.",
        "# file lines copy skills stored in this repo.",
        "# App skills such as Codex .system, Chronicle, ego-browser, and",
        "# terminal-browser stay out of this file. See skills.inventory.tsv.",
        "",
    ]
    body = format_npx_manifest(skills)
    lines = header + body
    if file_skills:
        lines.append("")
        lines.append("# Skills stored in this repo. They are copied, not fetched.")
        # ponytail: repo skills install for Claude only. Add --agent when another agent needs one.
        for name, _relative in file_skills:
            lines.append(shell_join(["file", name, f"local-skills/{name}", "--agent", "claude"]))
    return "\n".join(lines) + "\n"


def render_inventory(
    home: Path,
    pool: Path,
    manifest_names: set[str],
    file_names: set[str],
) -> str:
    today = datetime.now().astimezone().date().isoformat()
    header = [
        "# Installed agent skills inventory",
        f"# Last synced: {today}",
        "#",
        "# Generated by agents/install_skills.py snapshot.",
        "# Reinstall the shared pool with:",
        "#   python3 agents/install_skills.py install",
        "#",
        "# Columns: agent, skill, source, note",
        "#   shared    - symlink into ~/.agents/skills, or a pool directory",
        "#   local     - directory that belongs to one agent",
        "#   external  - symlink outside the shared pool",
        "#   system    - bundled with the agent",
        "# note:",
        "#   manifest         - skills.txt installs it",
        "#   local-copy       - agent directory whose name skills.txt installs from upstream",
        "#   not-in-manifest  - present here, but skills.txt does not install it",
        "#   broken-symlink   - link target is missing",
        "",
    ]
    rows: list[tuple[str, str, str, str]] = []
    for agent, relative in AGENT_SKILL_DIRS.items():
        root = home / relative
        if not root.is_dir():
            continue
        for entry in sorted(root.iterdir(), key=lambda item: item.name):
            classified = classify_installed(entry, pool, manifest_names, home, file_names)
            if classified is None:
                continue
            source, note = classified
            rows.append((agent, entry.name, source, note))

    if pool.is_dir():
        for entry in sorted(pool.iterdir(), key=lambda item: item.name):
            if entry.name in manifest_names or entry.name == ".DS_Store":
                continue
            classified = classify_installed(entry, pool, manifest_names, home, file_names)
            if classified is None:
                continue
            source, note = classified
            rows.append(("pool", entry.name, source, note))

    lines = header
    for agent, skill, source, note in rows:
        lines.append("\t".join((agent, skill, source, note)))
    return "\n".join(lines) + "\n"


def classify_installed(
    entry: Path,
    pool: Path,
    manifest_names: set[str],
    home: Path,
    file_names: set[str],
) -> tuple[str, str] | None:
    if entry.name == ".DS_Store":
        return None

    if entry.is_symlink():
        if not entry.exists():
            return ("shared", "broken-symlink")
        resolved = entry.resolve()
        try:
            resolved.relative_to(pool.resolve())
        except ValueError:
            return ("external", display_path(Path(entry.readlink()), home))
        note = "manifest" if entry.name in manifest_names else "not-in-manifest"
        return ("shared", note)

    if entry.name == ".system" or entry.name.startswith("."):
        return ("system", "bundled")

    if entry.is_dir():
        try:
            entry.resolve().relative_to(pool.resolve())
            in_pool = True
        except ValueError:
            in_pool = False
        if in_pool:
            note = "manifest" if entry.name in manifest_names else "not-in-manifest"
            return ("shared", note)
        if entry.name in file_names:
            return ("local", "manifest")
        if entry.name in manifest_names:
            return ("local", "local-copy")
        return ("local", "not-in-manifest")

    return None


def display_path(path: Path, home: Path) -> str:
    if path.is_absolute():
        try:
            return "~/" + path.relative_to(home).as_posix()
        except ValueError:
            return path.as_posix()
    return path.as_posix()


def build_snapshot(
    lock_file: Path,
    pool: Path,
    sources: Path,
    local_skills: Path,
    home: Path | None = None,
) -> tuple[str, str, str]:
    home = Path.home() if home is None else home
    locked = load_lock_skills(lock_file)
    source_map = read_source_map(sources)
    skills = skills_for_snapshot(locked, pool, source_map)
    file_skills = discover_file_skills(local_skills)
    file_names = {name for name, _relative in file_skills}
    manifest_names = set(skills) | file_names
    manifest_text = render_snapshot_manifest(skills, file_skills)
    inventory_text = render_inventory(home, pool, manifest_names, file_names)
    summary = (
        f"snapshot: {len(skills)} shared skills, {len(file_skills)} repo skills, "
        f"{inventory_text.count(chr(10)) - manifest_header_lines(inventory_text)} inventory rows"
    )
    return manifest_text, inventory_text, summary


def manifest_header_lines(text: str) -> int:
    count = 0
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            count += 1
            continue
        break
    return count


def self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        pool = root / "pool"
        home = root / "home"
        (pool / "gstack" / "autoplan").mkdir(parents=True)
        (pool / "gstack" / "SKILL.md").write_text("name: gstack\n", encoding="utf-8")
        (pool / "gstack" / "autoplan" / "SKILL.md").write_text("name: autoplan\n", encoding="utf-8")
        (pool / "autoplan").mkdir()
        (pool / "autoplan" / "SKILL.md").write_text("name: autoplan\n", encoding="utf-8")
        (pool / "gcpr").mkdir()
        (pool / "gcpr" / "SKILL.md").write_text("name: gcpr\n", encoding="utf-8")
        (pool / "chronicle").mkdir()
        (pool / "chronicle" / "SKILL.md").write_text("name: chronicle\n", encoding="utf-8")
        (pool / "gone").symlink_to(pool / "missing")

        local = root / "local-skills" / "auto-civil-defense"
        local.mkdir(parents=True)
        (local / "SKILL.md").write_text("---\nname: auto-civil-defense\n---\n", encoding="utf-8")

        sources = root / "skill-sources.tsv"
        sources.write_text(
            "gcpr\tchann/skills\tgit-skill/skills/gcpr/SKILL.md\n",
            encoding="utf-8",
        )
        lock = root / "lock.json"
        lock.write_text(
            json.dumps(
                {
                    "skills": {
                        "gstack": {"source": "garrytan/gstack", "skillPath": "SKILL.md"},
                        "pdf": {"source": "anthropics/skills", "skillPath": "skills/pdf/SKILL.md"},
                    }
                }
            ),
            encoding="utf-8",
        )
        claude = home / ".claude" / "skills"
        claude.mkdir(parents=True)
        (claude / "pdf").symlink_to(pool / "pdf")
        (claude / "mine").mkdir()
        (claude / "mine" / "SKILL.md").write_text("name: mine\n", encoding="utf-8")
        codex = home / ".codex" / "skills"
        codex.mkdir(parents=True)
        (codex / "pdf").mkdir()
        (codex / "pdf" / "SKILL.md").write_text("name: pdf\n", encoding="utf-8")

        manifest_text, inventory_text, _summary = build_snapshot(
            lock, pool, sources, root / "local-skills", home
        )
        manifest = root / "skills.txt"
        manifest.write_text(manifest_text, encoding="utf-8")
        entries = parse_manifest(manifest)
        by_kind = {entry.kind for entry in entries}
        names = []
        for entry in entries:
            if entry.kind == "file":
                names.append(entry.file_name)
            else:
                names.extend(token for token in entry.add_args if token != "--skill")

        if "autoplan" not in manifest_text or "garrytan/gstack" not in manifest_text:
            raise SkillsError("self-test failed: gstack child was not added")
        if "gcpr" not in manifest_text:
            raise SkillsError("self-test failed: source map skill was not added")
        if "chronicle" in manifest_text:
            raise SkillsError("self-test failed: untracked pool skill entered the manifest")
        if "file" not in by_kind or "auto-civil-defense" not in names:
            raise SkillsError("self-test failed: repo skill was not recorded")
        if "pdf" not in manifest_text:
            raise SkillsError("self-test failed: locked skill was dropped")
        if "claude\tmine\tlocal\tnot-in-manifest" not in inventory_text:
            raise SkillsError("self-test failed: local skill was not inventoried")
        if "codex\tpdf\tlocal\tlocal-copy" not in inventory_text:
            raise SkillsError("self-test failed: local copy of a shared skill was marked manifest")
        if "pool\tchronicle\tshared\tnot-in-manifest" not in inventory_text:
            raise SkillsError("self-test failed: untracked pool skill was not inventoried")
        if "pool\tgone\tshared\tbroken-symlink" not in inventory_text:
            raise SkillsError("self-test failed: broken symlink was not inventoried")

        file_entry = next(entry for entry in entries if entry.kind == "file")
        install_file(file_entry, manifest, dry_run=True)

    print("install_skills.py self-test ok")


if __name__ == "__main__":
    raise SystemExit(main())
