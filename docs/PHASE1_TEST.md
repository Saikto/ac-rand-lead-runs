# Phase 1 manual test — record one, chase one

## Подготовка

- CSP: 0.2.11 build 3465 или новее.
- New Mode: `AC Random Lead Runs — Phase 1`.
- Один AI-opponent той же модели, что и машина игрока.
- Открытое окно `Random Lead Runs — Phase 1`.

Phase 1 хранит один последний принятый ран отдельно для каждой комбинации track/layout/car. Файл находится в:

`Documents\Assetto Corsa\ac-random-lead-runs\runs\<track>\<layout>\<car>\latest.json`

## Основной сценарий

1. Нажать `Start recording` и проехать короткий lead run продолжительностью 5–15 секунд.
2. Нажать `Stop recording`.
3. Убедиться, что статус стал `review`, а количество samples примерно равно duration × 50.
4. Нажать `Keep run`.
5. Убедиться, что статус стал `saved`, `Saved: yes`, а `latest.json` появился по пути из Diagnostics.
6. Вернуться своей машиной к месту начала записанного рана.
7. Нажать `Play saved run` и проехать chase за лидером.
8. Убедиться, что лидер проходит по реальной записанной линии и высоте поверхности, а после конца исчезает со статусом `completed`.
9. Повторить playback несколько раз и проверить детерминированность и контакт.
10. Перезапустить сессию и убедиться, что сохранённый ран загружается автоматически.

## Discard

1. Записать второй короткий ран.
2. После Stop нажать `Discard run`.
3. Убедиться, что pending run исчез, а ранее сохранённый ран по-прежнему доступен для Play.

## Что фиксировать

| Check | Result | Notes |
|---|---|---|
| Recording starts/stops from UI | Да |  |
| 50 Hz sample count | Samples увеличиваются, выглядит нормально |  |
| Keep writes latest.json | Да |  |
| Discard preserves previous saved run | Да |  |
| Saved run reloads after session restart | Да |  |
| World-space route and height | Путь нормальный, высоты нормальные |  |
| Orientation and steering | машина едет задом наперёд, и колёса статичны, передние точно не поворачиваются и видимо не крутятся  |  |
| Wheels, smoke and engine audio | Колёса статичны, передние точно не поворачиваются и видимо не крутятся, как будто машину с заблокированными колёсами тащат, идёт мелкий дым из колёс |  |
| Chase receives collision impulse | Да |  |
| Leader remains deterministic after contact | Да |  |
| Repeated playback stability | Несколько раз нажимал, вроде проигрывалось одно и то же |  |

Если появляется `Status: error`, достаточно сообщить «посмотри логи». Ошибка также записывается в `Documents\Assetto Corsa\logs\custom_shaders_patch.log`.

## Playback visual follow-up — v0.1.1

По первому тесту data lifecycle, маршрут, высота, persistence, collision policy и повторяемость прошли. Для повторной проверки v0.1.1:

- направление, передаваемое в physical teleport, инвертировано относительно записанного `CarState.look`;
- формат v2 записывает angular speed всех четырёх колёс;
- playback задаёт wheel angular speed и engine RPM каждый frame;
- сохранённые v1-раны остаются читаемыми и получают расчётную wheel speed, но точная проверка visual state выполняется на заново записанном v2-ране.

## Playback visual/audio follow-up — v0.1.2

Файл v2 подтвердил корректные исходные данные steer, wheel angular speed и RPM. В v0.1.2:

- `physics.overrideSteering()` получает steering wheel angle в градусах, а `overrideCarControls.steer` — отдельное нормализованное значение;
- engine sound воспроизводится отдельным 3D FMOD `engine_ext` event из soundbank текущей машины, поскольку parked AI не запускает штатный engine event;
- Diagnostics показывает target/actual для steer, FL wheel speed и RPM, а также статус custom engine audio.

Результат проверки:

- live `engine_ext` audio — pass; RPM на слух соответствует записанному;
- направление кузова — pass;
- steering amplitude стала заметно больше, точность визуально пока не подтверждена;
- кузов лидера выглядит ниже такой же player car, колёса частично входят в арки;
- визуальное вращение колёс выглядит отсутствующим либо слишком медленным;
- в сохранённом AC replay передние колёса лидера сильно дёргаются, custom engine audio отсутствует.

Проверка исходного v2 JSON показала плавный target steering (95% изменений между 50 Hz samples меньше 0.031), среднюю wheel angular speed 22.2 rad/s и максимум 42.5 rad/s. Следовательно, оставшиеся дефекты возникают после recorder — в physical teleport/suspension/render/replay backend.

### Ride-height diagnostic — v0.1.3

В Diagnostics добавлен `Leader height offset` от −5 до +15 cm. Он смещает physical target вдоль записанного up-вектора и предназначен для A/B-проверки занижения. Если увеличение offset не меняет положение колёс относительно арок, дефект находится во внутреннем suspension reset и не исправляется простым transform offset.

### Automatic playback logger — v0.1.4

Каждый playback автоматически пишет 10 Hz CSV в `Documents/Assetto Corsa/ac-random-lead-runs/logs/`. Лог сохраняется раз в секунду и при Stop/completion. В нём есть target/actual steering, angular speed всех колёс, RPM, position error, ride height, ground distance, suspension travel, height offset и audio status. `tools/analyze-playback-log.ps1` автоматически анализирует последний файл.

Результат A/B-теста 0/5/10/15 cm:

- front ride height остался около 119 mm, rear — около 114 mm во всех четырёх прогонах;
- position error без первого reset sample вырос с 14.5 cm до 24.5 cm, то есть CSP принял отличающийся target, но выровнял автомобиль обратно на поверхность;
- FL wheel target/actual в прогоне +15 cm: 14.85/12.68 rad/s;
- RL wheel target/actual: 29.66/1.30 rad/s — причина визуально медленного заднего колеса подтверждена;
- engine target/actual: 5361/7 RPM — штатная физика перетирает RPM, слышимый live звук создаёт только custom FMOD event;
- steering actual расходится с target и насыщается на ±450°.

Вывод: recorder содержит нужные данные, но per-frame physical teleport не является пригодным production playback backend. Дальнейшее решение и Phase 1.5 описаны в `PLAYBACK_BACKEND_DECISION.md`.

## Phase 1.5 native replay spike — v0.2.0

Новый блок `Phase 1.5 native replay spike` не использует сохранённый JSON и не телепортирует physical leader. Он берёт короткий отрезок из rolling replay текущей AC-сессии и передаёт его нативному replay-based opponent с collision mode `stiff`.

1. Убедиться, что строка `Native API` показывает `available: native replay and collision API`.
2. Нажать `Start native capture`.
3. Проехать lead продолжительностью 10–20 секунд.
4. Нажать `Stop native capture`.
5. Вернуться своей машиной к началу проезда.
6. Нажать `Play native capture (stiff)`.
7. Проверить высоту кузова, работу подвески, steering, вращение всех колёс, дым и звук.
8. Сделать лёгкий контакт и сильный punt: chase должен получить импульс, а leader — продолжить записанный проезд.
9. Повторить playback несколько раз и затем сохранить обычный AC replay для проверки его visual/audio fidelity.

Если `Native API` показывает `unavailable`, скопировать status details. Если playback падает после доступного API, status details будет содержать runtime error и рассчитанный rewind offset.

Ограничение этого spike: capture живёт только в rolling replay текущей сессии. Persistence библиотеки проверяется отдельным следующим шагом только после прохождения visual/contact теста.
