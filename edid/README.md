# Colori sbagliati su HDMI (Mac mini 2010 + nouveau)

## Il problema in breve

- **Sintomo:** dal momento in cui parte il driver `nouveau` i colori sono
  sbagliati. Il nero diventa **bordeaux** (NixOS) o tutto ha una **tinta verde**
  (installer Fedora). Il menu di boot e i primissimi messaggi sono invece
  normali, perché lì lo schermo lo gestisce ancora il firmware Apple.
- **Hardware:** Mac mini Mid 2010 (GeForce 320M, uscita HDMI) + monitor
  **LG 27MK600M** collegato via HDMI.
- **Causa:** il monitor, nel suo EDID (i dati con cui si descrive al computer),
  si dichiara HDMI e capace di YCbCr. Con questa combinazione nouveau e il
  monitor non si accordano sul formato del colore.
- **Soluzione:** dare al kernel una copia dell'EDID **senza la parte HDMI**.
  Così nouveau tratta l'uscita come DVI e manda RGB normale.
- **Effetto collaterale:** niente audio sul cavo HDMI. Per l'audio usa il jack
  del Mac.

Verificato il 2026-10-18 con NixOS 26.05 e kernel 6.18.

## I file

| File | Cos'è |
|---|---|
| `lg-27mk600m-originale.bin` | EDID originale del monitor (256 byte), di riserva |
| `lg-27mk600m-dvi.bin` | EDID modificato (128 byte), quello in uso |
| `crea-edid-dvi.py` | Script che crea la versione DVI da un EDID originale |

In `configuration.nix` la parte interessata è questa:

```nix
hardware.display.edid.packages = [ ... lg-27mk600m-dvi.bin ... ];
hardware.display.outputs."HDMI-A-1".edid = "lg-27mk600m-dvi.bin";
```

NixOS la traduce nel parametro del kernel
`drm.edid_firmware=HDMI-A-1:edid/lg-27mk600m-dvi.bin`.

## Quando devo rifarlo?

- **Altro monitor 1080p:** probabilmente va bene così com'è, perché l'EDID in
  uso è un generico "1080p a 60 Hz, DVI".
- **Monitor con un'altra risoluzione** (1440p, 4K, ecc.) **oppure colori di nuovo
  strani:** rifai la procedura qui sotto con il nuovo monitor.
- **Nessun problema senza la correzione:** togli le due righe da
  `configuration.nix` e lancia `sudo nixos-rebuild switch`.

## Procedura per un monitor nuovo

### 0. Partire con l'EDID vero del monitor

Se la correzione è attiva, `/sys/class/drm/.../edid` restituisce il file
sostituito e non quello del monitor. Quindi prima commenta le due righe in
`configuration.nix`, lancia `sudo nixos-rebuild switch` e riavvia. In
alternativa, al menu di boot scegli una generazione precedente alla
correzione.

### 1. Trovare il nome dell'uscita e leggere l'EDID

```bash
for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status)"; done
```

L'uscita è quella che risulta `connected`, di solito `card0-HDMI-A-1`.

```bash
cat /sys/class/drm/card0-HDMI-A-1/edid > nuovo-monitor-originale.bin
```

Per guardarci dentro (facoltativo):

```bash
nix-shell -p edid-decode --run "edid-decode nuovo-monitor-originale.bin"
```

Se vedi `Vendor-Specific Data Block (HDMI)` e `Supports YCbCr`, è il caso
descritto qui.

### 2. Creare la versione DVI

```bash
nix-shell -p python3 --run "python3 crea-edid-dvi.py nuovo-monitor-originale.bin nuovo-monitor-dvi.bin"
```

### 3. Provarla al volo, senza toccare la configurazione

Vale fino al prossimo riavvio. Tieni d'occhio lo schermo mentre lanci i comandi.

```bash
sudo sh -c 'cat nuovo-monitor-dvi.bin > /sys/kernel/debug/dri/0/HDMI-A-1/edid_override'
```

```bash
echo off | sudo tee /sys/class/drm/card0-HDMI-A-1/status
```

```bash
echo detect | sudo tee /sys/class/drm/card0-HDMI-A-1/status
```

Lo schermo si spegne un attimo e torna con i colori giusti. Se sei in una
sessione grafica e non succede niente, prova dalla console (Ctrl+Alt+F2) o
riavvia la sessione.

Per annullare la prova:

```bash
echo reset | sudo tee /sys/kernel/debug/dri/0/HDMI-A-1/edid_override
```

```bash
echo detect | sudo tee /sys/class/drm/card0-HDMI-A-1/status
```

### 4. Renderla permanente

1. Copia `nuovo-monitor-dvi.bin` in `/etc/nixos/edid/`.
2. In `configuration.nix` sostituisci il nome del file nelle due righe di
   `hardware.display`. Il `cp` dentro `runCommand` e `outputs."HDMI-A-1".edid`
   devono avere lo stesso nome. Se l'uscita non è `HDMI-A-1`, cambia anche
   quella.
3. Applica la modifica:

```bash
sudo nixos-rebuild switch
```

4. Riavvia e controlla:

```bash
cat /proc/cmdline
```

Deve contenere `drm.edid_firmware=HDMI-A-1:edid/<file>.bin`.

## Se qualcosa va storto

- **Schermo nero dopo la modifica:** al menu di boot scegli la generazione
  precedente, poi sistema `configuration.nix`.
- **Senza nessuna modifica:** collegati via SSH dal PC (`ssh -i ~/.ssh/id_ed25519_macmini jhyrachy@<IP-del-mac>`) e
  annulla da lì.
- **Ripiego hardware:** un adattatore da Mini DisplayPort a VGA verso
  l'ingresso VGA del monitor. Non passa dall'HDMI, quindi il problema non si
  presenta.
