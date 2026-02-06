# -*- coding: utf-8 -*-
"""
Revit Model Cleaner Script for BatchRvt
Version: 4.0 - Enhanced dialog suppression for Revit 2022-2024
"""

import clr
import System
import os
import json
import time
import threading

clr.AddReference("System.Core")
clr.ImportExtensions(System.Linq)
clr.AddReference("RevitAPI")
clr.AddReference("RevitAPIUI")

from Autodesk.Revit.DB import *
from Autodesk.Revit.DB.Events import *
from Autodesk.Revit.UI import *
from Autodesk.Revit.UI.Events import *
from System.Collections.Generic import List
from System import Guid

# Win32 API для закрытия системных диалогов
try:
    clr.AddReference("System.Windows.Forms")
    clr.AddReference("System.Runtime.InteropServices")
    from System.Runtime.InteropServices import DllImport, Marshal
    from System.Windows.Forms import SendKeys
    import ctypes
    HAS_WIN32 = True
except:
    HAS_WIN32 = False

# Navisworks Export
try:
    from Autodesk.Revit.DB import NavisworksExportOptions, NavisworksExportScope, NavisworksCoordinates
    HAS_NAVISWORKS_EXPORT = True
except ImportError:
    HAS_NAVISWORKS_EXPORT = False

import revit_script_util
from revit_script_util import Output

# ============================================================================
# WIN32 API ДЛЯ ЗАКРЫТИЯ СИСТЕМНЫХ ДИАЛОГОВ
# ============================================================================

if HAS_WIN32:
    try:
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        
        # Константы Win32
        WM_CLOSE = 0x0010
        WM_COMMAND = 0x0111
        BM_CLICK = 0x00F5
        IDOK = 1
        IDCANCEL = 2
        IDYES = 6
        IDNO = 7
        GW_CHILD = 5
        
        EnumWindows = user32.EnumWindows
        EnumChildWindows = user32.EnumChildWindows
        GetWindowTextW = user32.GetWindowTextW
        GetClassNameW = user32.GetClassNameW
        GetWindowThreadProcessId = user32.GetWindowThreadProcessId
        SendMessageW = user32.SendMessageW
        PostMessageW = user32.PostMessageW
        IsWindowVisible = user32.IsWindowVisible
        FindWindowExW = user32.FindWindowExW
        GetCurrentProcessId = kernel32.GetCurrentProcessId
        
        WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int))
        
        WIN32_AVAILABLE = True
    except Exception as e:
        WIN32_AVAILABLE = False
        Output("Win32 API init failed: {0}".format(e))
else:
    WIN32_AVAILABLE = False


