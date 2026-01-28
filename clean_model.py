# -*- coding: utf-8 -*-

import clr
import System
import os
import json
clr.AddReference("System.Core")
clr.ImportExtensions(System.Linq)

clr.AddReference("RevitAPI")
clr.AddReference("RevitAPIUI")
from Autodesk.Revit.DB import *
from System.Collections.Generic import List
from System import Guid

import revit_script_util
from revit_script_util import Output

sessionId = revit_script_util.GetSessionId()
uiapp = revit_script_util.GetUIApplication()
doc = revit_script_util.GetScriptDocument()
revitFilePath = revit_script_util.GetRevitFilePath()
sessionDataFolderPath = revit_script_util.GetSessionDataFolderPath()
dataExportFolderPath = revit_script_util.GetDataExportFolderPath()

# Optional JSON config path supplied by the batch file.
CONFIG_PATH = System.Environment.GetEnvironmentVariable("CLEAN_CONFIG")
CONFIG = {}
if CONFIG_PATH and System.IO.File.Exists(CONFIG_PATH):
    try:
        CONFIG = json.loads(System.IO.File.ReadAllText(CONFIG_PATH))
        Output("CONFIG: {0}".format(CONFIG_PATH))
    except Exception as e:
        Output("CONFIG load failed: {0}".format(e))

# Feature toggles (defaults).
PURGE_UNUSED = True
DELETE_SHEETS = True
DELETE_IMPORTS = True
DELETE_LINKS = True
COMPACT_ON_SAVE = True

if CONFIG:
    PURGE_UNUSED = bool(CONFIG.get("purge_unused", PURGE_UNUSED))
    DELETE_SHEETS = bool(CONFIG.get("delete_sheets", DELETE_SHEETS))
    DELETE_IMPORTS = bool(CONFIG.get("delete_imports", DELETE_IMPORTS))
    DELETE_LINKS = bool(CONFIG.get("delete_links", DELETE_LINKS))
    COMPACT_ON_SAVE = bool(CONFIG.get("compact_on_save", COMPACT_ON_SAVE))

# Define a target folder for the saved model.
# Leave empty to fall back to BatchRvt paths or the source file directory.
CUSTOM_OUTPUT_FOLDER = System.Environment.GetEnvironmentVariable("RBP_OUTPUT")
if (not CUSTOM_OUTPUT_FOLDER or not CUSTOM_OUTPUT_FOLDER.strip()) and CONFIG.get("output_folder"):
    CUSTOM_OUTPUT_FOLDER = CONFIG.get("output_folder")
if CUSTOM_OUTPUT_FOLDER and CUSTOM_OUTPUT_FOLDER.strip():
    Output("CUSTOM_OUTPUT_FOLDER: {0}".format(CUSTOM_OUTPUT_FOLDER))
TYPE_PURGE_RULES = [
    ("wall types", WallType, BuiltInCategory.OST_Walls),
    ("floor types", FloorType, BuiltInCategory.OST_Floors),
    ("roof types", RoofType, BuiltInCategory.OST_Roofs),
    ("ceiling types", CeilingType, BuiltInCategory.OST_Ceilings),
    ("text note types", TextNoteType, BuiltInCategory.OST_TextNotes),
    ("dimension types", DimensionType, BuiltInCategory.OST_Dimensions),
    ("filled region types", FilledRegionType, BuiltInCategory.OST_FilledRegion),
    ("detail line types", ElementType, BuiltInCategory.OST_Lines),
]


def _is_valid(element):
    try:
        return element is not None and element.IsValidObject
    except:
        return False


def _get_class(name):
    return globals().get(name, None)


def _count_collection(items):
    if items is None:
        return 0
    try:
        return items.Count
    except:
        try:
            return len(items)
        except:
            return 0


