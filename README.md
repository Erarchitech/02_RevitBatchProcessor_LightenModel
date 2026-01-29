# 02_XML_RevitBatchProcessor
@'
$path = 'README.md'
$lines = @(
  '# 02_XML_RevitBatchProcessor',
  '',
  '## Инструкция по запуску',
  '',
  '1) Проверьте настройки в `config.json`:',
  '   - `RS_HOST` — адрес Revit Server.',
  '   - `source_folder` — папка на сервере (например `|Project|Folder|` или `RSN://server/Project/Folder`).',
  '   - `download_folder` — куда скачать исходные модели.',
  '   - `output_folder` — куда сохранять очищенные модели.',
  '   - `log_folder` — куда писать логи.',
  '   - `revit_version` — версия Revit (например `"2022"`).',
  '   - `models` — список моделей; если пустой (`[]`), будут взяты все модели из `source_folder`.',
  '',
  '2) Параметры очистки в `config.json`:',
  '   - `purge_unused` — удаляет неиспользуемые элементы (Purge Unused) при открытии модели.',
  '   - `delete_sheets` — удаляет листы из модели.',
  '   - `delete_imports` — удаляет импортированные CAD и другие импортируемые объекты.',
  '   - `delete_links` — удаляет связи (Revit/CAD/IFC links).',
  '   - `compact_on_save` — сохраняет модель с уплотнением (Compact) для уменьшения размера.',
  '',
  '3) Запустите `run_LightModelExport.bat` двойным кликом.',
  '',
  '4) Дождитесь завершения; логи смотрите в папке `PROJECT\\Scripts\\BatchRvtLogs`.'
)
Set-Content -Path $path -Value $lines -Encoding UTF8
'@ | powershell -NoProfile -File -