class Win32DialogKiller:
    """Фоновый поток для закрытия системных диалогов Windows"""
    
    # Заголовки диалогов для автозакрытия (частичное совпадение)
    DIALOG_TITLES = [
        "Autodesk Revit",
        "Warning",
        "Предупреждение",
        "Error",
        "Ошибка",
        "Units",
        "Единицы",
        "Scale",
        "Масштаб",
        "Missing",
        "Отсутствует",
        "Worksets",
        "Рабочие наборы",
        "Updating",
        "Обновление",
        "Loading",
        "Загрузка",
        "Audit",
        "Аудит",
        "Compact",
        "Сжатие",
        "Save",
        "Сохранение",
        "Specify",
        "Укажите",
        "Information",
        "Информация",
        "Notification",
        "Уведомление",
    ]
    
    # Классы окон диалогов
    DIALOG_CLASSES = [
        "#32770",  # Стандартный диалог Windows
        "TaskDialog",
        "Button",
    ]
    
    def __init__(self):
        self._running = False
        self._thread = None
        self._closed_count = 0
        self._process_id = None
        self._lock = threading.Lock()
    
    def start(self):
        """Запустить фоновый поток"""
        if not WIN32_AVAILABLE:
            Output("Win32 dialog killer: NOT AVAILABLE")
            return
        
        if self._running:
            return
        
        self._running = True
        self._process_id = GetCurrentProcessId()
        self._thread = threading.Thread(target=self._monitor_loop)
        self._thread.daemon = True
        self._thread.start()
        Output("Win32 dialog killer: STARTED (PID: {0})".format(self._process_id))
    
    def stop(self):
        """Остановить фоновый поток"""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
        Output("Win32 dialog killer: STOPPED (closed: {0})".format(self._closed_count))
    
    def _monitor_loop(self):
        """Основной цикл мониторинга"""
        while self._running:
            try:
                self._find_and_close_dialogs()
            except:
                pass
            time.sleep(0.3)  # Проверка каждые 300мс
    
    def _find_and_close_dialogs(self):
        """Найти и закрыть диалоговые окна"""
        if not self._process_id:
            return
        
        dialogs_to_close = []
        
        def enum_callback(hwnd, lparam):
            try:
                # Проверяем что окно видимо
                if not IsWindowVisible(hwnd):
                    return True
                
                # Проверяем что окно принадлежит нашему процессу
                pid = ctypes.c_ulong()
                GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                if pid.value != self._process_id:
                    return True
                
                # Получаем заголовок окна
                title_buf = ctypes.create_unicode_buffer(256)
                GetWindowTextW(hwnd, title_buf, 256)
                title = title_buf.value
                
                # Получаем класс окна
                class_buf = ctypes.create_unicode_buffer(256)
                GetClassNameW(hwnd, class_buf, 256)
                class_name = class_buf.value
                
                # Проверяем класс окна
                is_dialog_class = any(dc in class_name for dc in self.DIALOG_CLASSES)
                
                # Проверяем заголовок
                title_lower = title.lower() if title else ""
                is_dialog_title = any(dt.lower() in title_lower for dt in self.DIALOG_TITLES)
                
                if is_dialog_class and (is_dialog_title or not title):
                    dialogs_to_close.append((hwnd, title, class_name))
                
            except:
                pass
            return True
        
        # Перечисляем окна
        callback = WNDENUMPROC(enum_callback)
        EnumWindows(callback, None)
        
        # Закрываем найденные диалоги
        for hwnd, title, class_name in dialogs_to_close:
            self._close_dialog(hwnd, title)
    
    def _close_dialog(self, hwnd, title):
        """Закрыть диалоговое окно"""
        try:
            # Пробуем найти кнопки OK, Yes, Continue
            button_ids = [IDOK, IDYES, 1001, 1002]  # OK, Yes, и другие
            
            for btn_id in button_ids:
                try:
                    # Отправляем команду нажатия кнопки
                    result = SendMessageW(hwnd, WM_COMMAND, btn_id, 0)
                    if result == 0:
                        with self._lock:
                            self._closed_count += 1
                        Output("  [WIN32] Closed: {0}".format(title[:50] if title else "Unknown"))
                        return True
                except:
                    pass
            
            # Если не удалось - отправляем WM_CLOSE
            PostMessageW(hwnd, WM_CLOSE, 0, 0)
            with self._lock:
                self._closed_count += 1
            Output("  [WIN32] Force closed: {0}".format(title[:50] if title else "Unknown"))
            return True
            
        except:
            return False
    
    def get_closed_count(self):
        with self._lock:
            return self._closed_count


# ============================================================================
# РАСШИРЕННЫЙ ПОДАВИТЕЛЬ ДИАЛОГОВ REVIT API
# ============================================================================