def _delete_by_class(doc, class_name, label):
    cls = _get_class(class_name)
    if cls is None:
        return 0
    deleted = 0
    elems = list(FilteredElementCollector(doc).OfClass(cls))
    for elem in elems:
        if not _is_valid(elem):
            continue
        try:
            doc.Delete(elem.Id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed {0}: {1}".format(label, deleted))
    return deleted

def _get_target_folder():
    if CUSTOM_OUTPUT_FOLDER and CUSTOM_OUTPUT_FOLDER.strip():
        return CUSTOM_OUTPUT_FOLDER

    for candidate in (dataExportFolderPath, sessionDataFolderPath):
        if candidate and candidate.strip():
            return candidate

    if revitFilePath and revitFilePath.strip():
        base_dir = System.IO.Path.GetDirectoryName(revitFilePath)
        if base_dir:
            return System.IO.Path.Combine(base_dir, "BatchRvt_Clean")

    desktop = System.Environment.GetFolderPath(System.Environment.SpecialFolder.DesktopDirectory)
    return System.IO.Path.Combine(desktop, "BatchRvt_Clean")


def _ensure_directory(path):
    if not System.IO.Directory.Exists(path):
        System.IO.Directory.CreateDirectory(path)


def _build_target_path(folder):
    file_name = None
    if revitFilePath and revitFilePath.strip():
        file_name = System.IO.Path.GetFileName(revitFilePath)
    if not file_name:
        file_name = doc.Title if doc and doc.Title else "BatchModel.rvt"
        if not file_name.lower().endswith(".rvt"):
            file_name = file_name + ".rvt"
    return System.IO.Path.Combine(folder, file_name)


def _save_as_central(target_path):
    save_opts = SaveAsOptions()
    save_opts.OverwriteExistingFile = True
    save_opts.MaximumBackups = 1
    save_opts.Compact = COMPACT_ON_SAVE

    if doc.IsWorkshared:
        ws_opts = WorksharingSaveAsOptions()
        try:
            # Revit 2021+ exposes MakeCentral, older versions rely on SaveAsCentral.
            ws_opts.MakeCentral = True
        except AttributeError:
            ws_opts.SaveAsCentral = True
        save_opts.SetWorksharingOptions(ws_opts)
    else:
        Output("Warning: model is not workshared, saving as a regular file.")

    doc.SaveAs(target_path, save_opts)

def delete_revit_links(doc):
    deleted = 0
    deleted += _delete_by_class(doc, "RevitLinkInstance", "Revit link instances")
    deleted += _delete_by_class(doc, "RevitLinkType", "Revit link types")
    deleted += _delete_by_class(doc, "CoordinationModel", "Coordination models")
    deleted += _delete_by_class(doc, "PointCloudInstance", "Point clouds")
    deleted += _delete_by_class(doc, "PointCloudType", "Point cloud types")
    deleted += _delete_by_class(doc, "ImageType", "Raster images")
    deleted += _delete_by_class(doc, "DecalType", "Decals")
    if deleted == 0:
        Output("Removed Revit links: 0")


def delete_imported_content(doc):
    deleted = 0
    deleted += _delete_by_class(doc, "ImportInstance", "Imported CAD instances")
    deleted += _delete_by_class(doc, "CADLinkType", "CAD link types")
    return deleted

def delete_sheets(doc):
    deleted = 0
    sheets = list(FilteredElementCollector(doc).OfClass(ViewSheet))
    for sheet in sheets:
        if not _is_valid(sheet):
            continue
        try:
            doc.Delete(sheet.Id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed sheets: {0}".format(deleted))
    return deleted

def _collect_used_family_symbol_ids(doc):
    used_ids = set()
    instances = FilteredElementCollector(doc).OfClass(FamilyInstance).WhereElementIsNotElementType()
    for inst in instances:
        if not _is_valid(inst):
            continue
        try:
            type_id = inst.GetTypeId()
            if type_id != ElementId.InvalidElementId:
                used_ids.add(type_id)
        except:
            pass
    return used_ids


def _collect_used_type_ids_by_category(doc, bic):
    used_ids = set()
    collector = FilteredElementCollector(doc).OfCategory(bic).WhereElementIsNotElementType()
    for elem in collector:
        if not _is_valid(elem):
            continue
        try:
            type_id = elem.GetTypeId()
            if type_id != ElementId.InvalidElementId:
                used_ids.add(type_id)
        except:
            pass
    return used_ids


def _collect_all_used_type_ids(doc):
    used_ids = set()
    collector = FilteredElementCollector(doc).WhereElementIsNotElementType()
    for elem in collector:
        if not _is_valid(elem):
            continue
        try:
            type_id = elem.GetTypeId()
            if type_id != ElementId.InvalidElementId:
                used_ids.add(type_id)
        except:
            pass
    return used_ids


def _purge_unused_family_symbols(doc):
    used_ids = _collect_used_family_symbol_ids(doc)
    deleted = 0
    symbols = list(FilteredElementCollector(doc).OfClass(FamilySymbol))
    for sym in symbols:
        if not _is_valid(sym):
            continue
        if sym.Id in used_ids:
            continue
        try:
            doc.Delete(sym.Id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed unused family symbols: {0}".format(deleted))
    return deleted


def _purge_unused_types_for_category(doc, label, type_class, bic):
    category = Category.GetCategory(doc, bic)
    if category is None:
        return 0
    target_cat_id = category.Id
    used_ids = _collect_used_type_ids_by_category(doc, bic)
    deleted = 0
    types = list(FilteredElementCollector(doc).OfClass(type_class))
    for elem_type in types:
        if not _is_valid(elem_type):
            continue
        type_cat = elem_type.Category
        if type_cat is None or type_cat.Id != target_cat_id:
            continue
        if elem_type.Id in used_ids:
            continue
        try:
            doc.Delete(elem_type.Id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed unused {0}: {1}".format(label, deleted))
    return deleted


def _purge_unused_materials(doc):
    materials = list(FilteredElementCollector(doc).OfClass(Material))
    deleted = 0
    for mat in materials:
        if not _is_valid(mat):
            continue
        try:
            doc.Delete(mat.Id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed unused materials: {0}".format(deleted))
    return deleted


def _purge_unused_general_types(doc):
    used_ids = _collect_all_used_type_ids(doc)
    deleted = 0
    element_types = list(FilteredElementCollector(doc).WhereElementIsElementType())
    for elem_type in element_types:
        if not _is_valid(elem_type):
            continue
        elem_id = elem_type.Id
        if elem_id == ElementId.InvalidElementId or elem_id in used_ids:
            continue
        try:
            doc.Delete(elem_id)
            deleted += 1
        except:
            pass
    if deleted > 0:
        Output("Removed unused element types: {0}".format(deleted))
    return deleted


def _purge_unused_via_performance_adviser(doc):
    purge_guid = Guid("e8c63650-70b7-435a-9010-ec97660c1bda")
    rule_id = None
    for rule in PerformanceAdviser.GetPerformanceAdviser().GetAllRuleIds():
        if rule.Guid.Equals(purge_guid):
            rule_id = rule
            break

    if rule_id is None:
        Output("Purge rule not found; falling back to manual purge.")
        return None

    total_deleted = 0
    max_passes = 20
    for pass_index in range(1, max_passes + 1):
        try:
            rule_ids = List[PerformanceAdviserRuleId]()
            rule_ids.Add(rule_id)
            failure_messages = PerformanceAdviser.GetPerformanceAdviser().ExecuteRules(doc, rule_ids)
            if failure_messages is None or failure_messages.Count == 0:
                break
            purgeable_ids = failure_messages[0].GetFailingElements()
            if purgeable_ids is None or purgeable_ids.Count == 0:
                break
            t = Transaction(doc, "Purge unused elements")
            try:
                t.Start()
                deleted_ids = doc.Delete(purgeable_ids)
                t.Commit()
            except Exception as ex:
                if t.HasStarted():
                    t.RollBack()
                Output("PurgeUnused (PerformanceAdviser) failed: {0}".format(ex))
                break
            removed_count = _count_collection(deleted_ids)
            total_deleted += removed_count
            if removed_count == 0:
                break
        except Exception as ex:
            Output("PurgeUnused (PerformanceAdviser) failed: {0}".format(ex))
            break

    Output("Purge via PerformanceAdviser removed: {0}".format(total_deleted))
    return total_deleted


def _purge_unused_manual(doc):
    total_deleted = 0
    max_passes = 20
    for pass_index in range(1, max_passes + 1):
        deleted_this_pass = 0
        t = Transaction(doc, "Purge unused elements (manual)")
        try:
            t.Start()
            deleted_this_pass += _purge_unused_family_symbols(doc)
            deleted_this_pass += _purge_unused_general_types(doc)
            for label, type_class, bic in TYPE_PURGE_RULES:
                deleted_this_pass += _purge_unused_types_for_category(doc, label, type_class, bic)
            deleted_this_pass += _purge_unused_materials(doc)
            t.Commit()
        except Exception as ex:
            if t.HasStarted():
                t.RollBack()
            Output("Manual purge failed: {0}".format(ex))
            break

        if deleted_this_pass == 0:
            Output("Unused elements purge finished. Total removed: {0} in {1} passes.".format(total_deleted, pass_index if total_deleted > 0 else 1))
            return total_deleted

        total_deleted += deleted_this_pass

    Output("Unused elements purge finished. Total removed: {0} in {1} passes (max reached).".format(total_deleted, max_passes))
    return total_deleted


def purge_unused_families(doc):
    result = _purge_unused_via_performance_adviser(doc)
    if result is None:
        return _purge_unused_manual(doc)
    return result


def main():
    try:
        Output("Script started")
        if doc is None:
            Output("Document handle is empty")
            return

        Output("Current file: {0}".format(revitFilePath))

        if DELETE_LINKS or DELETE_IMPORTS or DELETE_SHEETS:
            t = Transaction(doc, "Remove links/imports/sheets")
            try:
                t.Start()
                if DELETE_LINKS:
                    delete_revit_links(doc)
                if DELETE_IMPORTS:
                    delete_imported_content(doc)
                if DELETE_SHEETS:
                    delete_sheets(doc)
                t.Commit()
            except Exception:
                if t.HasStarted():
                    t.RollBack()
                raise

        if PURGE_UNUSED:
            purge_unused_families(doc)

        target_folder = _get_target_folder()
        _ensure_directory(target_folder)
        target_path = _build_target_path(target_folder)
        Output("Saving model to: {0}".format(target_path))
        _save_as_central(target_path)

        Output("Script finished successfully")
    except Exception as e:
        Output("Script error: {0}".format(e))


main()