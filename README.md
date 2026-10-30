# AirPlay 2 для VK Капсула Мини на Alpine Linux

Готовые бинарники и установщик AirPlay 2-приёмника для **VK Капсула Мини**
(Amlogic A113X, aarch64) под **Alpine Linux 3.24**.

Внутри: `shairport-sync` 5.6.2 с AirPlay 2, D-Bus-управлением и `nqptp` 1.2.9
(SMI 11), собранные нативно под musl, плюс конфиг, службы OpenRC и
двусторонняя громкость для колонок с `capsule-mini-tweaker`.

**Это не прошивальщик.** Нужна уже работающая Alpine **3.24/aarch64**, root SSH,
ALSA `default` и не менее 30 MiB свободного места.

## Состав

| Файл | Что это |
|---|---|
| `bin/shairport-sync` | приёмник AirPlay 2 (aarch64, musl, D-Bus) |
| `bin/nqptp` | PTP-демон, обязателен для AirPlay 2 |
| `bin/capsule-ipc` | клиент к IPC твикера |
| `bin/ap2ctl` | status/active/pause/play/next/prev/volume/percent |
| `bin/ap2-volume-sync` | телефон → Master |
| `bin/ap2-bridge` | Master → телефон, native-first |
| `etc/shairport-sync.conf` | конфиг: имя, порт 7000, вывод на `default` |
| `etc/init.d.*` | службы OpenRC |
| `etc/dbus-policy.conf` | policy для имени `org.gnome.ShairportSync` |
| `install.sh` / `uninstall.sh` | установка/удаление |
| `build/` | рецепт сборки, патч модели, BUILD_INFO |
| `SHA256SUMS` | контрольные суммы всех файлов |

## Установка

```sh
git clone https://github.com/ryysel/capsula-mini-airplay2.git
cd capsula-mini-airplay2
sh install.sh --check        # только проверка
sh install.sh                # имя из /etc/hostname
sh install.sh --name 'Кухня' # своё имя
sh install.sh --upgrade      # обновление с backup, имя сохраняется
```

На Windows: распакуйте архив релиза и запустите **Install-Windows.cmd**.
Мастер проверит SHA256, найдёт кандидатов (USB-адрес `192.168.14.14` и
устройства из ARP с открытым SSH), спросит порт/ключ и имя (Enter = hostname),
покажет preflight и попросит `INSTALL`. Подробности — `docs/WINDOWS.md`.

Повторный запуск безопасен: файлы, совпадающие с комплектом, не перезаписываются,
а отличающиеся — только с `--upgrade` (старые файлы, `apk world` и runlevels
сохраняются в `/root/airplay2-backup-XXXXXXXX`).

## Управление и громкость

- D-Bus (system bus): `GetControlStatus`, `RemoteControl.Pause/Play/Next/Previous`,
  `SetAirplayVolume`, свойства `Available/Client/AirplayVolume/PlayerState`.
- Если на колонке работает `capsule-mini-tweaker` (есть
  `/run/capsule-controls.sock`), установщик включает `ap2-bridge` и
  `ignore_volume_control`: телефон меняет Master через IPC твикера (в том числе
  до начала воспроизведения), кнопки публикуются в телефон. На старте сессии сначала отправляется текущий уровень
  (native-first), поэтому громкость не прыгает до ползунка телефона.
- Без твикера мост не устанавливается, приёмник работает с собственной
  программной громкостью.
- Проверить из SSH: `ap2ctl status`, `ap2ctl active`, `ap2ctl pause`.

Задержка «кнопка → телефон» до 1 секунды (период опроса моста).

## Проверка

```sh
rc-service shairport-sync status
rc-service nqptp status
rc-service avahi-daemon status
rc-service ap2-bridge status      # если установлен твикер
ss -lntp | grep 7000
avahi-browse -rt _airplay._tcp
```

UDP 319/320 — PTP, TCP 7000 — приёмник, UDP 5353 — mDNS. `OPTIONS 200` и анонс
не доказывают звук: проверьте воспроизведение, громкость в обе стороны,
паузу, reconnect и мультирум с iPhone.

## Ограничения

- Только Alpine 3.24 / aarch64; другие версии и дистрибутивы не проверялись.
- AirPlay 2 требует PTP: без `nqptp` звука не будет.
- Модель `AudioAccessory5,1` (круглый значок как у Mini/Lite) — локальный патч,
  версия `-dirty`; бит-в-бит воспроизведение не обещается.
- avahi может писать `not fitting in legacy unicast packet` — multicast работает.
- Bluetooth-аудио (`bluealsa-aplay`) может занять ALSA.
- iOS кеширует имя/иконку.

## Удаление

```sh
sh uninstall.sh
```

Останавливает и убирает службы, удаляет бинарники, конфиг и D-Bus policy.
APK и `/etc/asound.conf` не трогает.

## Источники и лицензии

- `shairport-sync` 5.6.2, commit `0a34fbda83724cc06266aadcf7c88acc8fef4e7d`
  (https://github.com/mikebrady/shairport-sync) + патчи
  `shared-controls`, `dacp-ipv4-discovery`, `preplay-event-channel` из
  `Yandex-Station-Universal-Repo/Station-airplay` `1a11fd13c7ee`.
- `nqptp` 1.2.9, commit `ab8fb67483411640fd7f1e193889482f2421c37c`.
- FFmpeg `n7.1.3`, commit `f46e514491172d15bd74b4abb1814cd2f05a763e`
  (только AAC/ALAC, статически).

Лицензии: `nqptp` — GPL-2.0; FFmpeg — LGPL-2.1+; `shairport-sync` — см.
`LICENSES`/`COPYING` upstream. Наши скрипты и текст — MIT (`LICENSE`).
Бинарники — «как есть», без гарантий. Архив исходников — по запросу через issue.

## Контрольные суммы

Полный список — `SHA256SUMS`.
