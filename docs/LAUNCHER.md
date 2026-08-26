# Local browser launcher

Launcher заменяет ручной запуск PowerShell fixture и редактирование INI. Он работает только на loopback-интерфейсе и открывается командой:

```powershell
.\tools\start-launcher.ps1
```

Окно PowerShell остаётся открытым на всё время работы launcher. Закрытие через `Ctrl+C` останавливает и управляемый им server process.

## Экраны

### Run library

Показывает валидные v1/v2/v3 recordings из `Documents\Assetto Corsa\ac-random-lead-runs\runs`, дедуплицируя `latest.json`. Выбранный ран определяет трассу, layout, leader car и совместимую библиотеку playback.

### Session setup

- chase car и skin из установленного AC content;
- server name;
- установленный weather preset;
- ambient и road temperature;
- sun angle;
- start/loop delays и loop toggle;
- AC TCP/UDP port.

HTTP port пока зафиксирован на `8081`, потому что к нему подключается in-game CSP app.

### Launch & status

Launcher сохраняет профиль в ignored `.runtime\launcher\settings.json`, генерирует отдельный fixture `.runtime\launcher-server`, собирает актуальный plugin и запускает AssettoServer без дополнительного консольного окна. Экран показывает состояния `starting`, `ready`, `stopped`, `error`, live output, Stop и CM invite link.

## Ограничения первой версии

- каталог сканируется при запуске launcher; для новых recordings launcher пока нужно перезапустить;
- один выбранный chase car, а не список открытых player slots;
- нет enabled/delete/metadata management;
- первый Start включает сборку server plugin и поэтому занимает несколько секунд;
- публичная упаковка в standalone executable ещё не выполнена.
