# Localhost playback backend

Status: accepted runtime backend

Pinned AssettoServer: `6ce86addc1b1c70caf018a7b39f6d7bc9aa9493f` (`v0.0.55-pre35`).

`RandomLeadServerPlugin` загружает совместимую библиотеку, управляет playback state и публикует synthetic leader через обычные Assetto Corsa network position packets. Так используется нативный remote-car renderer вместо попытки анимировать или физически телепортировать вторую машину из Lua.

## Подтверждено

- правильная высота кузова;
- suspension movement;
- плавная траектория и вращение/выворот колёс;
- engine RPM audio;
- chase car получает collision impulse;
- лидер остаётся на записи после контакта.

Tyre smoke отсутствует и отложен.

## API

- `GET /api/random-lead/status`;
- `POST /api/random-lead/command/current`;
- `POST /api/random-lead/command/next`;
- `POST /api/random-lead/command/random`;
- `POST /api/random-lead/command/restart`;
- `POST /api/random-lead/command/stop`.

API принимает команды только с loopback-интерфейса. CSP app опрашивает status до 10 раз в секунду во время диагностического playback; random selection скрыт до завершения попытки.

## Build и fixture

```powershell
.\tools\build-server-plugin.ps1
.\tools\start-localhost-test.ps1
```

Generated configuration, plugin copy и логи находятся в ignored `.runtime/localhost-server`.

## Distribution boundary

AssettoServer распространяется под AGPL-3.0. Репозиторий использует ignored source checkout и не включает AssettoServer binaries. Публичная упаковка должна явно выбрать AGPL-compatible arrangement.

Pinned upstream сейчас сообщает advisories для `Scriban 6.6.0`. Fixture остаётся localhost-only; packaging заблокирован до обновления зависимости или отдельной оценки риска.
