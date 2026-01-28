import argparse
import pathlib
import sys
import xml.etree.ElementTree as ET


def normalize_model_path(raw: str) -> str:
    # Strip BOM / zero-width chars that sometimes appear in Windows-edited UTF-8 lists.
    s = raw.replace("\ufeff", "").replace("\u200b", "").strip()
    if not s:
        return s

    # Common formats encountered in file lists
    # - RSN://server/Project/Folder/Model.rvt
    # - RSN:\\server\Project\Folder\Model.rvt
    # - http://server/Project/Folder/Model.rvt
    upper = s.upper()

    if upper.startswith("RSN:"):
        # Convert to canonical RSN://server/Project/Folder/Model.rvt
        # Strip leading 'RSN:' then normalize separators.
        rest = s[4:]
        rest = rest.lstrip("\\/")
        rest = rest.replace("\\", "/")
        return "RSN://" + rest

    if upper.startswith("HTTP://") or upper.startswith("HTTPS://"):
        # Revit Batch Processor does not open Revit Server models via HTTP URLs.
        # Convert to RSN://host/path if you want to attempt direct RSN opening.
        # Example: http://10.0.2.43/Likino/AR/A.rvt -> RSN://10.0.2.43/Likino/AR/A.rvt
        try:
            scheme_sep = s.index("://")
            rest = s[scheme_sep + 3 :]
            rest = rest.replace("\\", "/")
            return "RSN://" + rest
        except ValueError:
            return s

    return s


def build_config(base_config: pathlib.Path, list_file: pathlib.Path, out_config: pathlib.Path) -> None:
    tree = ET.parse(base_config)
    root = tree.getroot()

    projects = root.find("Projects")
    if projects is None:
        raise RuntimeError("Base config XML does not contain <Projects> element")

    # Clear existing project entries
    for child in list(projects):
        projects.remove(child)

    # utf-8-sig strips an optional BOM which commonly appears in Windows-saved UTF-8 files
    lines = list_file.read_text(encoding="utf-8-sig").splitlines()
    model_paths: list[str] = []
    for raw in lines:
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue

        model_path = normalize_model_path(raw)
        if not model_path:
            continue

        model_path = model_path.replace("\ufeff", "").replace("\u200b", "").strip()
        if model_path:
            model_paths.append(model_path)

    if len(model_paths) == 0:
        raise RuntimeError(f"No model paths found in list file: {list_file}")

    # Deterministic formatting for <Projects> so BatchRvtGUI users can read/edit it.
    projects.text = "\n    "
    for idx, mp in enumerate(model_paths):
        el = ET.SubElement(projects, "ProjectFile")
        el.text = mp
        el.tail = "\n    " if idx < len(model_paths) - 1 else "\n  "

    out_config.parent.mkdir(parents=True, exist_ok=True)
    tree.write(out_config, encoding="utf-8", xml_declaration=True)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate a BatchRvt configuration XML by inserting <ProjectFile> entries "
            "from a text file list. Also normalizes common RSN/HTTP path formats."
        )
    )
    parser.add_argument(
        "--base-config",
        default="purge_config.xml",
        help="Path to the base config XML (default: purge_config.xml)",
    )
    parser.add_argument(
        "--list",
        default=str(pathlib.Path("PROJECT") / "Scripts" / "revit_file_list_6.txt"),
        help="Path to the model list txt (default: PROJECT/Scripts/revit_file_list_6.txt)",
    )
    parser.add_argument(
        "--out",
        default=str(pathlib.Path("PROJECT") / "Scripts" / "purge_config_from_list.xml"),
        help="Path for output config XML (default: PROJECT/Scripts/purge_config_from_list.xml)",
    )

    args = parser.parse_args(argv)

    base = pathlib.Path(args.base_config)
    lst = pathlib.Path(args.list)
    out = pathlib.Path(args.out)

    if not base.exists():
        raise SystemExit(f"Base config not found: {base}")
    if not lst.exists():
        raise SystemExit(f"List file not found: {lst}")

    build_config(base, lst, out)
    print(f"Wrote: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
