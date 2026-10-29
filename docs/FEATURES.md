# Что можно перенести со Station-airplay

Обзор 30.10.2026. Upstream Station-airplay: `1a11fd13c7ee` (влит PR #11,
runtime 1.4.14); локально также изучена ветка `release/luna-airplay-1.4.14-20261029`.
Это анализ исходников, не заявление о проверке новых функций на Капсуле.

| Функция | У Станций | Капсула / решение |
|---|---|---|
| Имя комнаты | YAM/Luna device API, UTF-8 truncation | hostname из /etc/hostname при установке; ручное имя сохранено при upgrade |
| Иконка | model/am=AudioAccessory5,1 | Уже перенесено, отдельный патч |
| Громкость с телефона | native-volume bridge + sender ack | Сейчас отдельная software attenuation; НЕ двусторонняя синхронизация |
| Кнопки громкости | нативная громкость → bridge → sender | Твикер уже пишет Master, добавлять triggerhappy нельзя |
| Play/Pause/Next/Previous | D-Bus RemoteControl + AP2 event channel/DACP | Нужна новая сборка приёмника и адаптер, пока не установлено |
| Кнопка Алисы | короткое 30–600 мс; длинное остаётся Алисе | На Alpine нет Алисы; action занят экраном, нужна настройка самого твикера |
| До нажатия Play | GetControlStatus с живым event connection | Нужны shared-controls/preplay патчи; старые metadata недостаточны |
| Двусторонняя громкость | native level first; delayed sender ack; echo suppression | Сначала адаптер к твикеру и согласование единственного владельца Master |
| Мультирум | Apple PTP/nqptp | Уже в базовом AirPlay 2; синхронность надо проверять ушами |
| Групповые кнопки/голос | HMAC LAN bridge, active own gid, peers/replay checks | Не включать автоматически; другой пакетный протокол, явные peers и ключ |
| Кольцо connected/play/pause/volume | YAM sysfs / Station2 cooperative framebuffer | На Капсуле кольцом владеет твикер; нужен IPC/lease, не второй painter |
| Duck на речь Алисы | SetStreamGain с ограниченной lease | Алисы на Alpine нет; полезно позже для локальных TTS/уведомлений |
| Голосовые команды | точный словарь + YAM command interception | Без ASR/ассистента переносить нечего; shell не создаёт Алису |
| Нативная музыка/handover | Quasar Player Pause, shared audio/pipe | На Alpine нет maind/Quasar — не переносить |

## Почему не triggerhappy + mpc

Команды `mpc toggle`/`next` управляют MPD, не потоком AirPlay на iPhone.
Установленные MPD/mpc не превращают их в пульт AirPlay. Коды KEY_A/B/C/D из
примера — заполнители, не измеренная раскладка Капсулы.

capsula-mini-tweaker 1.0.0 уже открывает CSK05T, делает EVIOCGRAB и обрабатывает
115/114/248/582 (из конфигурации), debounce/repeat, mute/action chord, экран и
кольцо. Второй evdev-reader либо не получит событий, либо создаст конфликт,
если отключить grab. Для ребинда надо расширять один обработчик твикера,
а не ставить параллельный сервис. evtest допустим для диагностики владельцем,
но с учётом текущего grab, и без остановки твикера вслепую.

## План безопасного переноса

1. Собрать отдельный aarch64/musl receiver с D-Bus и проверенными AP2
   shared-controls, preplay-event-channel и IPv4 DACP discovery патчами.
   Текущий бинарник не содержит этих интерфейсов. Патчи из upstream нельзя
   применять как конфиг к уже запущенному процессу.
2. Протестировать live status/transport на mock-отправителе: connected без
   audio, disconnect, смена клиента, stale metadata и недоступный DACP.
3. Добавить адаптер к твикеру: один владелец Master, чтение фактического
   квантованного уровня, startup native-first, timeout/ack и подавление echo.
   Не копировать формулу volume-sync.sh: software dB и шкала softvol отличаются.
   Твикер сейчас кеширует State, внешняя запись amixer может быть перетёрта.
4. Через опцию твикера привязать action к play/pause, не теряя режимы экрана и
   комбинации. Next/Previous — только по явному согласованию жестов.
5. Индикацию вести через того же владельца кольца, с возвратом пользовательских
   эффектов. Не писать одновременно из shairport hooks и твикера.
6. После приёмки локального управления обсуждать opt-in group bridge. Не
   копировать приватные peers/ключи, не считать два разных протокола совместимыми.

Функции из пунктов 1–6 ещё НЕ перенесены и НЕ развёрнуты. Рабочий звук и кнопки
ради обзора не останавливались. Windows-мастер устанавливает только текущую
проверенную аудиосборку с исправленным значком, не обещает transport/voice sync.
