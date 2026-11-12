"""Run movement-state integration tests in an isolated copy (standard library only)."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def run(godot: str, project: Path, args: list[str], label: str,
        expected_index_errors: int = 0, expected_selection_errors: int = 0) -> str:
    command = [godot, "--headless", "--path", str(project), *args]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace", timeout=30)
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        print(f"--- {label} timed out ---\n{output}", flush=True)
        raise SystemExit(f"{label} timed out")
    print(f"--- {label} ---\n{result.stdout}", flush=True)
    # Only this exact diagnostic is expected by sequence boundary rejection tests.
    index_error = r"(?m)^ERROR: Index out of range[ \t]*$"
    if len(re.findall(index_error, result.stdout)) != expected_index_errors:
        raise SystemExit(f"{label}: unexpected index-error count")
    checked_output = re.sub(index_error, "", result.stdout)
    selection_error = r"(?m)^ERROR: State selection rejected: [^\r\n]+$"
    if len(re.findall(selection_error, checked_output)) != expected_selection_errors:
        raise SystemExit(f"{label}: unexpected state-selection error count")
    checked_output = re.sub(selection_error, "", checked_output)
    if result.returncode or re.search(r"SCRIPT ERROR:|(?m:^ERROR:)", checked_output):
        raise SystemExit(f"{label} failed (exit {result.returncode})")
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot console executable")
    parser.add_argument("--suite", choices=("movement", "moves", "resources", "hits", "sequence", "catalog", "registration", "directions", "advancer", "commands", "timing", "matcher", "flat", "compound", "lifecycle", "cleanup"), default="movement")
    options = parser.parse_args()
    source = Path(__file__).resolve().parents[2]
    godot = shutil.which(options.godot) or str(Path(options.godot).resolve())
    with tempfile.TemporaryDirectory(prefix="fray-movement-") as temporary:
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
        test_source = source / {
            "movement": "tests/movement/test_movement.gd",
            "moves": "tests/moves/test_move_transitions.gd",
            "resources": "tests/movement/test_transition_resources.gd",
            "hits": "tests/hit/test_hit_assembly.gd",
            "sequence": "tests/input/test_sequence_tree.gd",
            "catalog": "tests/resources/test_state_catalog.gd",
            "registration": "tests/input/test_input_registration.gd",
            "directions": "tests/input/test_direction_history.gd",
            "advancer": "tests/input/test_native_advancer.gd",
            "commands": "tests/input/test_command_dispatch.gd",
            "timing": "tests/input/test_attack_timing.gd",
            "matcher": "tests/input/test_single_matcher.gd",
            "flat": "tests/input/test_flat_state_machine.gd",
            "compound": "tests/input/test_compound_exits.gd",
            "lifecycle": "tests/input/test_fray_compound_lifecycle.gd",
            "cleanup": "tests/input/test_input_cleanup.gd",
        }[options.suite]
        shutil.copytree(source / "tests" / "input", project / "tests" / "input")
        shutil.copyfile(test_source, project / "test_movement.gd")
        (project / "test_movement.tscn").write_text(
            '[gd_scene load_steps=2 format=3]\n'
            '[ext_resource type="Script" path="res://test_movement.gd" id="1"]\n'
            '[node name="MovementTests" type="Node"]\nscript = ExtResource("1")\n',
            encoding="utf-8")
        if options.suite == "resources":
            collection_tests = project / "tests" / "resources"
            collection_tests.mkdir(parents=True)
            shutil.copyfile(source / "tests/resources/test_resource_collections.gd",
                            collection_tests / "test_resource_collections.gd")
            shutil.copyfile(source / "tests/transitions/test_transition_serialization.gd",
                            project / "test_transition_serialization.gd")
            (project / "test_transition_serialization.tscn").write_text(
                '[gd_scene load_steps=2 format=3]\n'
                '[ext_resource type="Script" path="res://test_transition_serialization.gd" id="1"]\n'
                '[node name="SerializationTests" type="Node"]\nscript = ExtResource("1")\n',
                encoding="utf-8")
        run(godot, project, ["--editor", "--import"], "Import")
        if options.suite == "resources":
            # Non-tool resources use placeholder instances in the real editor.
            # Runtime-only tests miss exported-default type/serialization errors.
            plugin = project / "addons" / "transition_serialization_test"
            plugin.mkdir()
            (plugin / "plugin.cfg").write_text(
                '[plugin]\nname="Transition Serialization Test"\n'
                'description="Temporary editor regression test"\n'
                'author=""\nversion="1.0"\nscript="plugin.gd"\n', encoding="utf-8")
            (plugin / "plugin.gd").write_text(
                '@tool\nextends EditorPlugin\n'
                'func _enter_tree() -> void:\n\t_run_test.call_deferred()\n'
                'func _run_test() -> void:\n'
                '\tvar test := preload("res://test_transition_serialization.gd").new()\n'
                '\tadd_child(test)\n', encoding="utf-8")
            original_settings = settings.read_text(encoding="utf-8")
            enabled = 'enabled=PackedStringArray("res://addons/fray/plugin.cfg")'
            if enabled not in original_settings:
                raise SystemExit("Missing expected editor plugin configuration")
            settings.write_text(original_settings.replace(
                enabled, enabled[:-1] + ', "res://addons/transition_serialization_test/plugin.cfg")'),
                encoding="utf-8")
            try:
                editor_output = run(godot, project, ["--editor", "--quit-after", "600"],
                                    "Editor transition save/reload regression")
                if ("Serialization editor_hint=true" not in editor_output or
                        not re.search(r"TRANSITION SERIALIZATION TESTS: \d+ checks, 0 failures", editor_output)):
                    raise SystemExit("Missing successful editor serialization summary")
            finally:
                settings.write_text(original_settings, encoding="utf-8")
            # Save only the temporary copy, then start a fresh Godot process below.
            serialized = run(godot, project, ["--quit-after", "30", "res://test_transition_serialization.tscn"],
                             "Transition save/reload regression")
            if not re.search(r"TRANSITION SERIALIZATION TESTS: \d+ checks, 0 failures", serialized):
                raise SystemExit("Missing successful serialization summary")
        output = run(godot, project, ["--fixed-fps", "60", "--quit-after", "180", "res://test_movement.tscn"],
                     f"{options.suite} tests", expected_index_errors=8 if options.suite == "sequence" else 0,
                     expected_selection_errors=4 if options.suite == "catalog" else 0)
        summary = {
            "movement": "MOVEMENT TESTS",
            "moves": "MOVE TRANSITION TESTS",
            "resources": "TRANSITION RESOURCE TESTS",
            "hits": "HIT ASSEMBLY TESTS",
            "sequence": "SEQUENCE TREE TESTS",
            "catalog": "STATE CATALOG TESTS",
            "registration": "INPUT REGISTRATION TESTS",
            "directions": "DIRECTION HISTORY TESTS",
            "advancer": "NATIVE ADVANCER TESTS",
            "commands": "COMMAND DISPATCH TESTS",
            "timing": "ATTACK TIMING TESTS",
            "matcher": "SINGLE MATCHER TESTS",
            "flat": "FLAT STATE MACHINE TESTS",
            "compound": "COMPOUND EXIT TESTS",
            "lifecycle": "FRAY COMPOUND LIFECYCLE TESTS",
            "cleanup": "INPUT CLEANUP TESTS",
        }[options.suite]
        if not re.search(rf"{summary}: \d+ checks, 0 failures", output):
            raise SystemExit("Missing successful test summary")
        if options.suite == "movement":
            run(godot, project, ["--fixed-fps", "60", "--quit-after", "90"], "Default arena smoke test")


if __name__ == "__main__":
    main()
