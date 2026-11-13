# AirPlay 2 для VK Капсул

Готовые приёмники AirPlay 2 для колонок VK: **Капсула 2019** (Rockchip RK3308,
Buildroot) и **Капсула Мини** (Amlogic A113X, Alpine Linux). Один репозиторий,
два пакета; установщик сам определяет колонку.

Внутри — `shairport-sync` 5.6.2 с AirPlay 2 и `nqptp` 1.2.9 (SMI 11), собранные
под конкретную прошивку колонки, плюс конфиг и службы автозапуска. Сторонние
glibc/armhf-сборки и Yandex-обвязка не нужны.

## Установка

```sh
git clone https://github.com/ryysel/capsula-mini-airplay2.git
cd capsula-mini-airplay2
sh install.sh              # имя по умолчанию для этой колонки
sh install.sh "Кухня"      # своё имя в AirPlay
```

`install.sh` проверяет архитектуру и колонку, сверяет `SHA256SUMS`
соответствующего пакета и передаёт управление `packages/<колонка>/install.sh`.
Поддерживаются:

| Колонка | Определение | Пакет |
|---|---|---|
| VK Капсула 2019 | Buildroot + `rk3308` в device tree | `packages/capsula-2019` |
| VK Капсула Мини | `/etc/alpine-release`, aarch64 | `packages/mini-a113x` |

На неподдерживаемом устройстве установщик остановится до любых изменений.

## Что ставится

### Капсула 2019 (RK3308, Buildroot)

Всё в `/data/local`, потому что корневая ФС — squashfs + оверлей:

| Путь | Что |
|---|---|
| `/data/local/capsula-airplay/bin/shairport-sync` | приёмник AirPlay 2 |
| `/data/local/capsula-airplay/bin/nqptp` | PTP-демон (обязателен для AP2) |
| `/data/local/capsula-airplay/etc/shairport-sync.conf` | имя, порт, вывод |
| `/data/local/capsula-airplay/init.d/{nqptp,shairport-sync}` | start/stop/restart |
| `/data/local/bin/capsula-boot` | запуск поздних хуков |
| `/data/local/capsula-boot.d/30-airplay.sh` | хук автозапуска |
| `/data/overlay/upper/usr/bin/voice-agent` | копия `voice-agent` с патчем громкости |

Звук идёт в **PulseAudio**, в тот же sink `master`, которым управляет
`voice-agent`. Громкость у колонки одна — это собственное значение
`voice-agent` (0–100): оно двигает sink, кольцо-индикатор, сохранённые
настройки и состояние в приложении VK. Приёмник не трогает sink сам, а
передаёт громкость AirPlay в `stereoctl` сообщением `OnSetVolumeRequest` —
`voice-agent` применяет её нативно. В обратную сторону, когда громкость
меняют кнопками колонки, `shairport-sync` сообщает новое значение
отправителю, поэтому ползунок на телефоне едет вместе с кольцом.

Для этого нужен патч `voice-agent` (`voice-agent-volume-patch.sh`). В стоке
обработчик `OnVolumeChangedEvent` применяет событие только с флагом `remote`,
а всё, что приходит через локальный сокет `stereoctl`, помечено `remote=0`.
Патч заменяет две проверки на «всегда истина» (8 байт) в копии бинаря в
оверлее; сток в squashfs не меняется, откат — удалить файл.

**Автозапуск.** Штатный `rcS` разворачивает `/etc/init.d/S??*` до того, как
`S23overlayfs.sh` смонтирует оверлей, поэтому новые `S*`-скрипты в оверлее
никогда не запускаются. Установщик добавляет вызов `capsula-boot` в копию
обёртки `/usr/bin/voice-agent.sh` в оверлее — она стартует уже после
монтирования. Оригинал остаётся в squashfs, откат — `uninstall.sh`.

### Капсула Мини (A113X, Alpine)

Обычная установка в систему: `bin/`, конфиг `/etc/shairport-sync.conf`,
службы OpenRC `/etc/init.d/{nqptp,shairport-sync}`, зависимости через `apk`.
Вывод — ALSA `default` (softvol поверх микшера твикера).

## Проверка

Общее:

