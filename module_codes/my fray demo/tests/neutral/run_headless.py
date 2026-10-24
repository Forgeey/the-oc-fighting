"""Run neutral-state integration tests in an isolated copy (standard library only)."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(godot: str, project: Path, args: list[str], label: str) -> str:
    command = [godot, "--headless", "--path", str(project), *args]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace", timeout=120)
    print(f"--- {label} ---\n{result.stdout}", flush=True)
    if result.returncode or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)", result.stdout):
        raise SystemExit(f"{label} failed (exit {result.returncode})")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot console executable")
    options = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    godot = shutil.which(options.godot) or str(Path(options.godot).resolve())
    with tempfile.TemporaryDirectory(prefix="fray-neutral-") as temporary:
        project = Path(temporary) / "project"
        shutil.copytree(source, project, ignore=shutil.ignore_patterns(".godot", ".git", "tests"))
        # UIDs need a cache on first import. Use equivalent explicit paths only in the copy.
        settings = project / "project.godot"
        text = settings.read_text(encoding="utf-8")
        for name, script in (("FrayInputMap", "fray_input_map"), ("FrayInput", "fray_input")):
            text = re.sub(rf'^{name}="[^"]+"',
                          f'{name}="*res://addons/fray/src/input/autoloads/{script}.gd"',
                          text, flags=re.MULTILINE)
        settings.write_text(text, encoding="utf-8")
        shutil.copyfile(Path(__file__).with_name("test_neutral.gd"), project / "test_neutral.gd")
        (project / "test_neutral.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n'
            '[ext_resource type="Script" path="res://test_neutral.gd" id="1"]\n'
            '[node name="NeutralTests" type="Node"]\nscript = ExtResource("1")\n',
            encoding="utf-8")
        run(godot, project, ["--editor", "--import"], "Import")
        output = run(godot, project, ["--fixed-fps", "60", "res://test_neutral.tscn"], "Neutral tests")
        if not re.search(r"NEUTRAL TESTS: \d+ checks, 0 failures", output):
            raise SystemExit("Missing successful test summary")
        run(godot, project, ["--fixed-fps", "60", "--quit-after", "90"], "Default arena smoke test")


if __name__ == "__main__":
    main()
