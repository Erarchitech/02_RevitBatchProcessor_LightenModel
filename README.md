# Revit Batch Export & Clean


Система пакетной обработки моделей Revit: скачивание с Revit Server, очистка, экспорт в Navisworks.

## Структура

```
На сервере (\\srv-dfs\BIM\01_Ресурсы плагинов\10_Облегченные модели\Версия_BAT_2\):
├── Main_Export.ps1           # Основной скрипт
├── clean_model.py            # Скрипт очистки для BatchRvt
├── ListRevitServerModels.ps1 # Получение списка моделей с RS
├── disable_addins.bat        # Отключение аддинов
├── enable_addins.bat         # Включение аддинов
└── README.md                 # Эта инструкция

У пользователя:
└── RUN_Export.bat            # Шаблон с настройками (копируется)
```

## Быстрый старт

1. Скопируйте `RUN_Export.bat` в любую папку на вашем компьютере
2. Откройте файл в текстовом редакторе
3. Заполните настройки (см. раздел "Настройки")
4. Запустите файл двойным кликом

## Требования

- Windows 10/11
- Revit 2020-2025
- [RevitBatchProcessor](https://github.com/bvn-architecture/RevitBatchProcessor) (для очистки)
- Navisworks Manage 2020-2025 (для NWC/NWD)
- Доступ к Revit Server
- Доступ к сетевой папке со скриптами

## Настройки RUN_Export.bat

### Revit Server

| Параметр | Описание | Пример |
|----------|----------|--------|
| `RS_HOST` | IP или имя Revit Server | `10.0.2.35` |
| `RVT_VERSION` | Версия Revit | `2022` |
| `RS_SOURCE_FOLDER` | Папка на RS (можно \| / \\) | `\|Project\|Models\|` |
| `MODELS` | Список моделей (пусто = все) | `Model1.rvt Model2.rvt` |

### Папки вывода

| Параметр | Описание |
|----------|----------|
| `DOWNLOAD_FOLDER` | Папка для локальных копий с RS |
| `OUTPUT_FOLDER` | Папка для очищенных файлов |
| `LOG_FOLDER` | Папка для логов |
| `NWC_FOLDER` | Папка для NWC файлов |
| `NWD_FOLDER` | Папка для NWD файла |
| `NWD_FILENAME` | Имя NWD файла |

### Этапы обработки

| Параметр | Описание | Значение |
|----------|----------|----------|
| `ENABLE_DOWNLOAD` | Скачивание моделей | 1/0 |
| `ENABLE_CLEAN` | Очистка моделей | 1/0 |
| `ENABLE_NWC` | Экспорт в NWC | 1/0 |
| `ENABLE_NWD` | Сборка NWD | 1/0 |

### Параметры Navisworks (экспорт NWC)

| Параметр | Описание | По умолчанию |
|----------|----------|--------------|
| `NWC_CONVERT_LINKS` | Загружать связи Revit | 0 (нет) |
| `NWC_DIVIDE_BY_LEVEL` | Разделять по уровням | 1 |
| `NWC_CONVERT_IDS` | Экспортировать Element IDs | 1 |
| `NWC_COORDINATES` | Координаты: shared/internal | shared |
| `NWC_FACETING` | Качество геометрии (0.1-10) | 1.0 |
| `NWC_ROOMS` | Геометрия помещений | 0 |
| `NWC_LIGHTS` | Источники света | 0 |

### Параметры очистки

| Параметр | Описание | По умолчанию |
|----------|----------|--------------|
| `DELETE_LINKS` | Удалять связи Revit | 1 |
| `DELETE_IMPORTS` | Удалять CAD импорт | 1 |
| `DELETE_SHEETS` | Удалять листы | 1 |
| `DELETE_VIEWS` | Удалять виды | 0 |
| `VIEWS_TO_KEEP` | Виды для сохранения | `{3D},3D,Level` |
| `PURGE_UNUSED` | Очищать неиспользуемое | 1 |
| `COMPACT_ON_SAVE` | Сжимать при сохранении | 1 |
| `DRY_RUN` | Тестовый режим | 0 |
| `SUPPRESS_DIALOGS` | Автозакрытие диалогов | 1 |

## Примеры сценариев

### Только скачивание (без очистки)

```batch
set "ENABLE_DOWNLOAD=1"
set "ENABLE_CLEAN=0"
set "ENABLE_NWC=0"
set "ENABLE_NWD=0"
```

### Очистка + NWC (без NWD)

```batch
set "ENABLE_DOWNLOAD=1"
set "ENABLE_CLEAN=1"
set "ENABLE_NWC=1"
set "ENABLE_NWD=0"
```

### Полный цикл

```batch
set "ENABLE_DOWNLOAD=1"
set "ENABLE_CLEAN=1"
set "ENABLE_NWC=1"
set "ENABLE_NWD=1"
```

### Только конкретные модели

```batch
set "MODELS=AR_Model.rvt KR_Model.rvt MEP_Model.rvt"
```

## Последовательность выполнения

1. **Скачивание** → Модели копируются с RS в `DOWNLOAD_FOLDER`
2. **Очистка** → Модели очищаются и сохраняются в `OUTPUT_FOLDER`
3. **NWC экспорт** → Создаются NWC, перемещаются в `NWC_FOLDER`
4. **NWD сборка** → Создается сводный NWD в `NWD_FOLDER`

## Логи и отчеты

После выполнения в `LOG_FOLDER` создаются:
- `export_YYYYMMDD_HHMMSS.log` - текстовый лог
- `report_YYYYMMDD_HHMMSS.json` - JSON-отчет
- `BatchRvt_*.log` - логи BatchRvt
- `Navisworks_*.log` - логи Navisworks

## Устранение проблем

### Автоматическое закрытие диалогов

При `SUPPRESS_DIALOGS=1` скрипт автоматически закрывает:
- Предупреждения об отсутствующих плагинах (IEK, Dynamo и др.)
- Диалоги о рабочих наборах
- Предупреждения об обновлениях
- Вопросы о сохранении
- Большинство системных диалогов Revit

В логе будет указано количество подавленных диалогов.

### Вид "Navisworks" в Revit

Navisworks при экспорте ищет 3D вид в таком порядке:
1. `Navisworks` (точное имя)
2. `{3D} - Navisworks`
3. `{3D}` (стандартный)

**Рекомендация**: Создайте в шаблоне Revit вид с именем `Navisworks` и настройте:
- Отключите ненужные категории (аннотации, размеры)
- Скройте связи через Visibility/Graphics
- Настройте уровень детализации

### "Серверные скрипты недоступны"
- Проверьте сетевое подключение
- Проверьте путь `SCRIPTS_SERVER`

### "RevitServerTool не найден"
- Убедитесь что Revit установлен
- Проверьте версию `RVT_VERSION`

### "BatchRvt не найден"
- Установите [RevitBatchProcessor](https://github.com/bvn-architecture/RevitBatchProcessor)

### "Navisworks не найден"
- Установите Navisworks Manage

### Ошибки скачивания
- Проверьте IP/имя RS в `RS_HOST`
- Проверьте права доступа к RS
- Увеличьте `RETRY_COUNT`

## Поддерживаемые версии

- Revit: 2020, 2021, 2022, 2023, 2024, 2025
- Navisworks: 2020, 2021, 2022, 2023, 2024, 2025
- Windows: 10, 11, Server 2016+