```sh
ss -lntp | grep 7000
ss -lunp | grep -E ':(319|320) '
```

Капсула 2019:

```sh
pidof nqptp shairport-sync
/data/local/capsula-airplay/init.d/shairport-sync status
netstat -ln | grep 7000
```

Единая громкость проверяется так: значение `voice-agent` и громкость sink
должны меняться вместе, а ползунок телефона — следовать за кнопками колонки.

```sh
grep master_volume /data/voice-agent/device_settings.json
pactl get-sink-volume master
```

Вывод `shairport-sync` в syslog в этой сборке отключён. Подробный лог — только
ручным запуском (службу на это время остановить):

```sh
/data/local/capsula-airplay/init.d/shairport-sync stop
/data/local/capsula-airplay/bin/shairport-sync \
    --configfile=/data/local/capsula-airplay/etc/shairport-sync.conf -v
```

Мини:

```sh
rc-service nqptp status
rc-service shairport-sync status
avahi-browse -rt _airplay._tcp
```

На iPhone: Пункт управления → «Повтор экрана/Звук» → имя колонки.
Если колонки не видно — проверьте, что телефон и колонка в одной сети.

## Настройка

`shairport-sync.conf`:

- `name` — имя в AirPlay;
- `port` — RTSP-порт (по умолчанию 7000);
- `output_backend` — `pulseaudio` на 2019, `alsa` на Мини;
- `volume_range_db` — диапазон громкости, по умолчанию 30 дБ. Не поднимать
  выше 30: при большем значении `shairport-sync` переходит в режим
  «software priority» и отдаёт в колонку 0 дБ (полную громкость), гася
  звук программно — ползунок телефона перестаёт влиять на колонку.

После правки: `init.d/shairport-sync restart` (2019) или
`rc-service shairport-sync restart` (Мини).

## Сборка

Бинарники собраны под конкретную прошивку, поэтому сборка у каждого пакета
своя:

| Пакет | Как собрано |
|---|---|
| Мини | `build/build-mini.sh` — нативно в Alpine 3.24 aarch64 (musl) |
| 2019 | `build/build-2019.sh` — кросс-сборка в Debian bullseye (glibc 2.31 → 2.33), `build/Dockerfile` |

Для 2019 внутри образа `capsula-2019-airplay-builder`:

```sh
docker build -t capsula-2019-airplay-builder -f build/Dockerfile build
docker run --rm -v "$PWD":/work -w /work capsula-2019-airplay-builder \
    bash build/build-2019.sh
```

Результат — `out/shairport-sync`, `out/nqptp`, `out/BUILD_INFO.txt`.
Статически линкуются libconfig, popt, soxr, libsodium, libgpg-error,
libgcrypt, libplist и ffmpeg (только AAC/ALAC); динамически — libc,
libavahi-client, libpulse, libuuid, libssl/libcrypto, которые уже есть в
прошивке.

## Откат

- 2019: `sh packages/capsula-2019/uninstall.sh`, затем перезагрузка
  (удаляет и патч `voice-agent`, возвращая сток).
- Мини: `sh packages/mini-a113x/uninstall.sh`.

## Ограничения

- Прошивки 2019 и Мини обновляются только вместе с пакетом: бинарники
  привязаны к libc и библиотекам конкретной сборки.
- На 2019 OTA отключён, поэтому обновление прошивки не подменит библиотеки
  незаметно; при включении OTA пакет нужно пересобрать.
- AirPlay 2 и `voice-agent` делят один звуковой сервер: во время AirPlay
  голосовые ответы Маруси будут звучать поверх/вместо музыки.
- Патч `voice-agent` привязан к прошивке 44.90: установщик сверяет
  SHA-256 стокового бинаря и отказывается патчить незнакомую сборку.
  После установки или обновления пакета нужна одна перезагрузка —
  оверлей и патченный `voice-agent` подхватываются при старте.
- Холодная загрузка 2019 с автозапуском проверяется отдельно (см. журнал
  проекта).

## Лицензии

`shairport-sync` — GPL-2.0-or-later, `nqptp` — GPL-2.0-or-later, FFmpeg —
LGPL-2.1-or-later (сборка только декодеров). Подробности в `NOTICE.md`.
