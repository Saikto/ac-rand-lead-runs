# AC Random Lead Runs — PRD и технический план

Статус: draft после первичного research  
Дата: 2026-08-25

## 1. Короткий вывод

Для первого fidelity-spike отдельный Assetto Corsa dedicated server не нужен. Production playback backend пока не считается подтверждённым.

Наиболее прямой путь — собственный **CSP Lua New Mode** в offline Track Day:

1. режим записывает телеметрию машины игрока во время lead run;
2. пользователь вручную принимает или выбрасывает проезд и при необходимости подрезает начало/конец;
3. принятые раны складываются в библиотеку по track/layout/car;
4. второй локальный автомобиль воспроизводит ран через нативный CSP replay-car pipeline;
5. in-game UI управляет записью, библиотекой, single/random playback и стартовой логикой.

Официальный пример `altonline_ghost` остаётся полезным референсом, но фактический spike показал: в установленном CSP 0.2.11 build 3465 отсутствует модуль `shared/sim/altonline`. Поэтому `altonline` нельзя считать доступным baseline API для заявленной минимальной версии. Phase 0 переведён на документированные в локальном SDK `physics.setCarPosition()`, `physics.setCarVelocity()` и физический AI-opponent.

Phase 0 подтвердил ключевую feasibility-гипотезу: state-driven физический AI передаёт collision impulse chase-машине, но сам возвращается на заданную траекторию и не сбивается от контакта. Оставшиеся неизвестности относятся к качеству playback: поверхность, ориентация, анимация колёс, дым, звук и jitter.

Phase 1 подтвердил полный data lifecycle и точность world-space route, но опроверг пригодность physical teleport backend для production: повторный `physics.setCarPosition()` выравнивает машину по поверхности и сбрасывает/возмущает suspension, wheel, steering и engine state. A/B-тест offset 0–15 cm не изменил ride height; заднее колесо получало в среднем 1.3 rad/s при target 29.7 rad/s. Live custom engine audio работает, однако отдельный Lua/FMOD event не сериализуется обычным AC replay.

Архитектура переводится на нативный replay-car backend. Первый кандидат — официальный CSP `ac.setReplayBasedGhost()`/`Revenant` с collision mode `stiff`. Если он не позволит загружать сохранённую библиотеку, production fallback — localhost fake server, который выдаёт раны как нативные remote cars по модели Virtual Steward. Подробное решение: [PLAYBACK_BACKEND_DECISION.md](PLAYBACK_BACKEND_DECISION.md).

## 2. Проблема

Существующие replay-лидеры на drift-серверах:

- представлены небольшим числом похожих ранов;
- повторяются без вариативности;
- быстро запоминаются;
- развивают muscle memory под конкретного лидера сильнее, чем адаптацию chase-пилота к ошибкам, темпу и линиям другого водителя.

Нужен тренажёр, в котором пользователь сам накапливает достаточно разнообразную базу реалистичных лидов, а перед стартом chase не знает, какой именно ран выбран.

## 3. Цель продукта

Дать одному игроку быстрый offline loop:

`записать лиды → отобрать хорошие/полезные → выбрать набор → многократно тренировать chase со случайным лидом`.

Успешная сессия должна почти не требовать Alt+Tab, ручного копирования файлов или перезапуска Assetto Corsa.

### Не цели MVP

- полноценный публичный multiplayer-сервер;
- AI, который сам генерирует новые drift-линии;
- судейство chase или автоматическая оценка proximity/style;
- универсальный редактор `.acreplay`;
- синхронизация библиотеки между несколькими компьютерами;
- физически симулируемый AI-лидер, повторяющий inputs через tyre model.

Последний пункт принципиален: воспроизведение inputs через полноценную физику менее детерминировано и зависит от версии машины, setup, шин, температуры и состояния трассы. Для тренировки важнее точно повторить записанную траекторию.

## 4. Что показал research

### 4.1 CSP уже предоставляет подходящий runtime

В локальной установке найден CSP **0.2.11, build 3465**, Lua SDK и несколько встроенных New Modes. Официальный CSP Lua SDK поставляется вместе с CSP в `extension/internal/lua-sdk`; официальный репозиторий рекомендует использовать именно локальные definitions как актуальную документацию ([CSP Lua SDK](https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/README.md)).

