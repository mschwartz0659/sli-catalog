#!/usr/bin/env python3
"""sli-catalog command-line tool.

Fast feedback for slo.yaml files and the recipe catalog. The Terraform module is the
authority (its preconditions run at plan time); this tool mirrors its rules so mistakes
surface in CI before a plan runs. If the two disagree, the module wins and this is a bug.

Commands:
  validate FILE... [--render]   check slo.yaml files; --render prints the Datadog queries
  lint-catalog [DIR]            check every recipe in the catalog
  catalog-doc [--check]         write docs/catalog.md from the recipes (--check: fail if stale)
  self-test                     prove the checks pass good input and fail planted bad input
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
CATALOG_DIR = ROOT / "catalog" / "recipes"
SCHEMA_PATH = ROOT / "schema" / "slo.v1.schema.json"
CATALOG_DOC = ROOT / "docs" / "catalog.md"
FIXTURES = ROOT / "tests" / "fixtures"

CATEGORIES = ["availability", "latency", "quality", "freshness",
              "correctness", "coverage", "throughput", "durability"]
SOURCES = {"apm", "integration", "convention"}
STATUSES = {"draft", "verified", "deprecated"}
COMPARATORS = {">", ">=", "<", "<="}
BUILTINS = {"service", "env"}
WINDOW_HOURS = {"7d": 168, "30d": 720, "90d": 2160}
# Burn-rate tiers: share of the window's budget spent within the long window.
# Mirrors local.burn_tiers in modules/datadog-slo/main.tf.
BURN_TIERS = [
    ("page_fast", "page", 1, "5m", 0.02),
    ("page_slow", "page", 6, "30m", 0.05),
    ("ticket", "ticket", 24, "2h", 0.10),
]
VAR_RE = re.compile(r"\$\{([^}]*)\}")


class Problem(Exception):
    pass


# ---------------------------------------------------------------- recipes

def load_recipes(catalog_dir: Path = CATALOG_DIR) -> dict:
    recipes = {}
    for path in sorted(catalog_dir.glob("*.yaml")):
        recipes[path.stem] = yaml.safe_load(path.read_text())
    return recipes


def recipe_strings(recipe: dict) -> list[str]:
    out = []
    for block in (recipe.get("modes") or {}).values():
        out += [v for k, v in block.items() if isinstance(v, str)]
        out += list((block.get("queries") or {}).values())
    out += [v for v in (recipe.get("heartbeat") or {}).values() if isinstance(v, str)]
    return out


def lint_recipe(stem: str, r: dict) -> list[str]:
    errs = []
    if not isinstance(r, dict):
        return [f"{stem}: not a mapping"]
    for field in ("id", "category", "applies_to", "source", "status", "summary",
                  "good", "valid", "default_mode", "modes"):
        if field not in r:
            errs.append(f"{stem}: missing field '{field}'")
    if errs:
        return errs
    if r["id"] != stem:
        errs.append(f"{stem}: id '{r['id']}' does not match file name")
    if r["category"] not in CATEGORIES:
        errs.append(f"{stem}: category '{r['category']}' is not one of {CATEGORIES}")
    if r["source"] not in SOURCES:
        errs.append(f"{stem}: source '{r['source']}' is not one of {sorted(SOURCES)}")
    if r["status"] not in STATUSES:
        errs.append(f"{stem}: status '{r['status']}' is not one of {sorted(STATUSES)}")
    modes = r["modes"] or {}
    if not set(modes) <= {"events", "time_slice"} or not modes:
        errs.append(f"{stem}: modes must be events and/or time_slice")
    if r["default_mode"] not in modes:
        errs.append(f"{stem}: default_mode '{r['default_mode']}' is not defined under modes")
    if "events" in modes:
        for f in ("numerator", "denominator"):
            if not modes["events"].get(f):
                errs.append(f"{stem}: events mode missing '{f}'")
    if "time_slice" in modes:
        ts = modes["time_slice"]
        for f in ("queries", "formula", "comparator", "threshold"):
            if not ts.get(f):
                errs.append(f"{stem}: time_slice mode missing '{f}'")
        if ts.get("comparator") and ts["comparator"] not in COMPARATORS:
            errs.append(f"{stem}: comparator '{ts['comparator']}' is not one of {sorted(COMPARATORS)}")
        if ts.get("interval_seconds", 300) not in (60, 300):
            errs.append(f"{stem}: interval_seconds must be 60 or 300")
    hb = r.get("heartbeat")
    if hb is not None:
        for f in ("query", "threshold", "no_data_minutes"):
            if not hb.get(f):
                errs.append(f"{stem}: heartbeat missing '{f}'")
    params = r.get("params") or {}
    for name, p in params.items():
        if name in BUILTINS:
            errs.append(f"{stem}: param '{name}' shadows a built-in")
        if not isinstance(p, dict) or not p.get("description"):
            errs.append(f"{stem}: param '{name}' needs a description")
            continue
        if p.get("required") and "default" in p:
            errs.append(f"{stem}: param '{name}' is required and has a default; pick one")
        if not p.get("required") and "default" not in p:
            errs.append(f"{stem}: param '{name}' is optional but has no default")
    used = {v for s in recipe_strings(r) for v in VAR_RE.findall(s)}
    for v in sorted(used - set(params) - BUILTINS):
        errs.append(f"{stem}: uses ${{{v}}} but does not declare it as a param")
    for v in sorted(set(params) - used):
        errs.append(f"{stem}: declares param '{v}' but never uses it")
    return errs


def lint_catalog(catalog_dir: Path = CATALOG_DIR) -> list[str]:
    errs = []
    for stem, r in load_recipes(catalog_dir).items():
        errs += lint_recipe(stem, r)
    return errs


# ---------------------------------------------------------------- rendering

def render(text: str, variables: dict) -> tuple[str, set]:
    missing = set()

    def sub(m):
        key = m.group(1)
        if key in variables:
            return str(variables[key])
        missing.add(key)
        return f"<<MISSING:{key}>>"

    return VAR_RE.sub(sub, text), missing


def fmt_num(x) -> str:
    # Terraform tostring() prints whole numbers without a decimal point.
    if isinstance(x, float) and x.is_integer():
        return str(int(x))
    return str(x)


def resolve_slo(spec: dict, slo: dict, recipes: dict) -> dict:
    """Return the fully rendered SLO, or raise Problem. Mirrors local.slo in main.tf."""
    name = slo["name"]
    if slo["recipe"] == "custom":
        mode = "events" if "events" in slo else "time_slice"
        if slo.get("mode") and slo["mode"] != mode:
            raise Problem(f"slo '{name}': mode '{slo['mode']}' does not match the block given ({mode})")
        block = slo[mode]
        variables = {"service": spec["service"], "env": spec["env"]}
        category, heartbeat = slo["category"], None
    else:
        recipe = recipes.get(slo["recipe"])
        if recipe is None:
            raise Problem(f"slo '{name}': unknown recipe '{slo['recipe']}' "
                          f"(see docs/catalog.md for the menu)")
        mode = slo.get("mode", recipe["default_mode"])
        if mode not in recipe["modes"]:
            raise Problem(f"slo '{name}': recipe '{slo['recipe']}' has no '{mode}' mode "
                          f"(it has: {', '.join(recipe['modes'])})")
        unknown = set(slo.get("params") or {}) - set(recipe.get("params") or {})
        if unknown:
            raise Problem(f"slo '{name}': recipe '{slo['recipe']}' has no param(s) {sorted(unknown)}")
        variables = {k: fmt_num(p["default"]) for k, p in (recipe.get("params") or {}).items()
                     if "default" in p}
        variables.update({k: fmt_num(v) for k, v in (slo.get("params") or {}).items()})
        variables.update({"service": spec["service"], "env": spec["env"]})
        block = recipe["modes"][mode]
        category, heartbeat = recipe["category"], recipe.get("heartbeat")

    missing = set()

    def r(value):
        if isinstance(value, str):
            out, miss = render(value, variables)
            missing.update(miss)
            return out
        if isinstance(value, dict):
            return {k: r(v) for k, v in value.items()}
        return value

    block = r(block)
    heartbeat = r(heartbeat) if heartbeat else None
    if missing:
        raise Problem(f"slo '{name}': recipe '{slo['recipe']}' needs param(s) {sorted(missing)}")
    if mode == "time_slice":
        try:
            block["threshold"] = float(block["threshold"])
        except ValueError:
            raise Problem(f"slo '{name}': threshold '{block['threshold']}' is not a number")
    return {"name": name, "recipe": slo["recipe"], "category": category, "mode": mode,
            "target": slo["target"], "block": block, "heartbeat": heartbeat,
            "alerting": slo.get("alerting", spec.get("alerting", "observe"))}


def burn_alerts(window: str) -> list[dict]:
    hours = WINDOW_HOURS[window]
    out = []
    for key, severity, long_h, short, budget in BURN_TIERS:
        rate = round(budget * hours / long_h, 2)
        if rate > 1:
            out.append({"key": key, "severity": severity, "long": f"{long_h}h",
                        "short": short, "rate": rate, "budget_pct": int(budget * 100)})
    return out


# ---------------------------------------------------------------- validation

_schema_validator = None


def schema_validator():
    global _schema_validator
    if _schema_validator is None:
        import json
        _schema_validator = Draft202012Validator(json.loads(SCHEMA_PATH.read_text()))
    return _schema_validator


def validate_spec(spec, recipes: dict) -> tuple[list[str], list[dict]]:
    errs = []
    for e in sorted(schema_validator().iter_errors(spec), key=lambda e: list(e.path)):
        where = "/".join(str(p) for p in e.path) or "(top level)"
        errs.append(f"{where}: {e.message}")
    if errs:
        return errs, []
    seen, resolved = set(), []
    for slo in spec["slos"]:
        if slo["name"] in seen:
            errs.append(f"slo '{slo['name']}': name used twice")
            continue
        seen.add(slo["name"])
        if "warning" in slo and slo["warning"] <= slo["target"]:
            errs.append(f"slo '{slo['name']}': warning ({slo['warning']}) must be above target ({slo['target']})")
        try:
            resolved.append(resolve_slo(spec, slo, recipes))
        except Problem as p:
            errs.append(str(p))
    return errs, resolved


def print_render(spec: dict, resolved: list[dict]) -> None:
    window = spec.get("window", "30d")
    print(f"  service={spec['service']} env={spec['env']} window={window} "
          f"page=@pagerduty-{spec['routing']['page']}")
    for s in resolved:
        print(f"  - {s['name']}  [{s['category']}, {s['recipe']}, {s['mode']}]  "
              f"target {s['target']}%  alerting={s['alerting']}")
        b = s["block"]
        if s["mode"] == "events":
            print(f"      good:  {b['numerator']}")
            print(f"      total: {b['denominator']}")
        else:
            for q, text in b["queries"].items():
                print(f"      {q}: {text}")
            print(f"      good minute when: {b['formula']} {b['comparator']} {fmt_num(b['threshold'])}")
        if s["heartbeat"]:
            print(f"      heartbeat: {s['heartbeat']['query']} (no data after "
                  f"{s['heartbeat']['no_data_minutes']} min)")
    if any(s["alerting"] != "none" for s in resolved):
        tiers = ", ".join(f"{a['severity']} at {a['rate']}x over {a['long']}/{a['short']}"
                          for a in burn_alerts(window))
        print(f"  burn-rate alerts: {tiers}")


def cmd_validate(files: list[str], show: bool) -> int:
    recipes = load_recipes()
    failed = 0
    for f in files:
        try:
            spec = yaml.safe_load(Path(f).read_text())
        except (OSError, yaml.YAMLError) as e:
            print(f"FAIL {f}\n  {e}")
            failed += 1
            continue
        errs, resolved = validate_spec(spec, recipes)
        if errs:
            failed += 1
            print(f"FAIL {f}")
            for e in errs:
                print(f"  {e}")
        else:
            print(f"ok   {f}")
            if show:
                print_render(spec, resolved)
    return 1 if failed else 0


# ---------------------------------------------------------------- catalog doc

def catalog_markdown(recipes: dict) -> str:
    lines = [
        "# The menu",
        "",
        "<!-- Generated by `python3 scripts/sli.py catalog-doc` from catalog/recipes/. Do not edit by hand. -->",
        "",
        "Every recipe is a ready-made SLI: what counts as a good event and what counts as a valid one.",
        "Pick recipes in your `slo.yaml` by `id`. Status `draft` means the recipe has not yet been",
        "checked against real data in our Datadog org; `verified` means it has.",
        "",
        "Source: `apm` = needs Datadog APM on the service. `integration` = comes from a Datadog",
        "integration, no code. `convention` = you emit the metric named in",
        "[conventions.md](conventions.md).",
        "",
    ]
    by_cat = {}
    for r in recipes.values():
        by_cat.setdefault(r["category"], []).append(r)
    for cat in CATEGORIES:
        lines += [f"## {cat.capitalize()}", ""]
        if cat not in by_cat:
            lines += ["No recipe yet. Use `recipe: custom` (see the README).", ""]
            continue
        lines += ["| Recipe | For | Source | Status | Modes | Params (required in bold) | What it measures |",
                  "|---|---|---|---|---|---|---|"]
        for r in sorted(by_cat[cat], key=lambda r: r["id"]):
            params = ", ".join(
                (f"**{k}**" if p.get("required") else f"{k}={fmt_num(p['default'])}")
                for k, p in (r.get("params") or {}).items())
            modes = ", ".join(m + (" (default)" if m == r["default_mode"] else "") for m in r["modes"])
            lines.append(f"| `{r['id']}` | {', '.join(r['applies_to'])} | {r['source']} | "
                         f"{r['status']} | {modes} | {params} | {r['summary']} |")
        lines.append("")
    return "\n".join(lines)


def cmd_catalog_doc(check: bool) -> int:
    text = catalog_markdown(load_recipes())
    if check:
        if not CATALOG_DOC.exists() or CATALOG_DOC.read_text() != text:
            print("docs/catalog.md is out of date. Run: python3 scripts/sli.py catalog-doc")
            return 1
        print("ok   docs/catalog.md is current")
        return 0
    CATALOG_DOC.write_text(text)
    print("wrote docs/catalog.md")
    return 0


# ---------------------------------------------------------------- self-test

def expected(path: Path) -> str:
    first = path.read_text().splitlines()[0]
    m = re.match(r"#\s*expect:\s*(.+)", first)
    if not m:
        raise SystemExit(f"{path}: first line must be '# expect: <text>'")
    return m.group(1).strip()


def cmd_self_test() -> int:
    recipes = load_recipes()
    failures = []

    errs = lint_catalog()
    if errs:
        failures += [f"catalog: {e}" for e in errs]

    for p in sorted((FIXTURES / "valid").glob("*.yaml")):
        errs, _ = validate_spec(yaml.safe_load(p.read_text()), recipes)
        if errs:
            failures.append(f"{p.name} should pass but failed: {errs}")

    for p in sorted((FIXTURES / "invalid").glob("*.yaml")):
        want = expected(p)
        errs, _ = validate_spec(yaml.safe_load(p.read_text()), recipes)
        if not any(want in e for e in errs):
            failures.append(f"{p.name} should fail with '{want}' but got {errs or 'no errors'}")

    for p in sorted((FIXTURES / "bad-recipes").glob("*.yaml")):
        want = expected(p)
        errs = lint_recipe(p.stem, yaml.safe_load(p.read_text()))
        if not any(want in e for e in errs):
            failures.append(f"bad-recipes/{p.name} should fail lint with '{want}' but got {errs or 'no errors'}")

    if failures:
        print("SELF-TEST FAILED")
        for f in failures:
            print(f"  {f}")
        return 1
    n = sum(len(list((FIXTURES / d).glob("*.yaml"))) for d in ("valid", "invalid", "bad-recipes"))
    print(f"ok   self-test: catalog lint clean, {n} fixtures behaved as expected")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("validate")
    v.add_argument("files", nargs="+")
    v.add_argument("--render", action="store_true")
    lc = sub.add_parser("lint-catalog")
    lc.add_argument("dir", nargs="?", default=str(CATALOG_DIR))
    cd = sub.add_parser("catalog-doc")
    cd.add_argument("--check", action="store_true")
    sub.add_parser("self-test")
    a = ap.parse_args()

    if a.cmd == "validate":
        return cmd_validate(a.files, a.render)
    if a.cmd == "lint-catalog":
        errs = lint_catalog(Path(a.dir))
        for e in errs:
            print(f"  {e}")
        print("FAIL catalog" if errs else "ok   catalog")
        return 1 if errs else 0
    if a.cmd == "catalog-doc":
        return cmd_catalog_doc(a.check)
    return cmd_self_test()


if __name__ == "__main__":
    sys.exit(main())