class EnhancedDialogSuppressor:
    """Улучшенный перехватчик диалогов Revit с поддержкой 2024"""
    
    def __init__(self, uiapp):
        self.uiapp = uiapp
        self.app = uiapp.Application if uiapp else None
        self.suppressed_count = 0
        self.suppressed_dialogs = []
        self._attached = False
    
    def attach(self):
        """Подключить все обработчики"""
        if self._attached:
            return
        
        try:
            # 1. DialogBoxShowing - основной обработчик UI диалогов
            self.uiapp.DialogBoxShowing += self._on_dialog
            Output("  DialogBoxShowing: attached")
        except Exception as e:
            Output("  DialogBoxShowing failed: {0}".format(e))
        
        try:
            # 2. FailuresProcessing - обработка ошибок и предупреждений
            self.app.FailuresProcessing += self._on_failures
            Output("  FailuresProcessing: attached")
        except Exception as e:
            Output("  FailuresProcessing failed: {0}".format(e))
        
        try:
            # 3. DocumentOpening - диалоги при открытии
            self.app.DocumentOpening += self._on_doc_opening
            Output("  DocumentOpening: attached")
        except Exception as e:
            Output("  DocumentOpening failed: {0}".format(e))
        
        self._attached = True
        Output("Enhanced dialog suppressor: ATTACHED")
    
    def detach(self):
        """Отключить все обработчики"""
        if not self._attached:
            return
        
        try:
            self.uiapp.DialogBoxShowing -= self._on_dialog
        except:
            pass
        
        try:
            self.app.FailuresProcessing -= self._on_failures
        except:
            pass
        
        try:
            self.app.DocumentOpening -= self._on_doc_opening
        except:
            pass
        
        self._attached = False
        Output("Enhanced dialog suppressor: DETACHED")
    
    def _on_doc_opening(self, sender, args):
        """Обработчик открытия документа"""
        try:
            # Можно настроить параметры открытия
            Output("  [DOC_OPENING] Document opening event")
        except:
            pass
    
    def _on_failures(self, sender, args):
        """Обработчик FailuresProcessing на уровне Application"""
        try:
            accessor = args.GetFailuresAccessor()
            failures = accessor.GetFailureMessages()
            
            processed = 0
            for failure in failures:
                try:
                    severity = failure.GetSeverity()
                    desc = ""
                    try:
                        desc = failure.GetDescriptionText()[:50]
                    except:
                        pass
                    
                    if severity == FailureSeverity.Warning:
                        accessor.DeleteWarning(failure)
                        processed += 1
                        Output("  [FAILURE] Warning deleted: {0}".format(desc))
                        
                    elif severity == FailureSeverity.Error:
                        if failure.HasResolutions():
                            # Пробуем автоматическое разрешение
                            try:
                                accessor.ResolveFailure(failure)
                                processed += 1
                                Output("  [FAILURE] Error resolved: {0}".format(desc))
                            except:
                                # Если не удалось - удаляем элементы
                                try:
                                    ids = failure.GetFailingElementIds()
                                    if ids and ids.Count > 0:
                                        accessor.DeleteElements(ids)
                                        processed += 1
                                except:
                                    pass
                        else:
                            # Удаляем проблемные элементы
                            try:
                                ids = failure.GetFailingElementIds()
                                if ids and ids.Count > 0:
                                    accessor.DeleteElements(ids)
                                    processed += 1
                            except:
                                pass
                except:
                    pass
            
            if processed > 0:
                self.suppressed_count += processed
                args.SetProcessingResult(FailureProcessingResult.Continue)
            
        except Exception as e:
            Output("  [FAILURE ERROR] {0}".format(e))
    
    def _on_dialog(self, sender, args):
        """Обработчик диалоговых окон UI"""
        try:
            dialog_id = ""
            help_id = 0
            
            if hasattr(args, 'DialogId'):
                dialog_id = str(args.DialogId)
            if hasattr(args, 'HelpId'):
                try:
                    help_id = args.HelpId
                except:
                    pass
            
            self.suppressed_dialogs.append(dialog_id)
            self.suppressed_count += 1
            
            dialog_lower = dialog_id.lower() if dialog_id else ""
            
            # TaskDialog - используем OverrideResult
            if hasattr(args, 'OverrideResult'):
                
                # === КРИТИЧНО: Диалоги сохранения ===
                if "save" in dialog_lower:
                    if "central" in dialog_lower or "workset" in dialog_lower:
                        args.OverrideResult(6)  # Yes
                        Output("  [DIALOG] Save Central: YES")
                    elif "overwrite" in dialog_lower:
                        args.OverrideResult(6)  # Yes
                        Output("  [DIALOG] Overwrite: YES")
                    else:
                        args.OverrideResult(1001)
                        Output("  [DIALOG] Save: OK")
                    return
                
                # === Единицы измерения ===
                if "unit" in dialog_lower or "единиц" in dialog_lower:
                    args.OverrideResult(1001)  # OK / Continue
                    Output("  [DIALOG] Units: OK")
                    return
                
                # === Масштаб ===
                if "scale" in dialog_lower or "масштаб" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Scale: OK")
                    return
                
                # === Предупреждения ===
                if any(w in dialog_lower for w in ["warning", "предупрежден", "updater", "обновл"]):
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Warning: OK")
                    return
                
                # === Отсутствующие элементы ===
                if any(m in dialog_lower for m in ["missing", "not installed", "not found", "отсутств", "не найден"]):
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Missing: OK")
                    return
                
                # === Рабочие наборы ===
                if "workset" in dialog_lower or "рабоч" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Workset: OK")
                    return
                
                # === Аудит ===
                if "audit" in dialog_lower or "аудит" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Audit: OK")
                    return
                
                # === Сжатие / Compact ===
                if "compact" in dialog_lower or "сжат" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Compact: OK")
                    return
                
                # === Загрузка семейств ===
                if "family" in dialog_lower or "семейств" in dialog_lower or "load" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Family: OK")
                    return
                
                # === Координаты ===
                if "coordinate" in dialog_lower or "координат" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Coordinates: OK")
                    return
                
                # === Связи ===
                if "link" in dialog_lower or "связ" in dialog_lower:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Link: OK")
                    return
                
                # === Информационные ===
                if any(i in dialog_lower for i in ["info", "information", "информац", "notification", "уведомлен"]):
                    args.OverrideResult(1001)
                    Output("  [DIALOG] Info: OK")
                    return
                
                # === По HelpId для известных диалогов ===
                # Revit использует HelpId для идентификации некоторых диалогов
                known_help_ids = {
                    # Добавьте сюда известные HelpId если найдёте
                }
                if help_id in known_help_ids:
                    args.OverrideResult(1001)
                    Output("  [DIALOG] HelpId {0}: OK".format(help_id))
                    return
                
                # === По умолчанию - OK/Continue ===
                args.OverrideResult(1001)
                Output("  [DIALOG SUPPRESSED] {0}".format(dialog_id[:60] if dialog_id else "unknown"))
            
            # MessageBox - используем OverrideResult для кнопок
            elif hasattr(args, 'Handled'):
                args.Handled = True
                Output("  [MSGBOX SUPPRESSED] {0}".format(dialog_id[:60] if dialog_id else "unknown"))
            
        except Exception as e:
            Output("  [DIALOG ERROR] {0}".format(e))
    
    def get_summary(self):
        return {
            "count": self.suppressed_count,
            "dialogs": list(set(self.suppressed_dialogs))
        }