Полезные доступные API:

- `physics.setAINoInput()` — отключение обычного AI-input у локального оппонента;
- `physics.setCarPosition()` / `physics.setCarVelocity()` — state-driven playback физического оппонента;
- `physics.raycastTrack()` — привязка к поверхности, если она нужна;
- Lua UI — полноценное in-game меню;
- file I/O — локальная библиотека ранов;
- `ac.ReplayStream()` / `ac.writeReplayBlob()` — дополнительные данные в собственных будущих replays;
- `ac.tryToToggleReplay()` и `ac.setReplayPosition()` — управление instant replay;
- `ac.saveCarStateAsync()` / `ac.loadCarState()` — полный state машины, но только для специальных offline-сценариев и не как основной формат траектории;
- `shared/sim/altonline` отсутствует в локальном CSP 0.2.11 build 3465, хотя используется более новым официальным примером; его минимальная версия пока не установлена.

Официальный `altonline_ghost` уже интерполирует позиции, рассчитывает velocity, ориентацию относительно поверхности, wheel speed, counter-steer, RPM и lights, затем вызывает `submitState()`. Сам пример подчёркивает, что `altonline` создаёт почти настоящую машину, а не просто полупрозрачный ghost ([README примера](https://github.com/ac-custom-shaders-patch/acc-lua-examples/blob/main/new_modes/altonline_ghost/README.md), [код](https://github.com/ac-custom-shaders-patch/acc-lua-examples/blob/main/new_modes/altonline_ghost/script.lua)).

### 4.2 Почему не обычный AC ghost

Обычный ghost хорош для hotlap, но для chase важны:

- обычный внешний вид лидера;
- корректные колёса, brake lights, RPM/audio и tyre smoke;
- пространственное присутствие и, по выбранной политике, контакт;
- произвольный короткий участок, а не только lap semantics.

Физический локальный AI потенциально совпадает с требованиями контакта лучше, но его visual/audio качество и стабильность должны пройти Phase 0.

### 4.3 Почему не dedicated server в MVP

Обычный AC dedicated server не является хостом физически управляемого AI-лидера: онлайн-слоты рассчитаны на подключённые клиенты. Серверный вариант потребует fake/headless client, эмуляции сетевого протокола или отдельного bot-процесса. Это значительно усложняет запуск, синхронизацию и поддержку.

Сервер имеет смысл только если позже появится требование, чтобы несколько chase-пилотов одновременно видели одного синхронизированного лидера.

### 4.4 Что видно по Virtual Steward 0.5c

Локальная сборка Virtual Steward была проверена как референс:

- это внешний Windows executable;
- он умеет читать папку AC replays и конкретный `.acreplay`;
- в комплекте есть специальный `camera_car`;
- shortcut запускает Content Manager на локальный адрес `127.0.0.1:8081`;
- настройки и каталогизация replay находятся во внешнем UI.

Это указывает на архитектуру «внешний процесс + локальный сервер/stream + специальная машина». Она рабочая, но создаёт именно тот usability overhead, которого мы хотим избежать: отдельное приложение, пути, подключение к локальному серверу и слабая интеграция workflow записи/отбора/random-next в игру.

Virtual Steward остаётся полезным сравнением и возможным аварийным вариантом для импорта `.acreplay`, но не зависимостью проекта.

## 5. Основные пользовательские сценарии

### 5.1 Запись базы

1. Пользователь запускает режим на нужных track/layout и машине.
2. Нажимает `Start recording` в окне приложения.
3. С этого момента начинается запись.
4. По кнопке `Stop recording` запись заканчивается.
5. Появляется review card: длительность, car/track, дата, простые warnings.
6. Пользователь выбирает `Keep`, `Discard` или `Trim`.
7. Сохранённый ран сразу доступен в библиотеке.

### 5.2 Тренировка одного рана

1. Пользователь выбирает конкретный run.
2. Подъезжает в выбранную им позицию для старта chase.
3. Нажимает `Start chase` в окне приложения.
4. Лидер появляется в записанной начальной позиции и после настраиваемой задержки начинает ран.
5. После finish он исчезает и сбрасывается к старту.
6. Тот же ран готов к следующей попытке.

### 5.3 Random training

1. Пользователь выбирает pack или фильтры библиотеки.
2. Включает `Random`.
3. До старта UI не показывает имя следующего рана.
4. Каждый цикл выбирается случайный подходящий ран.
5. По завершении лидер скрывается, а следующий ран выбирается только перед новой попыткой.

## 6. UX in-game

Одна CSP Lua app/window внутри режима, с четырьмя компактными вкладками.

### Drive

- состояние: `Idle / Armed / Countdown / Running / Finished`;
- `Record lead`;
- `Start chase`;
- `Single` / `Random`;
- выбранный pack и число доступных ранов;
- `Skip next`, `Restart`, `Stop`;
- опция скрывать ID случайного рана до финиша.

### Library

- фильтры track/layout/car;
- enable/disable run для random pool;
- keep/discard последней записи;
- trim start/end;
- удаление только с подтверждением или через recoverable Trash.

### Playback

- текущий режим и состояние лидера;
- ручные `Start chase`, `Restart`, `Stop` и `Skip`;
- launch delay и reset delay;
- включение/выключение countdown;
- debug-строка с ID завершённого рана.

### Settings

- contact policy;
- sampling rate;
- random policy;
- countdown/sounds;
- debug overlay: sample index, drift angle, speed, interpolation error.

Управление выполняется из обычного CSP Lua app window. Проект не регистрирует hotkeys: клавиши и кнопки руля пользователя считаются занятым внешним ресурсом.

## 7. Предлагаемая архитектура

### 7.1 Состав

1. **CSP New Mode** — session lifecycle, state machine, virtual leader и HUD.
2. **Recorder** — sampling `ac.getCar(0)` с фиксированным временным шагом и/или маркировка нативного rolling replay.
3. **Run player adapter** — сначала native replay-based opponent, затем при необходимости localhost remote-car backend. Physical teleport остаётся только диагностическим fallback.
4. **Run library** — чтение/запись файлов, filtering и migration версии формата.
5. **In-game app UI** — управление всеми предыдущими компонентами.
6. **Replay importer** — отдельный optional milestone, не часть первого vertical slice.

### 7.2 Session manifest

Базовые параметры режима:

```ini
[RULES]
BASE_MODE=TRACK_DAY
PENALTIES=0
START_TYPE=PIT
ALLOW_PHYSICS_ALTERATIONS=1
AI_LEVEL=100

[TWEAKS]
IMMEDIATE_START=1
HIDE_PITCREW=1
```

Для Phase 0 пользователь добавляет ровно одного opponent той же модели в Content Manager.

### 7.3 State machine playback

```text
IDLE
  -> ARMED when user presses Start chase
ARMED
  -> COUNTDOWN after selected run is loaded and leader is positioned
COUNTDOWN
  -> RUNNING after launch delay
RUNNING
  -> FINISHED at end of recorded frames
FINISHED
  -> COOLDOWN: hide/deactivate leader
COOLDOWN
  -> IDLE: reset clock and wait for the next manual Start chase
```

Лидер не должен телепортироваться на глазах. Между ранами `ac.setCarActive(1, false)` скрывает его; state выставляется до повторной активации.

### 7.4 Sampling

Предлагаемый MVP sampling rate: **50 Hz** с реальным `t` на каждом frame.

Записываем исходные данные, а не вычисляем их повторно при playback:

- timestamp;
- position;
- orientation (лучше quaternion или basis, не только yaw);
- world/local velocity;
- steering/front wheel angle;
- angular speed четырёх колёс;
- tyre slip/spin flags или значения, доступные API;
- engine RPM;
- gear;
- brake/throttle/handbrake;
- brake lights;
- опционально turbo/limiter для audio fidelity.

50 Hz достаточно для плавной cubic/Hermite интерполяции и даёт небольшой размер: типичный 30–45-секундный ран должен занимать от сотен килобайт до примерно 1 MB даже в debug-friendly JSON. После проверки формата можно перейти на компактный binary payload.

Важно: playback идёт по timestamp, а не «один sample на render frame». Это делает результат независимее от FPS.

### 7.5 Формат библиотеки

Предлагаемая структура:

```text
runs/
  <track-id>/
    <layout-id>/
      course.json
      <run-uuid>/
        metadata.json
        frames.bin       # либо frames.json в первой debug-версии
```

`metadata.json`:

```json
{
  "schemaVersion": 1,
  "id": "uuid",
  "name": "Run 2026-08-25 18-42-10",
  "createdAt": "2026-08-25T18:42:10+02:00",
  "trackId": "vdc_bikernieki_2022",
  "layoutId": "drift_vdc",
  "carId": "wdts_nissan_silvia_s15",
  "carDataHash": "optional-later",
  "durationMs": 31740,
  "sampleRateHz": 50,
  "trimStartMs": 800,
  "trimEndMs": 31050,
  "enabled": true
}
```

Трасса и layout — жёсткая совместимость. Car ID в MVP также должен совпадать, потому что положение кузова, wheelbase, steering ratio и visual offsets различаются.

### 7.6 Random policy

Для MVP:

- равномерный выбор среди enabled runs после фильтров;
- каждый выбор независим: мгновенный повтор предыдущего рана разрешён;
- не показывать run ID до конца попытки;
- seed генерируется на старте сессии;
- после финиша показывать ID рана в debug-строке.

## 8. Запись напрямую или через `.acreplay`

### Основной путь: прямая запись

Режим пишет телеметрию во время lead run. Преимущества:

- полный контроль над sample rate и полями;
- мгновенный `Keep/Discard`;
- нет reverse engineering закрытого `.acreplay`;
- нет зависимости от replay quality/frequency пользователя;
- можно сохранять точные start/finish markers и notes.

Обычный AC replay при этом можно продолжать сохранять как видео-доказательство/backup.

### Дополнительный путь: импорт из AC replay

Два варианта после MVP:

1. Lua importer запускается во время просмотра replay, пользователь ставит In/Out, а приложение сэмплирует видимое состояние выбранной машины в наш формат.
2. Внешний parser `.acreplay`, если формат удастся стабильно разобрать или переиспользовать известную реализацию.

Первый вариант безопаснее и дешевле. `ac.ReplayStream()` полезен для данных, которые наше приложение заранее записало в replay, но сам по себе не является универсальным parser существующих `.acreplay`.

## 9. Контакт и физика лидера

Принятая продуктовая политика:

- лидер остаётся state-driven и не отклоняется от записанной траектории;
- физический контакт обязателен и должен передавать impulse машине chase-пилота;
- полноценная физическая модель и setup лидера не воспроизводятся.

Phase 0 обязан проверить боковой контакт, удар в заднее колесо и сильный punt. Если `altonline` не может обеспечить односторонний контакт без сбивания траектории лидера, это блокер выбранного playback backend, а не повод молча перейти на ghost.

## 10. Риски и проверки

| Риск | Почему важен | Как проверяем |
|---|---|---|
| `altonline` недоступен/изменён в CSP build | API новый и слабо документирован | Минимальный mode с одной круговой траекторией |
| Jitter на drift rotation | большие углы, transitions, variable FPS | Запись 50 Hz, quaternion/basis interpolation, slow-motion video |
| Неверная высота/roll/pitch | track raycast может давать ошибки у стен/kerbs | Записывать полный transform; raycast использовать только как fallback |
| Слабый tyre smoke/audio | пример часть полей оценивает | Записывать wheel speeds/slip/RPM, сравнить side-by-side |
| Контакт ведёт себя странно | лидер kinematic/state-driven | Матрица collision tests, configurable collision policy |
| Несовместимость car data | разные geometry/setup/version | car ID + optional data hash, warning/deny playback |
| Большой JSON и pause при загрузке | длинные pools | lazy metadata index, один frames payload в памяти, затем binary |
| Random раскрывается заранее | UI/skin/name могут выдать ран | одинаковая машина/skin, скрытый ID, выбор непосредственно перед arm |
| Leader появляется на глазах | ломает immersion | inactive reposition, activation только перед countdown |

## 11. План реализации

### Phase 0 — feasibility spike

Цель: снять главные неизвестности до строительства UI.

- создать минимальный Track Day New Mode с одним физическим AI-opponent;
- отключить AI-input и подавать hardcoded transform/velocity каждый кадр;
- проиграть hardcoded 15–20 s drift-like trajectory;
- проверить внешний вид, звук, smoke, lights и collision;
- проверить restart/hide/show без перезапуска session;
- записать результаты и минимально поддерживаемую CSP build.

**Exit criteria:** виртуальный лидер стабильно видим и воспроизводится 10 циклов; proximity не даёт заметного jitter; collision policy понятна. Ключевая collision policy подтверждена 2026-08-25; тест visual/audio и десяти циклов остаётся открытым для trajectory, записанной на реальной трассе.

### Phase 1 — vertical slice: record one, chase one

- кнопки manual start/stop recording;
- 50 Hz full-transform frames;
- `Keep/Discard`;
- один JSON-run;
- playback этого run в loop;
- базовое app window с кнопками и диагностикой.

**Exit criteria:** пользователь записывает lead, не выходит из игры и сразу проезжает за ним chase.

### Phase 2 — library и random

Phase 2 начинается только после прохождения Phase 1.5 native playback fidelity spike.

- metadata index;
- список/фильтры/enabled toggle;
- независимый uniform random, включая допустимый immediate repeat;
- скрытие run ID;
- базовый pack и enabled toggle без tags/rating;
- обработка повреждённых/несовместимых файлов.

**Exit criteria:** минимум 20 ранов работают в одной сессии без restart и заметных пауз.

### Phase 3 — polishing

- countdown, reset, skip/restart;
- trim UI;
- debug overlay;
- упаковка для установки через Content Manager.

### Phase 4 — replay import

- In/Out capture app для существующих `.acreplay`;
- выбор car index;
- preview и normalizing metadata;
- только затем оценить внешний direct parser.

### Phase 5 — optional multiplayer/server

Только если возникает реальный use case нескольких chase-клиентов:

- authoritative run selection/time source;
- distribution/cache run data;
- синхронизация virtual leader у клиентов или bot client;
- join-in-progress и version negotiation.

## 12. Критерии готовности MVP

MVP считается полезным, если:

- весь основной loop выполняется in-game;
- запись и playback доступны на любой явно настроенной track layout;
- пользователь может принять/удалить последнюю запись;
- single и random режимы работают без перезапуска AC;
- random pool содержит хотя бы 20 ранов и не раскрывает следующий заранее;
- leader trajectory не расходится более чем на 10 cm между повторными playback в обычных условиях;
- нет заметного jitter рядом с лидером при стабильных 60 FPS;
- reset занимает не больше 5 секунд или настраивается;
- несовместимый track/layout/car никогда не запускается молча;
- повреждённый run пропускается с понятной ошибкой, не ломая сессию.

## 13. Принятые решения

1. Первый target — только offline single-player.
2. Фикстура Phase 0: track/layout VDC Bikernieki и VDC Silvia S14. Это не архитектурное ограничение, а воспроизводимый стенд для проверки координат трассы, visual state машины, дыма, звука и контакта.
3. Физический контакт обязателен и влияет на chase-машину. Лидер остаётся state-driven: его траектория не должна изменяться от контакта, отдельные physics/setup лидера не моделируются.
4. Запись и запуск playback полностью ручные через обычное in-game app window. Hotkeys и start/finish gates не входят в scope.
5. В MVP ран запускается только с тем же car ID, на котором был записан.
6. Random — независимый uniform random; immediate repeat разрешён.
7. После финиша ID рана показывается в debug-строке окна.
8. Tags и rating не входят в MVP.
9. Минимальная поддерживаемая версия на старте — CSP 0.2.11+.

### Неблокирующее решение на потом

Source code находится в этом репозитории. Phase 1 использует runtime-папку `Documents/Assetto Corsa/ac-random-lead-runs/runs/<track>/<layout>/<car>/`. Vertical slice атомарно сохраняет один `latest.json` на комбинацию track/layout/car; Phase 2 заменит это ограничение индексом библиотеки из нескольких ранов.

## 14. Следующий практический шаг

Текущий шаг — Phase 1.5: добавить в существующее окно кнопки native capture/play и проверить официальный `ac.setReplayBasedGhost()` на том же автомобиле. Сначала проверяется live fidelity и collision mode `stiff`, затем отдельно persistence сохранённого рана. Physical teleport backend больше не полируется.

Если replay-based opponent проходит live fidelity, сохраняем текущий in-game workflow и решаем только загрузку базы. Если persistence не проходит, переходим к localhost fake-server/remote-car prototype без переделки recorder, run library и UI.
