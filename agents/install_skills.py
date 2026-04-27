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


class SkillsError(RuntimeError):
    """Raised when the manifest or environment is invalid."""


@dataclass(frozen=True)
class ManifestEntry:
    line_no: int
    add_args: tuple[str, ...]


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
                output_path = Path(args.output).expanduser()
                if not output_path.is_absolute():
                    output_path = Path.cwd() / output_path
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_text(text, encoding="utf-8")
                print(f"Wrote manifest to {output_path}")
            else:
                sys.stdout.write(text)
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


def run_install(entries: list[ManifestEntry], manifest_path: Path, dry_run: bool) -> None:
    if shutil.which("npx") is None:
        raise SkillsError("npx was not found in PATH")

    total = len(entries)
    for index, entry in enumerate(entries, start=1):
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


if __name__ == "__main__":
    raise SystemExit(main())
