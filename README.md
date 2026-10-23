# Cyberpunk 2077: fix "RED4ext (error 998)" on Linux / Proton

🇬🇧 English below · 🇫🇷 [Français](#français)

## The problem

On Linux (Steam + Proton), launching Cyberpunk 2077 with RED4ext shows:

```
RED4ext (error 998)
Invalid access to memory location.
S:\common\Cyberpunk 2077\red4ext\RED4ext.dll
RED4ext could not be loaded.
```

The RED4ext log in `red4ext/logs/` is created but stays **empty**, and no
RED4ext plugin (e.g. NightCoop) loads. Switching Proton versions does not help.

## The cause

The game's Proton prefix ships an old Visual C++ runtime (`msvcp140.dll`
**14.28**, from 2020). RED4ext is built with a recent Visual Studio, whose STL
requires runtime **14.40 or newer**: with the old one it crashes with an access
violation inside `MSVCP140.dll` the first time it locks a mutex (right when it
writes its first log line). Windows Update fixes this on Windows; nothing
updates it inside a Proton prefix.

A `PROTON_LOG=1 WINEDEBUG=+seh,+loaddll` trace shows it:

```
Loaded L"S:\\common\\Cyberpunk 2077\\red4ext\\RED4ext.dll" ... native
code=c0000005 (EXCEPTION_ACCESS_VIOLATION) ...
backtrace: L"MSVCP140.dll" + 0000000000012EB0.
backtrace: L"RED4ext.dll" + ...
```

## The fix

### Automatic

```bash
git clone https://github.com/miriwayy/cyberpunk-red4ext-proton-fix.git
cd cyberpunk-red4ext-proton-fix
./fix-red4ext-proton.sh
```

Requires `protontricks`, `curl` and `unzip`. Close the game first.

If your game patch is newer than the latest RED4ext release (e.g. patch 2.5
before RED4ext 1.31 is out), add `--red4ext-dev` to also install the latest
build from RED4ext's official GitHub CI:

```bash
./fix-red4ext-proton.sh --red4ext-dev
```

### Manual

1. Close the game.
2. Download the latest
   [Visual C++ Redistributable x64](https://aka.ms/vs/17/release/vc_redist.x64.exe)
   from Microsoft.
3. Install it into the game's prefix:
   ```bash
   protontricks -c 'wine /path/to/vc_redist.x64.exe /install /quiet /norestart' 1091500
   ```
4. Steam launch options for the game:
   ```
   WINEDLLOVERRIDES="winmm=n,b" %command%
   ```
5. Launch the game. `red4ext/logs/red4ext-*.log` should now have content.

### RED4ext and game patch 2.5

RED4ext 1.30.0 supports the game up to patch 2.31. Support for patch 2.5 is on
RED4ext's `master` branch (commit
[`47ac01c`](https://github.com/WopsS/RED4ext/commit/47ac01cd1d04a33f1748d1ebf8d8bf64814ee6c6))
but not released yet. Until it is, use `--red4ext-dev`, or download the
`red4ext-release-*` artifact of the latest
[Build Workflow run](https://github.com/WopsS/RED4ext/actions/workflows/cpp-build.yml)
yourself. Once an official release supports your patch, install that instead.

Tested with: Cyberpunk 2077 patch 2.5 (exe 3.0.88.46235), Proton 11.0,
Nobara (Fedora 44), RED4ext `47ac01c`, NightCoop open beta.

---

## Français

### Le problème

Sous Linux (Steam + Proton), au lancement de Cyberpunk 2077 avec RED4ext :

```
RED4ext (error 998)
Pas d'accès à l'emplacement mémoire.
RED4ext could not be loaded.
```

Le log dans `red4ext/logs/` reste **vide** et aucun plugin RED4ext (ex.
NightCoop) ne se charge. Changer de version de Proton ne change rien.

### La cause

Le prefix Proton du jeu contient un runtime Visual C++ trop vieux
(`msvcp140.dll` **14.28**, de 2020). RED4ext est compilé avec un Visual Studio
récent qui exige la version **14.40 ou plus** ; avec l'ancienne il plante dans
`MSVCP140.dll` dès son démarrage.

### La solution

Jeu fermé :

```bash
./fix-red4ext-proton.sh               # met à jour le runtime Visual C++
./fix-red4ext-proton.sh --red4ext-dev # + installe le build de dev de RED4ext (patch 2.5)
```

Ou à la main : télécharge
[vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe), puis

```bash
protontricks -c 'wine /chemin/vers/vc_redist.x64.exe /install /quiet /norestart' 1091500
```

Options de lancement Steam du jeu :

```
WINEDLLOVERRIDES="winmm=n,b" %command%
```

## Credits

- [RED4ext](https://github.com/WopsS/RED4ext) by WopsS and contributors (MIT).
- Build artifacts are fetched through [nightly.link](https://nightly.link).

This repository contains no game files, mod files or Microsoft binaries — only
a script that downloads them from their official sources.
