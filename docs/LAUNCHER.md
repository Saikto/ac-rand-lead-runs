# Local browser launcher

Launcher заменяет ручной запуск PowerShell fixture и редактирование INI. Он работает только на loopback-интерфейсе и открывается командой:

```powershell
.\tools\start-launcher.ps1
```

Окно PowerShell остаётся открытым на всё время работы launcher. Закрытие через `Ctrl+C` останавливает и управляемый им server process.

## Экраны

### Run library

Показывает валидные v1/v2/v3 recordings из `Documents\Assetto Corsa\ac-random-lead-runs\runs`, дедуплицируя `latest.json`. Выбранный ран определяет трассу, layout, leader car и совместимую библиотеку playback. Строка поиска фильтрует библиотеку по track, layout, leader car и run ID.

### Session setup

- chase car и skin из установленного AC content, с текстовыми фильтрами;
- server name;
- установленный weather preset с текстовым фильтром;
- температура воздуха и нагрев асфальта относительно воздуха (`BASE_TEMPERATURE_ROAD` в AC — это прибавка, а не абсолютная температура);
- время суток и скорость его течения;
- скорость/направление ветра и стартовый grip трассы;
- режимы TC/ABS, stability control и auto clutch;
- damage, fuel, tyre wear и tyre blankets;
- start/loop delays и loop toggle;
- AC TCP/UDP port.

Время ограничено диапазоном 08:00–18:00, который соответствует поддерживаемому launcher диапазону `SUN_ANGLE` от −80° до +80°. Например, air `18 °C` и road heating `+6 °C` дают фактическую температуру асфальта `24 °C`.

HTTP port пока зафиксирован на `8081`, потому что к нему подключается in-game CSP app.

### Launch & status

Launcher сохраняет профиль в ignored `.runtime\launcher\settings.json`, генерирует отдельный fixture `.runtime\launcher-server`, собирает актуальный plugin и запускает AssettoServer без дополнительного консольного окна. Экран показывает состояния `starting`, `ready`, `stopped`, `error`, live output, Stop и CM invite link.

`Stop` завершает и wrapper, и принадлежащий launcher процесс AssettoServer, после чего освобождаются порты и plugin DLL. При следующем Start launcher также убирает оставшийся процесс именно своей сборки AssettoServer на выбранных портах. Если порт занят другим приложением, проверка завершается понятной ошибкой до сборки и копирования DLL.

## Ограничения первой версии

- каталог сканируется при запуске launcher; для новых recordings launcher пока нужно перезапустить;
- один выбранный chase car, а не список открытых player slots;
- нет enabled/delete/metadata management;
- первый Start включает сборку server plugin и поэтому занимает несколько секунд;
- публичная упаковка в standalone executable ещё не выполнена.