class FailureSwallower(IFailuresPreprocessor):
    """Обработчик ошибок для транзакций"""
    
    def __init__(self):
        self.failures_count = 0
        self.warnings_count = 0
    
    def PreprocessFailures(self, failuresAccessor):
        try:
            failures = failuresAccessor.GetFailureMessages()
            
            for failure in failures:
                severity = failure.GetSeverity()
                
                if severity == FailureSeverity.Warning:
                    failuresAccessor.DeleteWarning(failure)
                    self.warnings_count += 1
                    
                elif severity == FailureSeverity.Error:
                    if failure.HasResolutions():
                        failuresAccessor.ResolveFailure(failure)
                        self.failures_count += 1
                    else:
                        try:
                            ids = failure.GetFailingElementIds()
                            if ids and ids.Count > 0:
                                failuresAccessor.DeleteElements(ids)
                        except:
                            pass
                        self.failures_count += 1
            
            return FailureProcessingResult.Continue
            
        except:
            return FailureProcessingResult.Continue


def create_silent_transaction(doc, name):
    """Создать транзакцию с подавлением предупреждений"""
    t = Transaction(doc, name)
    options = t.GetFailureHandlingOptions()
    options.SetFailuresPreprocessor(FailureSwallower())
    options.SetClearAfterRollback(True)
    t.SetFailureHandlingOptions(options)
    return t


# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================

sessionId = revit_script_util.GetSessionId()
uiapp = revit_script_util.GetUIApplication()
doc = revit_script_util.GetScriptDocument()
revitFilePath = revit_script_util.GetRevitFilePath()
sessionDataFolderPath = revit_script_util.GetSessionDataFolderPath()
dataExportFolderPath = revit_script_util.GetDataExportFolderPath()

# ============================================================================
# ЗАГРУЗКА КОНФИГУРАЦИИ
# ============================================================================

CONFIG_PATH = System.Environment.GetEnvironmentVariable("CLEAN_CONFIG")
CONFIG = {}

if CONFIG_PATH and System.IO.File.Exists(CONFIG_PATH):
    try:
        CONFIG = json.loads(System.IO.File.ReadAllText(CONFIG_PATH))
        Output("CONFIG: {0}".format(CONFIG_PATH))
    except Exception as e:
        Output("CONFIG ERROR: {0}".format(e))


def get_opt(key, default):
    if CONFIG:
        opts = CONFIG.get("cleaning_options", {})
        if key in opts:
            return opts[key]
        if key in CONFIG:
            return CONFIG[key]
    return default


PURGE_UNUSED = bool(get_opt("purge_unused", True))
DELETE_SHEETS = bool(get_opt("delete_sheets", True))
DELETE_IMPORTS = bool(get_opt("delete_imports", True))
DELETE_LINKS = bool(get_opt("delete_links", True))
DELETE_VIEWS = bool(get_opt("delete_views", False))
COMPACT_ON_SAVE = bool(get_opt("compact_on_save", True))
DRY_RUN = bool(get_opt("dry_run", False))
VIEWS_TO_KEEP = get_opt("delete_views_except", ["{3D}", "3D"])
SUPPRESS_DIALOGS = bool(get_opt("suppress_dialogs", True))

EXPORT_NWC = bool(get_opt("export_nwc", False))
NWC_FOLDER = get_opt("nwc_folder", "")
NWC_COORDINATES = get_opt("nwc_coordinates", "shared")
NWC_DIVIDE_BY_LEVEL = bool(get_opt("nwc_divide_by_level", True))
NWC_CONVERT_IDS = bool(get_opt("nwc_convert_ids", True))
NWC_CONVERT_LINKS = bool(get_opt("nwc_convert_links", False))

