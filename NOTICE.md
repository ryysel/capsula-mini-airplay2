# Лицензии и происхождение бинарников

Репозиторий содержит предсобранные бинарники под две колонки:
`packages/mini-a113x` (aarch64/musl, Alpine 3.24) и
`packages/capsula-2019` (aarch64/glibc 2.33, Buildroot). Они не написаны
автором репозитория и распространяются на условиях их собственных лицензий.

## shairport-sync

- Версия: `5.6.2-dirty-AirPlay2-smi11-OpenSSL-Avahi-…-soxr-…`
- Исходник: https://github.com/mikebrady/shairport-sync
- Коммит: `0a34fbda83724cc06266aadcf7c88acc8fef4e7d`
- Условия: см. `COPYING` и `LICENSES` в дереве исходников; часть файлов имеет
  собственные лицензии (например, ALAC-код David Hammerton).

## nqptp

- Версия: `1.2.9`, Shared Memory Interface `smi11`
- Исходник: https://github.com/mikebrady/nqptp
- Коммит: `ab8fb67483411640fd7f1e193889482f2421c37c`
- Лицензия: GNU General Public License v2 (см. `LICENSE` в исходниках).

## FFmpeg (статически слинкован в shairport-sync)

- Версия: `n7.1.3`
- Исходник: https://github.com/FFmpeg/FFmpeg
- Коммит: `f46e514491172d15bd74b4abb1814cd2f05a763e`
- Лицензия: LGPL-2.1+ (`LICENSE.md` в исходниках). Сборка выполнена с
  `--disable-everything` и включает только LGPL-компоненты: декодеры AAC и
  ALAC, парсер AAC.

## Статически слинкованные библиотеки (только пакет 2019)

| Библиотека | Версия | Лицензия |
|---|---|---|
| libconfig | 1.7.3 | LGPL-2.1+ |
| popt | 1.19 | MIT |
| soxr | 0.1.3 | LGPL-2.1+ |
| libsodium | 1.0.19 | ISC |
| libgpg-error | 1.49 | LGPL-2.1+ |
| libgcrypt | 1.10.3 | LGPL-2.1+ |
| libplist | 2.3.0 | LGPL-2.1+ |

Динамически пакет 2019 использует только те библиотеки, что уже есть в
прошивке колонки: libc, libm, libpthread, libdl, libavahi-client,
libpulse, libuuid, libssl/libcrypto.

## Воспроизведение сборки

- Мини: `build/build-mini.sh` — контейнер `alpine:3.24` под qemu-user-static.
- 2019: `build/Dockerfile` + `build/build-2019.sh` — Debian bullseye,
  кросс-компиляция `aarch64-linux-gnu-gcc` (glibc 2.31 → запускается на 2.33).

Файлы `BUILD_INFO.txt` / `out/BUILD_INFO.txt` фиксируют коммиты, вывод `-V`,
`NEEDED`, максимальные версии символов glibc и SHA256.

## Исходники

Точные исходники доступны в upstream-репозиториях по коммитам выше. Если нужен
архив исходников, соответствующий этим бинарникам, — откройте issue в этом
репозитории, архив будет выложен.

## Отказ от гарантий

Бинарники предоставляются «как есть», без каких-либо гарантий. Установка
выполняется на свой риск.

## Исправление значка — v1.0.1

Модель AirPlay изменена с `ShairportSync` на `AudioAccessory5,1`: круглый
значок как у Mini/Lite. Патч: `build/model-icon.patch` (применяется в обоих
сборочных скриптах). Суффикс `-dirty` в версии означает эту локальную правку.
Имя и настройки звука не меняются. iOS может кешировать старый значок.
