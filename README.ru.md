# inir-niri — мой рабочий стол на Linux

**[English](README.md)** · **[Español](README.es.md)**

Мой сетап **[inir](https://github.com/snowarch/iNiR)** + **niri** на CachyOS: музыкальные виджеты, живые тексты песен на рабочем столе и мои настройки шелла.

![Панель с визуализатором](docs/screenshots/bar-visualizador.png)

## Что вы получите

![Полный рабочий стол](docs/screenshots/escritorio-completo.png)

Всё это работает на **niri + inir**:

- Рабочий стол с **живым текстом песни** и визуализатором cava на всю ширину.
- **Панель** с плеером, календарём, погодой, ресурсами и батареей.
- **5 кастомных попапов** (панель управления, музыка, орбита, календарь, ресурсы).
- **Обои Yami Luminas 1440p** в `assets/wallpapers/`.
- Мой **полный конфиг** inir и niri.

## Рекомендую: OpenCode + DeepSeek

Чтобы править эти конфиги без борьбы с QML, я использую **OpenCode** с **DeepSeek**:

![OpenCode с DeepSeek](docs/screenshots/opencode-deepseek.png)

- Ставите OpenCode, выбираете модель DeepSeek.
- Пишете обычными словами: *«сделай, чтобы музыкальный попап открывался по клику»*.
- Он правит `.qml`, вы перезапускаете шелл — готово.

## Что внутри

### Виджеты (QML)
| Виджет | Что делает |
|---|---|
| **Visualizer** | Полосы спектра (cava) на панели или рабочем столе, реагируют на реальный звук |
| **Media Controls** | Карточка с обложкой, названием, прогрессом и кнопками |
| **Lyrics** | Текст песни на рабочем столе, слово за словом, текущая строка подсвечена |

Включает лица Iris (`IrisLyricsFace`, `IrisNowPlayingFace`) и компоненты cava.

### Кастомные попапы

| Скриншот | Файл | Что это |
|---|---|---|
| ![панель](docs/screenshots/panel-control.png) | `popups/controlPanel/ControlPanelContent.qml` | Панель управления: погода, календарь, медиа, маскот |
| ![орбита](docs/screenshots/reproductor-orbit.png) | `popups/mediaControls/components/MediaOrbitPlayer.qml` | Плеер-орбита с обложками вокруг трека |
| ![музыка](docs/screenshots/popup-musica-elvis.png) | `popups/mediaControls/components/MediaDashboardPlayer.qml` | Полный плеер: обложка, системная информация, очередь |
| ![календарь](docs/screenshots/calendario-clima.png) | `popups/bar/ClockWidgetTooltip.qml` | Календарь + большая погода с фазой луны |
| ![ресурсы](docs/screenshots/recursos-cpu-gpu.png) | `popups/bar/ResourcesPopup.qml` | CPU, GPU, RAM, диск и батарея со шкалами |

### Конфиг
| Папка | Что это |
|---|---|
| `config/inir/config.json` | Мой полный конфиг шелла (панель, цвета, панели, бинды) |
| `config/inir/widgets/` | Позиция, размер и опции каждого виджета |
| `config/inir/desktop-profiles/` | Сохранённые профили рабочего стола |
| `config/niri/` | Мой конфиг niri (`config.kdl` + `config.d/`) |
| `assets/wallpapers/` | Обои **Yami Luminas 1440p** (видео mp4) |

## Требования

- CachyOS / Arch (подойдёт любой дистрибутив с niri)
- **niri**
- **inir** shell (quickshell) 3.1.x
- **cava** — `sudo pacman -S cava`
- Nerd Fonts + `Z003` (курсив для текста песен)
- Любой MPRIS-плеер (mpv, Spotify, Firefox…)

## Установка

```bash
git clone https://github.com/Elvislrd/inir-niri.git
cd inir-niri
bash install.sh
systemctl --user restart inir.service
```

- Делает **бэкап** всего в `~/.config/inir-niri-backup/ДАТА-ВРЕМЯ/`.
- Ничего не удаляет, только копирует поверх.
- Пути `/home/USERNAME` автоматически заменяются на ваш `$HOME`.

## Только виджеты (не трогая свой конфиг)

```bash
cp -r widgets/* ~/.config/quickshell/inir/modules/shared/background/widgets/
cp common/widgets/*.qml ~/.config/quickshell/inir/modules/common/widgets/
cp iris/widgets/*.qml ~/.config/quickshell/inir/modules/iris/widgets/
```

## Включить виджеты

1. Рабочий стол → **редактировать виджеты**.
2. Добавьте **Visualizer**, **Media** и **Lyrics**.
3. Подгоните размер и место; визуализатор можно растянуть на всю ширину.

## Обои

```bash
cp assets/wallpapers/yami-luminas-1440p.mp4 ~/Изображения/Wallpapers/
```

Потом выберите их в настройках шелла.

## Примечания

- Визуализатор не двигается? Проверьте, что `cava` установлен, а sink по умолчанию — аппаратный.
- Нет текста? Трека нет на LRCLIB — попробуйте другую песню.
- Для текста можно включить курсив **Z003** (как в музыкальном попапе).

## Лицензия

Свободно используйте. Делитесь улучшениями.
