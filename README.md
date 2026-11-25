# inir-niri — my Linux desktop

**[Español](README.es.md)** · **[Русский](README.ru.md)**

My **[inir](https://github.com/snowarch/iNiR)** + **niri** setup on CachyOS: music widgets, live lyrics on the desktop and my shell tweaks.

![Bar with visualizer](docs/screenshots/bar-visualizador.png)

## New here? Read this first

This repo **is not a full desktop**: it's *my look* (widgets, popups and configs)
for two projects made by other people.

| # | What you need | Where it comes from |
|---|---|---|
| 1 | **niri** — the compositor (the windows) | It's **installed**, not cloned: `sudo pacman -S niri` · [repo](https://github.com/YaLTeR/niri) |
| 2 | **iNiR** — the shell (bar, panels, settings) | It's **cloned**: [snowarch/iNiR](https://github.com/snowarch/iNiR) |
| 3 | **This look** | This repo 🙂 |

> On another distro? No problem: follow iNiR's guide
> ([inir.space/docs/install](https://inir.space/docs/install/)) for niri + iNiR,
> then run `./install.sh` from this repo. `bootstrap.sh` is Arch/CachyOS only.

### The easy way: one command

`bootstrap.sh` checks what's missing, installs niri + iNiR if needed, and applies
my setup at the end. It never deletes anything: whatever it replaces goes to a backup.

```bash
git clone https://github.com/Elvislrd/inir-niri.git
cd inir-niri
./bootstrap.sh
```

When it finishes: **log out, log back in choosing "niri"** and you're done.

> Prefer to let an AI do it? Copy the prompt from [`PROMPT.md`](PROMPT.md).

### The manual way (you already have niri + iNiR)

```bash
git clone https://github.com/Elvislrd/inir-niri.git
cd inir-niri
./install.sh
systemctl --user restart inir.service
```

### Which one do I use?

| Your situation | Command |
|---|---|
| I don't have niri or iNiR (or I'm not sure) | `./bootstrap.sh` |
| I already run niri + iNiR | `./install.sh` |

### If something fails

```bash
inir doctor      # checks the install and fixes what it can
inir logs        # shows why the shell didn't start
```

- Compile error (`makepkg`, `fakeroot`, `make`):
  `sudo pacman -S --needed base-devel`
- Can't clone iNiR: check your connection, or pin a version with
  `./bootstrap.sh --ref v3.1.1`.
- The script leaves the **log** and the iNiR copy in `/tmp/...`: send that text
  and we'll look at it.
- iNiR installed but no shell? Log out and back in choosing **niri**.

## What you get

![Full desktop](docs/screenshots/escritorio-completo.png)

All of this running on **niri + inir**:

- Desktop with **live song lyrics** and a cava visualizer across the screen.
- **Bar** with player, calendar, weather, resources and battery.
- **5 custom popups** (control panel, music, orbit, calendar, resources).
- **Yami Luminas 1440p wallpaper** included in `assets/wallpapers/`.
- My **full config** for inir and niri.

## Recommended: OpenCode + DeepSeek

To edit these configs without fighting QML, I use **OpenCode** with **DeepSeek**:

![OpenCode with DeepSeek](docs/screenshots/opencode-deepseek.png)

- Install OpenCode, pick DeepSeek as the model.
- Ask in plain language: *"make the music bar open on click"*.
- It edits the `.qml`, you restart the shell, done.

## What's included

### Widgets (QML)
| Widget | What it does |
|---|---|
| **Visualizer** | Cava spectrum bars on the bar or desktop, driven by real audio |
| **Media Controls** | Card with cover art, title, progress and controls |
| **Lyrics** | Song lyrics on the desktop, word by word, current line highlighted |

Includes the Iris faces (`IrisLyricsFace`, `IrisNowPlayingFace`) and the cava components.

### Custom popups

| Screenshot | File | What it is |
|---|---|---|
| ![panel](docs/screenshots/panel-control.png) | `popups/controlPanel/ControlPanelContent.qml` | Control panel: weather, calendar, media, mascot |
| ![orbit](docs/screenshots/reproductor-orbit.png) | `popups/mediaControls/components/MediaOrbitPlayer.qml` | Orbit player with covers around the current track |
| ![music](docs/screenshots/popup-musica-elvis.png) | `popups/mediaControls/components/MediaDashboardPlayer.qml` | Full player: cover, system info, queue |
| ![calendar](docs/screenshots/calendario-clima.png) | `popups/bar/ClockWidgetTooltip.qml` | Calendar + big weather with moon phase |
| ![resources](docs/screenshots/recursos-cpu-gpu.png) | `popups/bar/ResourcesPopup.qml` | CPU, GPU, RAM, disk and battery gauges |

### Config
| Folder | What it is |
|---|---|
| `config/inir/config.json` | My full shell config (bar, colours, panels, keybinds) |
| `config/inir/widgets/` | Position, size and options of every desktop widget |
| `config/inir/desktop-profiles/` | Saved desktop profiles |
| `config/niri/` | My niri config (`config.kdl` + `config.d/`) |
| `assets/wallpapers/` | **Yami Luminas 1440p** wallpaper (video mp4) |

## Requirements

- CachyOS / Arch (any distro with niri works)
- **niri**
- **inir** shell (quickshell) 3.1.x
- **cava** — `sudo pacman -S cava`
- Nerd Fonts + `Z003` (cursive font used by the lyrics)
- Any MPRIS player (mpv, Spotify, Firefox…)

## What `install.sh` does

- Copies my widgets, popups and configs **over** your existing iNiR.
- Backs everything up to `~/.config/inir-niri-backup/DATE-TIME/`.
- Never deletes anything, only copies over.
- `/home/USERNAME` paths are replaced by your `$HOME` automatically.
- If iNiR isn't found, it tells you to run `./bootstrap.sh`.

## Widgets only (keep your own config)

```bash
cp -r widgets/* ~/.config/quickshell/inir/modules/shared/background/widgets/
cp common/widgets/*.qml ~/.config/quickshell/inir/modules/common/widgets/
cp iris/widgets/*.qml ~/.config/quickshell/inir/modules/iris/widgets/
```

## Turn the widgets on

1. Desktop → **edit widgets**.
2. Add **Visualizer**, **Media** and **Lyrics**.
3. Resize and place them; the visualizer can stretch across the whole screen.

## Wallpaper

```bash
cp assets/wallpapers/yami-luminas-1440p.mp4 ~/Pictures/Wallpapers/
```

Then pick it in your shell settings.

## Notes

- Visualizer not moving? Check `cava` is installed and the default sink is the hardware one.
- No lyrics? The track isn't on LRCLIB; try another song.
- Lyrics can use the **Z003** cursive (same as the music popup).

## License

Free to use. Share your improvements.

- The **iNiR** shell is by [snowarch](https://github.com/snowarch/iNiR), licensed **GPL-3.0**.
- My configs and widgets are shared under the same license, because several files
  are derived from iNiR. See [`NOTICE.md`](NOTICE.md).