OUTPUT_FOLDER = System.Environment.GetEnvironmentVariable("RBP_OUTPUT")
if not OUTPUT_FOLDER:
    OUTPUT_FOLDER = CONFIG.get("output_folder", "")

if DRY_RUN:
    Output("*** DRY-RUN MODE ***")


# ============================================================================
# СТАТИСТИКА
# ============================================================================

class Stats:
    def __init__(self):
        self.links = 0
        self.imports = 0
        self.sheets = 0
        self.views = 0
        self.purged = 0
        self.errors = []
        self.start = time.time()
    
    def error(self, msg):
        self.errors.append(msg)
        Output("ERROR: {0}".format(msg))
    
    def elapsed(self):
        return time.time() - self.start
    
    def summary(self):
        Output("")
        Output("=" * 50)
        Output("SUMMARY")
        Output("=" * 50)
        Output("Links: {0}".format(self.links))
        Output("Imports: {0}".format(self.imports))
        Output("Sheets: {0}".format(self.sheets))
        Output("Views: {0}".format(self.views))
        Output("Purged: {0}".format(self.purged))
        Output("Errors: {0}".format(len(self.errors)))
        Output("Time: {0:.1f}s".format(self.elapsed()))
        Output("=" * 50)


STATS = Stats()

# Глобальные подавители
DIALOG_SUPPRESSOR = None
WIN32_KILLER = None


# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================================================

def is_valid(elem):
    try:
        return elem is not None and elem.IsValidObject
    except:
        return False


def safe_delete(doc, eid, label=""):
    if DRY_RUN:
        return 1
    try:
        deleted = doc.Delete(eid)
        return deleted.Count if deleted else 1
    except:
        return 0


def delete_by_class(doc, cls_name, label):
    cls = globals().get(cls_name)
    if cls is None:
        return 0
    
    try:
        elems = list(FilteredElementCollector(doc).OfClass(cls))
    except:
        return 0
    
    if not elems:
        return 0
    
    if DRY_RUN:
        Output("[DRY] {0}: {1}".format(label, len(elems)))
        return len(elems)
    
    deleted = 0
    for e in elems:
        if is_valid(e) and safe_delete(doc, e.Id, label) > 0:
            deleted += 1
    
    if deleted:
        Output("{0}: {1}".format(label, deleted))
    
    return deleted


def get_output_folder():
    if OUTPUT_FOLDER and OUTPUT_FOLDER.strip():
        return OUTPUT_FOLDER
    
    for p in (dataExportFolderPath, sessionDataFolderPath):
        if p and p.strip():
            return p
    
    if revitFilePath:
        base = System.IO.Path.GetDirectoryName(revitFilePath)
        if base:
            return System.IO.Path.Combine(base, "Cleaned")
    
    return System.IO.Path.Combine(
        System.Environment.GetFolderPath(System.Environment.SpecialFolder.DesktopDirectory),
        "Cleaned"
    )


def ensure_dir(path):
    if not System.IO.Directory.Exists(path):
        System.IO.Directory.CreateDirectory(path)


def get_output_path(folder):
    name = None
    if revitFilePath:
        name = System.IO.Path.GetFileName(revitFilePath)
    
    if not name:
        name = (doc.Title if doc and doc.Title else "Model") + ".rvt"
    
    if not name.lower().endswith(".rvt"):
        name += ".rvt"
    
    return System.IO.Path.Combine(folder, name)


# ============================================================================
# УДАЛЕНИЕ ЭЛЕМЕНТОВ
# ============================================================================

def delete_links(doc):
    d = 0
    d += delete_by_class(doc, "RevitLinkInstance", "Link instances")
    d += delete_by_class(doc, "RevitLinkType", "Link types")
    d += delete_by_class(doc, "CoordinationModel", "Coordination models")
    d += delete_by_class(doc, "PointCloudInstance", "Point clouds")
    d += delete_by_class(doc, "PointCloudType", "Point cloud types")
    d += delete_by_class(doc, "ImageType", "Images")
    d += delete_by_class(doc, "DecalType", "Decals")
    
    if d == 0:
        Output("Links: none")
    
    return d


def delete_imports(doc):
    d = 0
    d += delete_by_class(doc, "ImportInstance", "CAD instances")
    d += delete_by_class(doc, "CADLinkType", "CAD types")
    
    if d == 0:
        Output("Imports: none")
    
    return d


