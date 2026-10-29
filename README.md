# AirPlay 2 для VK Капсула Мини — Alpine 3.24 / aarch64

Предсобранные shairport-sync 5.6.2 + nqptp 1.2.9 (SMI11), статический FFmpeg
n7.1.3 AAC/ALAC, конфиг и OpenRC. Модель `AudioAccessory5,1` даёт значок
круглой колонки как у Mini/Lite. Изменение модели: `build/model-icon.patch`.

**Это не прошивальщик.** Нужна уже работающая Alpine **3.24/aarch64**, root SSH,
ALSA `default` и не менее 30 MiB свободного места. Только Amlogic A113X;
стоковая ОС, Rockchip и другие версии Alpine не квалифицированы.

## Windows — пошаговый мастер

Скачайте и распакуйте архив релиза, запустите **Install-Windows.cmd**.
Мастер проверит SHA256, спросит адрес/порт/ключ, покажет SSH preflight и
попросит подтверждение `INSTALL`. OpenSSH не отключает проверку host key,
пароли и ключи в комплект не входят. Подробности/откат: [docs/WINDOWS.md](docs/WINDOWS.md).

Windows-мастер экспериментальный: синтаксис, локальный комплект и mock-сценарий
проверяются отдельно от реальной установки Windows → колонка.

## Установка из SSH

```sh
sh install.sh --check                     # только preflight, без изменений
sh install.sh                             # новая установка: имя из /etc/hostname
sh install.sh --upgrade                    # обновление с backup, старое имя сохраняется
sh install.sh --upgrade --hostname         # явно взять текущее /etc/hostname
sh install.sh --upgrade --name 'My Speaker' # своё имя
```

Имя hostname читается **на колонке**, не на ПК, и фиксируется в конфиге при
установке. Перезапись `/etc/hostname` и автоматический ребинд кнопок не делаются.
Настройки звука, Wi-Fi и конфиг твикера не меняются. На время обновления
останавливаются только shairport-sync и nqptp.

Если существующий бинарник отличается, без `--upgrade` установка откажет.
При upgrade старые файлы, список APK world и runlevels сохраняются в
`/root/airplay2-backup-XXXXXXXX` (700). Автоматического полного отката нет;
инструкция в [docs/WINDOWS.md](docs/WINDOWS.md).

## Проверка и настройка

```sh
rc-service shairport-sync status
rc-service nqptp status
rc-service avahi-daemon status
avahi-browse -rt _airplay._tcp
```

UDP 319/320 — PTP, TCP 7000 — приёмник, UDP 5353 — mDNS. Телефон должен быть
в той же доверенной LAN. `OPTIONS 200` и наличие анонса не доказывают звук:
проверьте воспроизведение, громкость, паузу, reconnect и мультирум с iPhone.

Конфиг: `/etc/shairport-sync.conf`; после ручной правки —
`rc-service shairport-sync restart`. Выход `default`, 48 кГц/S16/стерео.
Громкость пока программная: телефон и Master — **два независимых уровня**,
а не синхронизация. Если Master почти нулевой, телефонный ползунок не спасёт.
Bluetooth может занять ALSA. iOS может кешировать имя/иконку.

`sh uninstall.sh` удаляет бинарники и конфиг; предварительно сохраните свои
настройки. APK и `/etc/asound.conf` не удаляются.

## Кнопки, синхронизация и функции Алисы

[Полный разбор переноса](docs/FEATURES.md),
[обновления сообщества](docs/UPDATES_20261030.md).
`triggerhappy + mpc` не управляет AirPlay на iPhone. Твикер уже захватывает
кнопки; параллельный обработчик не устанавливается. Транспорт, двусторонняя
громкость, голосовые команды и индикация из Station-airplay ещё **не перенесены**.

## Исходники и контроль целостности

Пины, версии и SHA256 — `build/BUILD_INFO.txt`, полный комплект — `SHA256SUMS`.
Рецепт `build/build.sh` запускается в arm64-контейнере Alpine 3.24 с каталогами
`/work` и `/out` (на x86 нужен qemu/binfmt). Бит-в-бит идентичность пересборки
не обещается: образ и APK-версии не зафиксированы digest-ами.

* shairport-sync: https://github.com/mikebrady/shairport-sync, commit
  `0a34fbda83724cc06266aadcf7c88acc8fef4e7d` + локальный model patch.
* nqptp: https://github.com/mikebrady/nqptp, commit
  `ab8fb67483411640fd7f1e193889482f2421c37c`.
* FFmpeg: https://github.com/FFmpeg/FFmpeg, commit
  `f46e514491172d15bd74b4abb1814cd2f05a763e`.

Скрипты/текст — MIT; бинарники сохраняют лицензии upstream, см. `NOTICE.md`.
Предоставляется без гарантий. SHA256 защищает от повреждения архива,
но не заменяет проверку доверия к источнику загрузки.
