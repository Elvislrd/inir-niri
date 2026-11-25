# Instalar con OpenCode (o cualquier IA)

Si no quieres tocar la terminal paso a paso, puedes pedirle la instalación a una IA
como **OpenCode + DeepSeek**. Copia el bloque de abajo y pégalo tal cual en el chat.

> **Antes de empezar:** abre OpenCode **dentro de esta carpeta** (la del repo),
> para que la IA vea `bootstrap.sh` e `install.sh`.

---

## Prompt (español)

```text
Estoy en un Linux y quiero instalar mi escritorio: niri (compositor) + iNiR (shell)
+ la estética de este repo.

Contexto importante:
- niri NO se clona: es un paquete del sistema.
- iNiR se instala clonando https://github.com/snowarch/iNiR y corriendo ./setup install.
- Este repo solo aplica la estética con ./install.sh (hace backup automático).

Haz esto, paso a paso, sin improvisar:

1. Muéstrame: la distro, si niri y quickshell están instalados, y si existe
   ~/.config/quickshell/inir.
2. Ejecuta ./bootstrap.sh desde esta carpeta y muéstrame su salida.
3. Si algo falla, PARA. Pégame el error y no deshagas backups, no borres configs
   y no inventes comandos "para arreglarlo".
4. No leas, copies ni subas ~/.config/inir/yt-cookies.txt ni los archivos *.bak-*.
5. Al terminar dime: qué se instaló, qué archivos se reemplazaron y dónde quedó
   el backup para revertir.
```

## Prompt (English)

```text
I'm on Linux and I want to install my desktop: niri (compositor) + iNiR (shell)
+ the look from this repo.

Important:
- niri is NOT cloned: it's a system package.
- iNiR is installed by cloning https://github.com/snowarch/iNiR and running
  ./setup install.
- This repo only applies the look with ./install.sh (it makes a backup first).

Do this step by step, don't improvise:
1. Show me: my distro, whether niri and quickshell are installed, and whether
   ~/.config/quickshell/inir exists.
2. Run ./bootstrap.sh from this folder and show me the output.
3. If anything fails, STOP. Paste the error and don't undo backups, don't delete
   configs, and don't invent "fixes".
4. Don't read, copy or upload ~/.config/inir/yt-cookies.txt or any *.bak-* file.
5. When done, tell me: what got installed, which files were replaced, and where
   the backup is so I can revert.
```

---

## ¿Por qué `bootstrap.sh` y no dejar que la IA improvise?

Porque el script hace **siempre lo mismo**: revisa, instala, hace backup y aplica.
La IA solo lo ejecuta y te cuenta qué pasó. Menos libertad para ella, menos sorpresas
para ti.

## Si prefieres hacerlo a mano

```bash
# 1. niri + quickshell (Arch/CachyOS)
sudo pacman -S --needed niri quickshell

# 2. iNiR (shell) — sí se clona
git clone https://github.com/snowarch/iNiR
cd iNiR && ./setup install

# 3. esta estética
cd .. && git clone https://github.com/Elvislrd/inir-niri.git
cd inir-niri && ./install.sh
```

Luego cierra sesión, vuelve a entrar eligiendo **niri**, y corre:

```bash
systemctl --user restart inir.service
```

Más detalles: [README.es.md](README.es.md) · [inglés](README.md) · [ruso](README.ru.md)