def delete_sheets(doc):
    try:
        sheets = list(FilteredElementCollector(doc).OfClass(ViewSheet))
    except:
        return 0
    
    if not sheets:
        Output("Sheets: none")
        return 0
    
    if DRY_RUN:
        Output("[DRY] Sheets: {0}".format(len(sheets)))
        return len(sheets)
    
    deleted = 0
    for s in sheets:
        if is_valid(s) and safe_delete(doc, s.Id) > 0:
            deleted += 1
    
    Output("Sheets: {0}".format(deleted))
    return deleted


def delete_views(doc):
    try:
        views = list(FilteredElementCollector(doc).OfClass(View))
    except:
        return 0
    
    to_delete_ids = []
    kept = 0
    
    for v in views:
        if not is_valid(v):
            continue
        
        try:
            if v.IsTemplate or isinstance(v, ViewSheet):
                continue
        except:
            continue
        
        name = v.Name if v.Name else ""
        keep = False
        
        for pattern in VIEWS_TO_KEEP:
            if pattern.lower() in name.lower():
                keep = True
                break
        
        if keep:
            kept += 1
        else:
            try:
                to_delete_ids.append(v.Id)
            except:
                pass
    
    if not to_delete_ids:
        return 0
    
    if DRY_RUN:
        Output("[DRY] Views: {0} (keep {1})".format(len(to_delete_ids), kept))
        return len(to_delete_ids)
    
    deleted = 0
    failed = 0
    for eid in to_delete_ids:
        try:
            if safe_delete(doc, eid) > 0:
                deleted += 1
            else:
                failed += 1
        except Exception as ex:
            failed += 1
            Output("WARNING: View delete failed: {0}".format(ex))
    
    if failed:
        Output("Views failed: {0}".format(failed))
    Output("Views: {0} (kept {1})".format(deleted, kept))
    return deleted


# ============================================================================
# ОЧИСТКА НЕИСПОЛЬЗУЕМОГО
# ============================================================================

def get_used_type_ids(doc):
    used = set()
    try:
        for e in FilteredElementCollector(doc).WhereElementIsNotElementType():
            if is_valid(e):
                try:
                    tid = e.GetTypeId()
                    if tid != ElementId.InvalidElementId:
                        used.add(tid)
                except:
                    pass
    except:
        pass
    
    return used


def purge_via_adviser(doc):
    if DRY_RUN:
        Output("[DRY] PerformanceAdviser purge")
        return 0
    
    purge_guid = Guid("e8c63650-70b7-435a-9010-ec97660c1bda")
    rule_id = None
    
    try:
        for rule in PerformanceAdviser.GetPerformanceAdviser().GetAllRuleIds():
            if rule.Guid.Equals(purge_guid):
                rule_id = rule
                break
    except:
        return None
    
    if rule_id is None:
        return None
    
    total = 0
    for i in range(1, 21):
        try:
            rules = List[PerformanceAdviserRuleId]()
            rules.Add(rule_id)
            
            msgs = PerformanceAdviser.GetPerformanceAdviser().ExecuteRules(doc, rules)
            if not msgs or msgs.Count == 0:
                break
            
            ids = msgs[0].GetFailingElements()
            if not ids or ids.Count == 0:
                break
            
            t = create_silent_transaction(doc, "Purge {0}".format(i))
            try:
                t.Start()
                deleted = doc.Delete(ids)
                t.Commit()
                
                count = deleted.Count if deleted else 0
                total += count
                
                if count == 0:
                    break
            except:
                if t.HasStarted():
                    t.RollBack()
                break
        except:
            break
    
    Output("Adviser purge: {0}".format(total))
    return total


def purge_manual(doc):
    if DRY_RUN:
        Output("[DRY] Manual purge")
        return 0
    
    total = 0
    for i in range(1, 21):
        deleted = 0
        t = create_silent_transaction(doc, "Manual purge {0}".format(i))
        
        try:
            t.Start()
            
            used_ids = get_used_type_ids(doc)
            
            for sym in FilteredElementCollector(doc).OfClass(FamilySymbol):
                if is_valid(sym) and sym.Id not in used_ids:
                    if safe_delete(doc, sym.Id) > 0:
                        deleted += 1
            
            for et in FilteredElementCollector(doc).WhereElementIsElementType():
                if is_valid(et) and et.Id not in used_ids:
                    if safe_delete(doc, et.Id) > 0:
                        deleted += 1
            
            for mat in FilteredElementCollector(doc).OfClass(Material):
                if is_valid(mat):
                    if safe_delete(doc, mat.Id) > 0:
                        deleted += 1
            
            t.Commit()
            
        except:
            if t.HasStarted():
                t.RollBack()
            break
        
        if deleted == 0:
            break
        
        total += deleted
        Output("  Pass {0}: {1}".format(i, deleted))
    
    Output("Manual purge: {0}".format(total))
    return total


