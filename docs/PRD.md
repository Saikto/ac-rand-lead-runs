# AC Random Lead Runs — PRD

## 1. Цель

Сделать тренажёр chase-заездов для оригинальной Assetto Corsa, в котором пользователь:

1. записывает несколько собственных lead runs;
2. вручную принимает или отбрасывает каждый проезд;
3. запускает выбранный либо случайный ран;
4. не знает траекторию случайного лидера заранее;
5. получает естественно выглядящего и физически контактного лидера.

Главная ценность — тренировать реакцию на разные линии, ошибки и темп лидера, а не muscle memory одного неизменного проезда.

## 2. Принятые решения

- Все действия выполняются кнопками в resizeable in-game app window; hotkeys не используются.
- Запись начинается и заканчивается вручную, затем пользователь выбирает `Keep run` или `Discard run`.
- Track ID, layout ID и car ID должны совпадать с playback-сессией.
- Random — независимый равномерный выбор; immediate repeat разрешён.
- В random mode ID выбранного рана скрыт до завершения попытки.
- Tags и rating не входят в MVP.
- Лидер остаётся на записанной траектории при контакте, chase-машина получает физический impulse.
- Tyre smoke отложен и не блокирует текущую разработку.
- Минимальная целевая версия — CSP 0.2.11+.

## 3. Актуальная архитектура

```text
Offline Recorder New Mode
        │ Keep
        ▼
Documents/Assetto Corsa/ac-random-lead-runs/runs/
  <track>/<layout>/<car>/<run-id>.json
        │ server startup
        ▼
AssettoServer + RandomLeadServerPlugin
        │ native AC position packets
        ▼
Recorded Leader in localhost online session

Single resizeable CSP app window
  offline ──► recorder commands
  online  ──► loopback HTTP playback commands

Local browser launcher
  library/session settings ──► generated fixture ──► managed AssettoServer process
```

### 3.1 Recorder

New Mode записывает player car с частотой 50 Hz: physics transform, velocity, inputs, gear, RPM и angular speed четырёх колёс. Recorder не создаёт, не двигает и не рендерит leader car.

### 3.2 Run library

Каждый принятый ран сохраняется отдельным JSON. `latest.json` обновляется как совместимый указатель, а сервер дедуплицирует его по run ID.

При запуске сервер читает все JSON текущей track/layout/car папки, проверяет schema v1/v2/v3 и пропускает повреждённые или несовместимые файлы с записью в лог. Live reload пока отсутствует: после добавления ранов сервер нужно перезапустить.

### 3.3 Playback backend

Принят localhost AssettoServer backend. Плагин резервирует leader slot и отправляет обычные AC network position packets с transform, velocity, steering, wheel speed, RPM, gear, throttle и brake lights.

Живым тестом подтверждены правильная высота кузова, wheel/suspension animation, engine audio, односторонний collision impulse и отсутствие отклонения лидера от записи. Отвергнутые Lua physical-teleport и undocumented native replay варианты удалены из runtime-кода; их история остаётся в Git.

### 3.4 Управление

В online-сессии app общается с loopback-only API `127.0.0.1:8081` и предоставляет `Play selected`, `Next`, `Random`, `Restart` и `Stop`. Состояния сервера: `waiting_for_player`, `countdown`, `playing`, `loop_wait`, `completed`, `stopped`.

## 4. UX-потоки

### Запись

1. Запустить `AC Random Lead Runs — Recorder` offline.
2. Открыть app `Random Lead Runs`.
3. Нажать `Start recording`, проехать ран и нажать `Stop recording`.
4. Проверить duration/sample count.
5. Нажать `Keep run` или `Discard run`.

### Chase

1. Запустить localhost server и подключиться к `127.0.0.1:9600`.
2. Открыть app `Random Lead Runs`.
3. Выбрать current, next или random и дождаться countdown.
4. Использовать Restart, Next или Stop без перезапуска AC-сессии.

## 5. Ограничения

