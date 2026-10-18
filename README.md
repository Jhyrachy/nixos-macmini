# NixOS sul Mac mini Mid 2010

Configurazione [NixOS](https://nixos.org) per un Mac mini Mid 2010
(Macmini4,1). Su questa macchina NixOS fa da desktop leggero e da piccolo
server di casa.

| Componente | Dettagli |
|---|---|
| CPU | Intel Core 2 Duo P8600 (2 core, 2,4 GHz) |
| RAM | 16 GB |
| Disco | SSD SATA 240 GB, btrfs |
| GPU | NVIDIA GeForce 320M, driver libero `nouveau` |
| Wi-Fi | Broadcom BCM43224 (`14e4:4353`), driver libero `brcmsmac` |

## Cosa c'è nella configurazione

- **NixOS 26.05**, avvio con systemd-boot in UEFI.
- **LXQt su X11**, con LightDM come schermata di login. È leggero abbastanza
  per la 320M.
- **btrfs** con i subvolumi `@`, `@home` e `@nix`, compressione `zstd:1`,
  `noatime` e un controllo mensile dei checksum (scrub). Swap su zram.
- **Wi-Fi** con connessione automatica tramite NetworkManager. Le credenziali
  stanno in un file separato, mai nel repository.
- **SSH** solo con chiave: niente password e niente accesso come root.
- **Flatpak** con Flathub. Come store grafico c'è Discover.
- **Podman** (rootless, con i comandi `docker` compatibili), `podman-compose`
  e `distrobox`.
- **Correzione dei colori HDMI:** con `nouveau` e un monitor HDMI i colori
  escono sbagliati. Spiegazione e procedura sono in
  [`edid/README.md`](edid/README.md).

## I file

| File | Cos'è |
|---|---|
| `configuration.nix` | La configurazione del sistema |
| `hardware-configuration.nix` | Generato da `nixos-generate-config`: dischi e moduli del kernel |
| `edid/` | EDID modificato del monitor, script per crearlo e guida |
| `wifi.env.example` | Modello per le credenziali Wi-Fi |
| `estrai-wifi.sh` | Crea `wifi.env` partendo dalla rete a cui è connesso un PC con NetworkManager |

## I segreti

Il file `wifi.env`, con il nome della rete e la password, è escluso da git
(vedi `.gitignore`). Sul Mac sta in `/etc/nixos/secrets/wifi.env`, con
permessi `600` (lo legge solo root). La configurazione lo legge all'avvio
tramite `networking.networkmanager.ensureProfiles.environmentFiles`.

## Installazione da zero

1. Avvia il Mac dalla ISO **minimal** di NixOS: tieni premuto Alt
   all'accensione e scegli "EFI Boot".
2. Partiziona il disco:
   - tabella GPT;
   - una partizione ESP da 1 GB, FAT32, con etichetta `BOOT`;
   - il resto in btrfs con etichetta `nixos`, con i subvolumi `@`, `@home`
     e `@nix`.
3. Monta i subvolumi in `/mnt` e lancia `nixos-generate-config --root /mnt`.
4. Copia questo repository in `/mnt/etc/nixos/`, sovrascrivendo il
   `configuration.nix` generato ma tenendo l'`hardware-configuration.nix`
   generato.
5. Crea `/mnt/etc/nixos/secrets/wifi.env` partendo da `wifi.env.example`, con
   permessi `600`.
6. Lancia `nixos-install --no-root-passwd`, poi imposta la password del tuo
   utente con `nixos-enter --root /mnt -c 'passwd jhyrachy'`.

## Aggiornare il sistema

Sul Mac:

```bash
sudo nixos-rebuild switch
```

Per aggiornare anche i pacchetti:

```bash
sudo nixos-rebuild switch --upgrade
```

Se qualcosa va storto, al menu di avvio scegli la generazione precedente.
