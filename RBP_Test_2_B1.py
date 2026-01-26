# -*- coding: utf-8 -*-

import clr
import System
clr.AddReference("System.Core")
clr.ImportExtensions(System.Linq)

clr.AddReference("RevitAPI")
clr.AddReference("RevitAPIUI")
from Autodesk.Revit.DB import *

import revit_script_util
from revit_script_util import Output

sessionId = revit_script_util.GetSessionId()
uiapp = revit_script_util.GetUIApplication()
doc = revit_script_util.GetScriptDocument()
revitFilePath = revit_script_util.GetRevitFilePath()
sessionDataFolderPath = revit_script_util.GetSessionDataFolderPath()
dataExportFolderPath = revit_script_util.GetDataExportFolderPath()

# Define a target folder for the saved model.
# Leave empty to fall back to BatchRvt paths or the source file directory.
CUSTOM_OUTPUT_FOLDER = System.Environment.GetEnvironmentVariable("RBP_OUTPUT")
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
    collector = FilteredElementCollector(doc).OfClass(RevitLinkType)
    links = list(collector)
    count = 0
    for lt in links:
        if not _is_valid(lt):
            continue
        try:
            doc.Delete(lt.Id)
            count += 1
        except:
            pass
    Output("Removed Revit links: {0}".format(count))


def delete_imported_content(doc):
    deleted = 0
    imports = list(FilteredElementCollector(doc).OfClass(ImportInstance))
    for inst in imports:
        if not _is_valid(inst):
            continue
        try:
            doc.Delete(inst.Id)
            deleted += 1
        except:
            pass

    cad_types = list(FilteredElementCollector(doc).OfClass(CADLinkType))
    for cad in cad_types:
        if not _is_valid(cad):
            continue
        try:
            doc.Delete(cad.Id)
            deleted += 1
        except:
            pass

    if deleted > 0:
        Output("Removed imported CAD content: {0}".format(deleted))
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


def purge_unused_families(doc):
    total_deleted = 0
    max_passes = 10

    for pass_index in range(1, max_passes + 1):
        deleted_this_pass = 0
        deleted_this_pass += _purge_unused_family_symbols(doc)
        deleted_this_pass += _purge_unused_general_types(doc)
        for label, type_class, bic in TYPE_PURGE_RULES:
            deleted_this_pass += _purge_unused_types_for_category(doc, label, type_class, bic)
        deleted_this_pass += _purge_unused_materials(doc)

        if deleted_this_pass == 0:
            Output("Unused elements purge finished. Total removed: {0} in {1} passes.".format(total_deleted, pass_index if total_deleted > 0 else 1))
            return

        total_deleted += deleted_this_pass

    Output("Unused elements purge finished. Total removed: {0} in {1} passes (max reached).".format(total_deleted, max_passes))


def main():
    try:
        Output("Script started")
        if doc is None:
            Output("Document handle is empty")
            return

        Output("Current file: {0}".format(revitFilePath))

        t = Transaction(doc, "Model cleanup")
        try:
            t.Start()
            delete_revit_links(doc)
            delete_imported_content(doc)
            delete_sheets(doc)
            purge_unused_families(doc)
            t.Commit()
        except Exception:
            if t.HasStarted():
                t.RollBack()
            raise

        target_folder = _get_target_folder()
        _ensure_directory(target_folder)
        target_path = _build_target_path(target_folder)
        Output("Saving model to: {0}".format(target_path))
        _save_as_central(target_path)

        Output("Script finished successfully")
    except Exception as e:
        Output("Script error: {0}".format(e))


main()