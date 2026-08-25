# AC Random Lead Runs

Offline-тренажёр chase-заездов для оригинальной Assetto Corsa с Custom Shaders Patch.

Идея: записывать собственные lead runs, собирать из удачных проездов библиотеку и запускать их по одному или случайно, не зная заранее траекторию следующего лидера.

Текущее состояние: Phase 1.5 — запись/Keep/Discard работают; physical teleport признан недостаточно качественным, добавляется A/B spike нативного CSP replay-based leader. Основные документы:

- [PRD и технический план](docs/PRD.md)
- [Инструкция ручной проверки Phase 0](docs/PHASE0_TEST.md)
- [Инструкция ручной проверки Phase 1](docs/PHASE1_TEST.md)
- [Решение о смене playback backend](docs/PLAYBACK_BACKEND_DECISION.md)
- [Localhost remote-car backend spike](docs/SERVER_BACKEND_SPIKE.md)
