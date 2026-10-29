# Лицензии и происхождение бинарников

Репозиторий содержит два предсобранных бинарника для aarch64/musl. Они не
написаны автором репозитория и распространяются на условиях их собственных
лицензий.

## shairport-sync

- Версия: `5.6.2-dirty-AirPlay2-smi11-OpenSSL-Avahi-ALSA-soxr-metadata-sysconfdir:/etc`
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
  ALAC, парсер AAC, демуксер mov, протокол file.

## Воспроизведение сборки

`build/build.sh` — полный рецепт: контейнер `alpine:3.24` под
qemu-user-static, установка `-dev`-пакетов, сборка FFmpeg, nqptp и
shairport-sync с `--with-airplay-2`. Файл `BUILD_INFO.txt` фиксирует коммиты,
вывод `-V`, `ldd` и SHA256.

## Исходники

Точные исходники доступны в upstream-репозиториях по коммитам выше. Если нужен
архив исходников, соответствующий этим бинарникам, — откройте issue в этом
репозитории, архив будет выложен.

## Отказ от гарантий

Бинарники предоставляются «как есть», без каких-либо гарантий. Установка
выполняется на свой риск.

## Исправление значка — v1.0.1

Модель AirPlay изменена с `ShairportSync` на `AudioAccessory5,1`: круглый
значок как у Mini/Lite. Патч: `build/model-icon.patch`. Суффикс `-dirty`
в версии означает эту локальную правку. Имя и настройки звука не меняются.
iOS может кешировать старый значок.
