# inir-niri — música y letras en el escritorio

Widgets de **música y letras** para [inir](https://github.com/Elvislrd) + **niri** (CachyOS / Arch).

![Barra con visualizador](docs/screenshots/bar-visualizador.png)

![Escritorio con letras y reproductor](docs/screenshots/escritorio-lyrics.png)

## Qué trae

| Widget | Qué hace |
|---|---|
| **Visualizer** | Barras de espectro (cava) en la barra o el escritorio, reaccionan al audio real |
| **Media Controls** | Tarjeta con carátula, título, progreso y controles |
| **Lyrics** | Letra de la canción en el escritorio, palabra por palabra, línea actual iluminada |

Incluye las caras Iris (`IrisLyricsFace`, `IrisNowPlayingFace`) y los componentes de cava.

## Requisitos

- CachyOS / Arch
- niri (o Hyprland)
- inir shell (quickshell)
- `cava` — `sudo pacman -S cava`
- Reproductor con MPRIS (mpv, Spotify, Firefox…)
- Red para las letras (`lyrics` usa LRCLIB)

## Instalar

```bash
git clone https://github.com/Elvislrd/inir-niri.git
cd inir-niri
bash install.sh
systemctl --user restart inir.service
```

Backup automático en `~/.config/inir-music-widgets-backup/FECHA-HORA/`.

## Activar los widgets

1. Escritorio → **clic derecho → editar widgets** (o el modo edición de inir).
2. Añade **Visualizer**, **Media** y **Lyrics**.
3. Ajusta tamaño y posición; el visualizador puede ir a lo ancho de la pantalla.

## Configuración útil

- **Visualizador**: en `widgets/visualizer/widget.json` puedes cambiar barras, sensibilidad y estilo (barras, línea ondulada, espejo).
- **Letras**: `widgets/lyrics/widget.json` → fuente y tamaño. Con la opción *Letra* puedes usar la cursiva **Z003** (la misma del popout).
- **Media**: `widgets/mediaControls/widget.json` → preset (`full`, `compact`, `lyrics`, `expandingLyrics`…).

## Notas

- Si el visualizador no se mueve, revisa que `cava` exista y que el sink por defecto sea el de hardware.
- Si no aparecen letras, es que la canción no está en LRCLIB; prueba otra.

## Licencia

Uso libre. Comparte mejoras.