- Сервер читает библиотеку только при старте.
- Нет metadata index, enabled toggle/delete и live rescan.
- Нет tyre smoke у synthetic remote leader.
- Публичная упаковка AssettoServer требует AGPL-compatible решения.
- Pinned AssettoServer приносит upstream advisories для Scriban; packaging заблокирован до обновления или отдельной оценки риска.

## 6. Критерии MVP

- Запись, Stop, Keep и Discard стабильно работают из app window.
- Минимум 20 совместимых ранов загружаются за один старт сервера.
- Current, next и random работают без перезапуска AC-сессии.
- Random не раскрывает следующий ран заранее.
- Restart занимает не больше 5 секунд.
- Leader trajectory детерминирована и не меняется от контакта.
- Chase car получает collision impulse.
- Повреждённый ран пропускается с понятной записью в логе.

## 7. Следующие этапы

1. Диагностировать remote wheel/slip/suspension state и решить судьбу smoke/skid marks на основании измерений.
2. Library UI: список ранов, enable/disable, delete с подтверждением, live reload и человекочитаемые названия.
3. Start preparation: отдельные состояния `armed` и `countdown`, лидер ждёт на первой позиции, пользователь запускает отсчёт после построения chase car.
4. Расширить готовый local launcher: live rescan, несколько разрешённых chase cars, metadata и standalone packaging.
5. Нагрузочный тест библиотеки из 20+ ранов и packaging.
6. Polishing: trim, metadata, фильтры и компактный production status вместо диагностического блока.

## 8. Launcher и будущие экраны

Для первой версии launcher выбирается локальное browser UI, которое стартует вместе с небольшим launcher process. Это даёт полноценные dropdown/search controls и не привязывает проект к внутренним, нестабильным extension points Content Manager. Позже можно добавить CM preset/deeplink как удобную точку входа, не перенося в CM серверную логику.

План экранов:

1. `Library` — track/layout/car filters, список ранов, duration/date, enabled toggle, delete и rescan.
2. `Session` — track/layout, player car и skin, дополнительные разрешённые машины, weather, ambient/road temperature, time, session duration, grip, loop/start delay и порты.
3. `Launch` — проверка конфигурации, Start/Stop server, live log, статус портов и кнопка подключения через CM invite link.
4. `In-game` — только подготовка попытки и управление playback; серверные настройки остаются в launcher, чтобы не перегружать окно во время езды.

Нормальная подготовка старта означает двухшаговый flow: выбор рана ставит лидера неподвижно на первый кадр (`armed`), а отдельная кнопка `Start attempt` запускает видимый отсчёт `3–2–1–GO`. Так chase car может спокойно занять позицию. Для быстрых повторов будет опциональный auto-countdown; random run остаётся скрытым. Restart сначала возвращает лидера на старт, поэтому не начинается неожиданно, пока chase car ещё разворачивается.

## 9. Последующий POC: полноценный protocol bot

Диагностика synthetic leader показала, что v3 wheel speed корректно проходит как legacy, так и CSP Custom Update transport, а `speedDifference` достигает 18 m/s. При этом remote state постоянно возвращает `slipRatio=0`, `nSlip=0.001`, `loadK=1` и `suspensionTravel=0`; штатные smoke, skid marks и полноценная suspension state не появляются.

После launcher/MVP нужно провести отдельный POC с локальным leader bot process, который проходит обычный AC TCP/UDP handshake и отправляет recording как полноценный сетевой клиент. AssettoServer в этом варианте ретранслирует лидера тем же путём, что реального online player. Текущие run library, state machine, API и UI сохраняются, меняется только нижний playback transport.

Критерий POC: на одном и том же recording сравнить synthetic slot и protocol bot по smoke, skid marks, suspension animation, audio, collision impulse и trajectory determinism. Если полноценный client identity не возвращает нативные эффекты, smoke реализуется client-side от уже подтверждённого `speedDifference`, а skid marks оцениваются отдельным spike.