def purge_unused(doc):
    Output("")
    Output("Purging unused...")
    
    result = purge_via_adviser(doc)
    if result is None:
        result = purge_manual(doc)
    
    return result or 0


# ============================================================================
# СОХРАНЕНИЕ
# ============================================================================

def save_model(doc, path):
    if DRY_RUN:
        Output("[DRY] Save: {0}".format(path))
        return
    
    Output("")
    Output("=" * 50)
    Output("SAVING MODEL")
    Output("=" * 50)
    Output("Path: {0}".format(path))
    Output("Compact: {0}".format(COMPACT_ON_SAVE))
    Output("Workshared: {0}".format(doc.IsWorkshared))
    
    opts = SaveAsOptions()
    opts.OverwriteExistingFile = True
    opts.MaximumBackups = 1
    opts.Compact = COMPACT_ON_SAVE
    
    if doc.IsWorkshared:
        ws = WorksharingSaveAsOptions()
        
        try:
            ws.SaveAsCentral = True
            Output("  Using: SaveAsCentral (2024+ API)")
        except:
            try:
                ws.MakeCentral = True
                Output("  Using: MakeCentral (2022 API)")
            except:
                Output("  WARNING: Could not set central mode")
        
        opts.SetWorksharingOptions(ws)
    
    try:
        Output("  Starting SaveAs...")
        doc.SaveAs(path, opts)
        
        if System.IO.File.Exists(path):
            size_mb = System.IO.FileInfo(path).Length / 1024.0 / 1024.0
            Output("")
            Output("=" * 50)
            Output("SAVE SUCCESS!")
            Output("=" * 50)
            Output("  File: {0}".format(path))
            Output("  Size: {0:.1f} MB".format(size_mb))
            Output("=" * 50)
        else:
            Output("")
            Output("WARNING: SaveAs executed but file not found!")
            STATS.error("File not created after SaveAs")
    
    except Exception as e:
        Output("")
        Output("=" * 50)
        Output("SAVE ERROR!")
        Output("=" * 50)
        Output("  Error: {0}".format(e))
        STATS.error("SaveAs exception: {0}".format(e))
        raise


# ============================================================================
# ЭКСПОРТ NWC
# ============================================================================

def export_nwc_via_revit(doc, output_folder):
    if not HAS_NAVISWORKS_EXPORT:
        Output("WARNING: NavisworksExportOptions not available")
        return False
    
    if DRY_RUN:
        Output("[DRY] NWC export via Revit API")
        return True
    
    try:
        file_name = None
        if revitFilePath:
            base_name = System.IO.Path.GetFileNameWithoutExtension(revitFilePath)
            file_name = base_name + ".nwc"
        else:
            file_name = (doc.Title if doc and doc.Title else "Model") + ".nwc"
        
        nwc_folder = output_folder
        if NWC_FOLDER and NWC_FOLDER.strip():
            nwc_folder = NWC_FOLDER
        
        if not nwc_folder:
            nwc_folder = OUTPUT_FOLDER if OUTPUT_FOLDER else System.IO.Path.GetDirectoryName(revitFilePath)
        
        ensure_dir(nwc_folder)
        
        view_3d = None
        view_names_priority = ["Navisworks", "{3D} - Navisworks", "{3D}"]
        
        for vname in view_names_priority:
            collector = FilteredElementCollector(doc).OfClass(View3D)
            for v in collector:
                if v.Name == vname and not v.IsTemplate:
                    view_3d = v
                    break
            if view_3d:
                break
        
        if not view_3d:
            collector = FilteredElementCollector(doc).OfClass(View3D)
            for v in collector:
                if not v.IsTemplate:
                    view_3d = v
                    break
        
        if not view_3d:
            Output("ERROR: No 3D view found for NWC export")
            return False
        
        Output("NWC export view: {0}".format(view_3d.Name))
        
        nwc_options = NavisworksExportOptions()
        
        if NWC_COORDINATES == "shared":
            nwc_options.Coordinates = NavisworksCoordinates.Shared
        else:
            nwc_options.Coordinates = NavisworksCoordinates.Internal
        
        nwc_options.ExportScope = NavisworksExportScope.View
        nwc_options.ViewId = view_3d.Id
        nwc_options.ExportLinks = NWC_CONVERT_LINKS
        nwc_options.DivideFileIntoLevels = NWC_DIVIDE_BY_LEVEL
        nwc_options.ExportElementIds = NWC_CONVERT_IDS
        nwc_options.ExportRoomAsAttribute = False
        nwc_options.ExportRoomGeometry = False
        nwc_options.ConvertElementProperties = True
        nwc_options.FindMissingMaterials = False
        
        nwc_path = System.IO.Path.Combine(nwc_folder, file_name)
        Output("Exporting NWC: {0}".format(nwc_path))
        
        doc.Export(nwc_folder, file_name.Replace(".nwc", ""), nwc_options)
        
        if System.IO.File.Exists(nwc_path):
            size_mb = System.IO.FileInfo(nwc_path).Length / 1024.0 / 1024.0
            Output("NWC exported: {0:.1f} MB".format(size_mb))
            return True
        else:
            Output("WARNING: NWC file not created")
            return False
    
    except Exception as e:
        Output("NWC export error: {0}".format(e))
        return False


