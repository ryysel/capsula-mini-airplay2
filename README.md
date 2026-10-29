# AirPlay 2 для VK Капсула Мини на Alpine Linux

Готовые бинарники и установщик AirPlay 2-приёмника для **VK Капсула Мини**
(Amlogic A113X, aarch64) под **Alpine Linux 3.24**.

Внутри: `shairport-sync` 5.6.2 с AirPlay 2 и `nqptp` 1.2.9 (SMI 11), собранные
нативно под musl, плюс конфиг и службы OpenRC. Сторонние glibc/armhf-сборки и
Yandex-обвязка не нужны: зависимости ставятся через `apk` с самого устройства.

Собрано и проверено на VK Капсула Мини: Alpine 3.24.1, kernel 6.18.56,
Amlogic A113X, 4 ядра, ~215 MiB RAM.

## Состав

| Файл | Что это |
|---|---|
| `bin/shairport-sync` | приёмник AirPlay 2 (aarch64, musl) |
| `bin/nqptp` | PTP-демон, обязателен для AirPlay 2 |
| `etc/shairport-sync.conf` | конфиг: имя, порт 7000, вывод на `default` |
| `etc/init.d/nqptp` | служба OpenRC |
| `etc/init.d/shairport-sync` | служба OpenRC |
| `install.sh` | установка одной командой |
| `uninstall.sh` | удаление |
| `build/build.sh` | воспроизводимая сборка (alpine:3.24 + qemu) |
| `BUILD_INFO.txt` | коммиты исходников, `-V`, `ldd`, хеши |
| `SHA256SUMS` | контрольные суммы всех файлов |

## Требования

- Alpine Linux **3.24**, архитектура **aarch64**, root.
- ~30 MiB свободного места и доступ в интернет (для `apk add`).
- Работающий ALSA-выход (`aplay -l` должен видеть карту).
- Для другой версии Alpine или другого дистрибутива сборка не гарантируется:
  бинарники собраны под musl 1.2 и конкретные soname Alpine 3.24.

## Установка

```sh
git clone https://github.com/ryysel/capsula-mini-airplay2.git
cd capsula-mini-airplay2
sh install.sh              # имя по умолчанию: «Капсула Мини»
sh install.sh "Кухня"      # своё имя в AirPlay
```

Скрипт проверяет архитектуру и контрольные суммы, ставит пакеты
(`avahi`, `avahi-tools`, `libplist`, `libsodium`, `libgcrypt`, `libconfig`,
`popt`, `soxr`, `libgomp`, `libuuid`), копирует файлы, включает
`avahi-daemon`, `nqptp` и `shairport-sync` в runlevel `default` и запускает их.

Повторный запуск безопасен: файлы, совпадающие с комплектом, не перезаписываются,
а отличающиеся — не затираются без разрешения.

## Проверка

```sh
rc-service avahi-daemon status
rc-service nqptp status
rc-service shairport-sync status
ss -lntp | grep 7000
ss -lunp | grep -E ':(319|320) '
avahi-browse -rt _airplay._tcp
```

На iPhone: Пункт управления → «Повтор экрана/Звук» → имя колонки.
Если колонки не видно — проверьте, что телефон и колонка в одной сети и что
avahi видит `_airplay._tcp` (см. выше).

## Настройка

`/etc/shairport-sync.conf`:

- `name` — имя в AirPlay;
- `port` — RTSP-порт (по умолчанию 7000);
- `output_device` — ALSA-устройство (по умолчанию `default`);
- `volume_range_db` — диапазон программной громкости.

После правки: `rc-service shairport-sync restart`.

По умолчанию громкость **программная**: телефонный ползунок не переписывает
системный микшер. Если нужен системный микшер, добавьте
`mixer_control_name = "Master Playback Volume"` в секцию `alsa`, но тогда
ползунок iPhone и кнопки/меню будут делить один контрол.

## Удаление

```sh
sh uninstall.sh
```

Останавливает и убирает службы, удаляет бинарники и конфиг. Пакеты `apk` и
`/etc/asound.conf` не трогает.

## Известные ограничения

- Проверено на одном экземпляре Капсулы Мини; другие платы/ядра не тестировались.
- AirPlay 2 требует PTP: без запущенного `nqptp` воспроизведения не будет.
- avahi может писать `not fitting in legacy unicast packet, dropping` для
  `_airplay._tcp`: TXT-запись большая. Multicast-обнаружение при этом работает,
  на практике iPhone колонку видит.
- Если рядом работает Bluetooth-аудио (`bluealsa-aplay`), оно может занять ALSA.
- Иконка и переподключение кэшируются на стороне iOS — это не приёмник.

## Источники и лицензии

- `shairport-sync` 5.6.2, commit `0a34fbda83724cc06266aadcf7c88acc8fef4e7d` —
  https://github.com/mikebrady/shairport-sync
- `nqptp` 1.2.9, commit `ab8fb67483411640fd7f1e193889482f2421c37c` —
  https://github.com/mikebrady/nqptp
- FFmpeg `n7.1.3`, commit `f46e514491172d15bd74b4abb1814cd2f05a763e` —
  https://github.com/FFmpeg/FFmpeg (только AAC/ALAC-декодеры, mov-демуксер,
  статически)
- Сборка: `build/build.sh`, контейнер `alpine:3.24` под qemu-user-static.

Лицензии: `nqptp` — GPL-2.0; FFmpeg — LGPL-2.1+ (в сборке только
LGPL-компоненты); `shairport-sync` — см. `LICENSES`/`COPYING` в его исходниках.
Скрипты и текст этого репозитория — MIT (`LICENSE`).

Бинарники распространяются «как есть», без гарантий. Точные исходники — в
upstream-репозиториях по коммитам выше; `build/build.sh` воспроизводит сборку.
Если нужен архив исходников — откройте issue, выложу.

## Контрольные суммы

```
ce934c9554fe9065e6cf56efa77b1084727897feb7b64f7fe6d296cc4d3d8df4  bin/shairport-sync
46fa1399c3b1bc8f5680fc67959cfb0c1638b1b10e15c454eac5ae56a6504edf  bin/nqptp
```

Полный список — `SHA256SUMS`.

## Исправление значка — v1.0.1

Модель AirPlay изменена с `ShairportSync` на `AudioAccessory5,1`: круглый
значок как у Mini/Lite. Патч: `build/model-icon.patch`. Суффикс `-dirty`
в версии означает эту локальную правку. Имя и настройки звука не меняются.
iOS может кешировать старый значок.

### Обновление с v1.0.0 (root, из нового архива)

`install.sh` намеренно не перезаписывает отличающийся бинарник. Для обновления:

```sh
sha256sum -c SHA256SUMS || exit 1
cp -p /usr/local/bin/shairport-sync /root/shairport-sync.before-v1.0.1
rc-service shairport-sync stop
install -m 0755 bin/shairport-sync /usr/local/bin/shairport-sync
rc-service shairport-sync start
rc-service shairport-sync status
```

Конфиг (включая имя комнаты) сохранится. Для отката остановите службу,
верните `/root/shairport-sync.before-v1.0.1` в `/usr/local/bin/shairport-sync`
и запустите службу снова.
