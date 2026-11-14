# AirPlay 2 на Капсуле Мини с родной прошивкой

Пакет `packages/mini-stock/` ставит AirPlay 2 на стоковую VK Капсулу Мини
(Buildroot 2022.11.1, glibc 2.33, PulseAudio 16.1, Amlogic A113X) без замены
прошивки. Всё живёт в `/data/local/capsula-airplay`; `voice-agent`, аккаунт и
OTA-обновление не трогаются.

## Требования

- Проверенная прошивка 44.90, root через ADB, свободные ≥ 25 МиБ в `/data`.
- Оверлей `/`, смонтированный с `upperdir=/data/overlay/upper` (стоковая схема).
- Локальная сеть с mDNS и PTP (порт UDP 319/320 для nqptp).

## Что устанавливается

| Файл | Назначение |
|---|---|
| `/data/local/capsula-airplay/bin/shairport-sync` | приёмник 5.6.2, сборка под glibc 2.33 |
| `/data/local/capsula-airplay/bin/nqptp` | PTP-демон 1.2.9 |
| `/data/local/capsula-airplay/bin/libuuid.so.1.3.0` | зависимость shairport |
| `/data/local/capsula-airplay/bin/capsula-art` | палитра обложки (Go, из Alpine-пакета) |
| `/data/local/capsula-airplay/bin/capsula-airplay-keys` | кнопка `KEY_PLAYPAUSE` → control-сокет |
| `/data/local/capsula-airplay/bin/capsula-airplay-ring` | кольцо: обложка, громкость, дыхание |
| `/data/local/capsula-airplay/S99airplay` | управление службами (start/stop/status) |
| `/data/local/capsula-airplay/init.d/` | init-скрипты nqptp и shairport |
| `/etc/init.d/S99airplay` | копия для ручного запуска |
| `/etc/init.d/S50avahi-daemon` | оверлейная замена стокового скрипта (см. ниже) |

Конфиг — `/data/local/capsula-airplay/etc/shairport-sync.conf`. При обновлении
существующий конфиг сохраняется; имя меняется только через `--name`.

## Почему заменяется S50avahi-daemon

`rcS` в этой прошивке раскрывает список скриптов **до** выполнения:

```sh
for i in /etc/init.d/S??* ;do ... $i start ;done
```

Оверлей монтируется только на `S04overlaymount.sh`, поэтому файл
`/etc/init.d/S99airplay`, лежащий в оверлее, в этом списке отсутствует и при
загрузке не выполняется. Это было подтверждено: после перезагрузки службы не
поднимались, хотя ручной `S99airplay start` работал, а `rcK` при выключении
скрипт видел и вызывал.

Рабочее решение без записи в стоковый `/rom`: заменить через оверлей стоковый
`/etc/init.d/S50avahi-daemon`. Он всё равно нерабочий на этом ядре:
`CONFIG_ANDROID_PARANOID_NETWORK` не даёт `socket()` после сброса привилегий, и
стоковый скрипт (без `--no-drop-root`) завершает avahi с ошибкой. Замена
запускает avahi с `--no-drop-root` и затем вызывает
`/data/local/capsula-airplay/S99airplay start`. S50 идёт после S04 (оверлей уже
смонтирован) и после S40/S41 (сеть уже стартовала).

Удаление файла возвращает стоковый скрипт из `/rom`; `uninstall.sh` так и делает.

## Автозапуск: порядок

1. `S50avahi-daemon` (оверлей) → `avahi-daemon --no-drop-root -D`.
2. `S99airplay start` → `nqptp` → пауза 1 с → `shairport-sync` → `keys` → `ring`.

Службы держат pid-файлы в `/var/run`. Повторный `start` идемпотентен.

### Ловушка с именами скриптов

Внутри init-скриптов **нельзя** использовать `pidof nqptp` / `pidof
shairport-sync`: при прямом запуске скрипт получает то же 15-символьное `comm`,
что и демон, и `pidof` находит сам себя. Именно из-за этого `S99airplay`
молча выходил, пока скрипты вызывались напрямую. Сейчас проверка идёт по
pid-файлу, а helper-скрипты вызываются через `sh`.

## Громкость

`voice-agent` на стоковой Мини игнорирует `OnVolumeChangedEvent` при
`remote=0`, поэтому AirPlay-громкость применяется напрямую к PulseAudio-синку
`master` (`pa_sw_volume_from_dB`). Текущее значение пишется в
`/tmp/capsula-airplay-volume` и используется кольцом для белой дуги.
`stereoctl` остаётся только для обратной связи кнопок.

## Кнопка

`csk05t` отдаёт `KEY_PLAYPAUSE` (164), `KEY_VOLUMEUP`, `KEY_VOLUMEDOWN`,
`KEY_MICMUTE`. `capsula-airplay-keys` пересылает play/pause в control-сокет
shairport (`/tmp/capsula-airplay-control.sock`). Вне сеанса AirPlay кнопка
сохраняет штатное действие `voice-agent`.

## Кольцо

- 36 каналов = 12 RGB-пикселей, устройство `/dev/topleds`.
- Запись — ioctl `0x40107a01` (`struct { u32 start; u32 count; u8 *data; }`),
  карта каналов повторяет `voice-agent` (меняются местами первые два канала
  каждого пикселя).
- Обложка: shairport кладёт её в `/tmp/capsula-airplay-covers`, палитра
  считается `capsula-art --palette`, демон рисует градиент.
- Громкость: белая дуга 1,5 с после изменения.
- Без обложки: слабое белое дыхание.
- Штатные анимации ассистента и громкости имеют приоритет: демон уступает по
  меткам в `logread` и возвращает кольцо после сеанса.
- Часы (`is31fl32xx`, `clock-led1..30`) — отдельное устройство, пакет их не
  использует.

## Проверка

```sh
/data/local/capsula-airplay/S99airplay status
netstat -ltn | grep 7000
avahi-browse -t -p _airplay._tcp | grep -i mini
logread | grep -e shairport -e nqptp | tail
```

Холодная загрузка проверена: после `reboot` поднимаются avahi, nqptp,
shairport (:7000), keys и ring; mDNS-имя совпадает с конфигом.

## Ограничения

- OTA-обновление не отключается пакетом. Это отдельное решение владельца.
- Проверенная прошивка — 44.90. На другой версии пути и драйверы могут
  отличаться; установщик проверит `ID=buildroot`, `amlogic`/`axg` и оверлей.
- Windows-мастер из `windows/` рассчитан на Мини с Alpine (SSH). Для стоковой
  Мини установка выполняется командами `sh install.sh` (ADB/SSH).
- Воспроизведение, громкость с телефона и кнопка требуют живой проверки
  владельцем: без телефона эти события не воспроизводятся.