# ============================================================================
# MAIN
# ============================================================================

def main():
    global DIALOG_SUPPRESSOR, WIN32_KILLER
    
    try:
        Output("")
        Output("=" * 50)
        Output("REVIT MODEL CLEANER v4.0")
        Output("=" * 50)
        
        if doc is None:
            STATS.error("Document is None")
            return
        
        revit_version = uiapp.Application.VersionNumber if uiapp and uiapp.Application else "Unknown"
        Output("Revit Version: {0}".format(revit_version))
        Output("Source: {0}".format(revitFilePath or "unknown"))
        Output("Workshared: {0}".format("Yes" if doc.IsWorkshared else "No"))
        Output("")
        
        # КРИТИЧНО: Запускаем все подавители диалогов
        if SUPPRESS_DIALOGS:
            Output("Starting dialog suppressors...")
            
            # 1. Win32 фоновый убийца диалогов
            WIN32_KILLER = Win32DialogKiller()
            WIN32_KILLER.start()
            
            # 2. Revit API подавитель
            DIALOG_SUPPRESSOR = EnhancedDialogSuppressor(uiapp)
            DIALOG_SUPPRESSOR.attach()
            
            Output("")
        
        # Фаза 1: Удаление
        if DELETE_LINKS or DELETE_IMPORTS or DELETE_SHEETS or DELETE_VIEWS:
            if not DRY_RUN:
                t = Transaction(doc, "Clean model")
                try:
                    t.Start()
                    
                    if DELETE_LINKS:
                        STATS.links = delete_links(doc)
                    
                    if DELETE_IMPORTS:
                        STATS.imports = delete_imports(doc)
                    
                    if DELETE_SHEETS:
                        STATS.sheets = delete_sheets(doc)
                    
                    if DELETE_VIEWS:
                        STATS.views = delete_views(doc)
                    
                    t.Commit()
                    
                except Exception as ex:
                    if t.HasStarted():
                        t.RollBack()
                    STATS.error("Delete failed: {0}".format(ex))
                    raise
            else:
                if DELETE_LINKS:
                    STATS.links = delete_links(doc)
                if DELETE_IMPORTS:
                    STATS.imports = delete_imports(doc)
                if DELETE_SHEETS:
                    STATS.sheets = delete_sheets(doc)
                if DELETE_VIEWS:
                    STATS.views = delete_views(doc)
        
        # Фаза 2: Очистка
        if PURGE_UNUSED:
            STATS.purged = purge_unused(doc)
        
        # Фаза 3: Экспорт NWC
        if EXPORT_NWC and not DRY_RUN:
            Output("")
            Output("=" * 50)
            Output("EXPORTING NWC")
            Output("=" * 50)
            export_nwc_via_revit(doc, get_output_folder())
        
        # Фаза 4: Сохранение
        folder = get_output_folder()
        ensure_dir(folder)
        path = get_output_path(folder)
        
        save_model(doc, path)
        
        # Отчет
        STATS.summary()
        
        # Статистика подавления
        if DIALOG_SUPPRESSOR:
            summary = DIALOG_SUPPRESSOR.get_summary()
            Output("")
            Output("Revit dialogs suppressed: {0}".format(summary["count"]))
            if summary["dialogs"]:
                Output("Dialog types: {0}".format(", ".join(summary["dialogs"][:5])))
        
        if WIN32_KILLER:
            Output("Win32 dialogs closed: {0}".format(WIN32_KILLER.get_closed_count()))
        
        Output("")
        Output("DONE")
    
    except Exception as e:
        STATS.error("Fatal: {0}".format(e))
        STATS.summary()
        Output("")
        Output("FAILED")
        raise
    
    finally:
        # КРИТИЧНО: Останавливаем все подавители
        if WIN32_KILLER:
            WIN32_KILLER.stop()
        
        if DIALOG_SUPPRESSOR:
            DIALOG_SUPPRESSOR.detach()


# Запуск
main()
