# AC Random Lead Runs

Тренажёр chase-заездов для оригинальной Assetto Corsa с Custom Shaders Patch.

Проект записывает собственные lead runs в offline Recorder mode и воспроизводит выбранного или случайного лидера через локальный AssettoServer. Управление записью и playback выполняется из одного resizeable in-game app window без хоткеев.

Текущее состояние:

- постоянная JSON-библиотека ранов;
- ручные Start/Stop/Keep/Discard;
- current/next/random/restart/stop playback;
- нативный remote-car renderer, engine audio и односторонний контакт;
- tyre smoke и автоматическая упаковка пока не реализованы.

Документы:

- [PRD и актуальная архитектура](docs/PRD.md)
- [Запуск и ручная проверка](docs/LOCALHOST_TEST.md)
- [Принятый playback backend](docs/PLAYBACK_BACKEND.md)

## Локальная установка

```powershell
.\tools\install.ps1
```

После первой установки включи app `Random Lead Runs` в Content Manager. Для записи выбери New Mode `AC Random Lead Runs — Recorder`; для chase запусти localhost server по инструкции ниже.
