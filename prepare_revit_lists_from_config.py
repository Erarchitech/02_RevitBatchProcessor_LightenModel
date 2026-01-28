# -*- coding: utf-8 -*-
import argparse
import json
import os
import sys
import uuid
import urllib.request


def load_config(path):
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def normalize_source_folder(folder):
    if not folder:
        return ""
    s = str(folder).strip()
    if s == "|" or s == "":
        return ""
    s = s.replace("\\", "|").replace("/", "|")
    s = s.strip("|")
    return s


def normalize_model_path(model):
    if not model:
        return ""
    s = str(model).strip()
    if not s:
        return ""
    s = s.replace("\\", "|").replace("/", "|")
    s = s.strip("|")
    return s


def join_source_and_model(source_folder, model):
    model = normalize_model_path(model)
    if not model:
        return ""
    if "|" in model:
        return model
    if source_folder:
        return source_folder + "|" + model
    return model


def rs_contents(base_url, folder):
    url = base_url + folder + "/contents"
    req = urllib.request.Request(url, method="GET")
    req.add_header("User-Name", os.environ.get("USERNAME", "BatchRvt"))
    req.add_header("User-Machine-Name", os.environ.get("COMPUTERNAME", "BatchRvt"))
    req.add_header("Operation-GUID", str(uuid.uuid4()))
    with urllib.request.urlopen(req) as resp:
        payload = resp.read().decode("utf-8")
    return json.loads(payload)


def list_rsn_models(host, version, source_folder):
    base = "http://{0}/RevitServerAdminRESTService{1}/AdminRESTService.svc/".format(host, version)
    root_folder = "|" if not source_folder else "|" + source_folder
    results = []

    def walk(folder_token):
        data = rs_contents(base, folder_token)
        for model in data.get("Models", []):
            name = model.get("Name")
            if not name:
                continue
            if folder_token == "|":
                rel = name
            else:
                rel = folder_token.strip("|") + "|" + name
            results.append(rel)
        for sub in data.get("Folders", []):
            sub_name = sub.get("Name")
            if not sub_name:
                continue
            if folder_token == "|":
                next_folder = "|" + sub_name
            else:
                next_folder = folder_token + "|" + sub_name
            walk(next_folder)

    walk(root_folder)
    return results


def rel_to_server_path(rel):
    return rel.replace("|", "\\")


def rel_to_local_path(rel, download_folder):
    parts = rel.split("|")
    return os.path.join(download_folder, *parts)


def write_list(path, lines):
    if not path:
        return
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for line in lines:
            f.write(line + "\n")


def write_env(path, values):
    if not path:
        return
    folder = os.path.dirname(path)
    if folder:
        os.makedirs(folder, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for key, value in values.items():
            if value is None:
                continue
            f.write("set {0}={1}\n".format(key, value))


def main(argv):
    parser = argparse.ArgumentParser(description="Prepare Revit model lists from JSON config.")
    parser.add_argument("--config", required=True, help="Path to config JSON.")
    parser.add_argument("--download_folder", required=True, help="Local folder for downloaded models.")
    parser.add_argument("--list", required=True, help="Output list of local RVT paths.")
    parser.add_argument("--download_list", required=True, help="Output list of RS paths and local paths.")
    parser.add_argument("--env", default="", help="Output .cmd file with environment variables.")
    args = parser.parse_args(argv)

    cfg = load_config(args.config)
    rs_host = cfg.get("RS_HOST", "")
    rs_ver = str(cfg.get("RS_VER", "")).strip()
    source_folder = normalize_source_folder(cfg.get("source_folder", ""))
    output_folder = cfg.get("output_folder", "")
    download_folder = cfg.get("download_folder", args.download_folder)

    models = cfg.get("models", [])
    if not isinstance(models, list):
        models = []

    rel_models = []
    if models:
        for model in models:
            rel = join_source_and_model(source_folder, model)
            if rel:
                rel_models.append(rel)
    elif rs_host and rs_ver:
        try:
            rel_models = list_rsn_models(rs_host, rs_ver, source_folder)
        except Exception as exc:
            print("ERROR: Revit Server listing failed: {0}".format(exc))
            rel_models = []

    if not rel_models:
        print("ERROR: no models resolved from config")
        write_list(args.list, [])
        write_list(args.download_list, [])
        write_env(args.env, {
            "RS_HOST": rs_host,
            "RS_VER": rs_ver,
            "RS_SOURCE_FOLDER": source_folder,
            "DOWNLOAD_FOLDER": download_folder,
            "RBP_OUTPUT": output_folder,
        })
        return 2

    local_list = []
    download_list = []
    for rel in rel_models:
        server_path = rel_to_server_path(rel)
        local_path = rel_to_local_path(rel, download_folder)
        local_list.append(local_path)
        download_list.append(server_path + "|" + local_path)

    write_list(args.list, local_list)
    write_list(args.download_list, download_list)
    write_env(args.env, {
        "RS_HOST": rs_host,
        "RS_VER": rs_ver,
        "RS_SOURCE_FOLDER": source_folder,
        "DOWNLOAD_FOLDER": download_folder,
        "RBP_OUTPUT": output_folder,
    })

    print("Models resolved: {0}".format(len(local_list)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
