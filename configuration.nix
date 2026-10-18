# NixOS - Mac mini Mid 2010 (Macmini4,1)
# Core 2 Duo, 16 GB RAM, SSD, NVIDIA GeForce 320M (Tesla) -> driver nouveau
#
# Va copiato in /mnt/etc/nixos/configuration.nix DOPO aver lanciato
# `nixos-generate-config --root /mnt` (che crea hardware-configuration.nix).

{ config, pkgs, lib, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # --- Boot -----------------------------------------------------------------
  # Il firmware EFI Apple ignora quasi sempre le variabili NVRAM scritte da
  # Linux: non le tocchiamo e ci affidiamo al percorso di fallback
  # EFI/BOOT/BOOTX64.EFI, che systemd-boot installa comunque.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = false;

  # --- Hardware -------------------------------------------------------------
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Sensori e controller SMC Apple (temperature, ventola)
  boot.kernelModules = [ "applesmc" "coretemp" ];
  # Controllo ventola più aggressivo; opzionale, l'SMC se la cava anche da solo.
  # services.mbpfan.enable = true;

  # GPU: nouveau è il default, non serve impostare videoDrivers.
  # Il driver proprietario per la 320M (legacy 340) è abbandonato e non
  # funziona con i kernel attuali: non usarlo.
  hardware.graphics.enable = true;

  # Colori sbagliati su HDMI (sfondo bordeaux/verde) con nouveau + LG 27MK600M.
  # Soluzione: EDID del monitor senza il blocco CTA/HDMI, così nouveau tratta
  # l'uscita come DVI e manda RGB pieno. Testato dal live: colori corretti.
  # NB: è l'EDID di QUESTO monitor; se lo cambi, togli/aggiorna queste righe.
  # Spiegazione e procedura completa: edid/README.md
  hardware.display.edid.packages = [
    (pkgs.runCommand "edid-lg-27mk600m-dvi" { } ''
      mkdir -p $out/lib/firmware/edid
      cp ${./edid/lg-27mk600m-dvi.bin} $out/lib/firmware/edid/lg-27mk600m-dvi.bin
    '')
  ];
  hardware.display.outputs."HDMI-A-1".edid = "lg-27mk600m-dvi.bin";

  # Wi-Fi: Broadcom BCM43224 (14e4:4353) -> driver libero brcmsmac, già nel
  # kernel; il firmware arriva da enableRedistributableFirmware. Niente da fare.
  #
  # Solo se brcmsmac si rivelasse instabile, alternativa broadcom-sta
  # (non libero e segnato "insecure" in nixpkgs):
  # boot.kernelModules = [ "wl" ];  # (da unire alla lista sopra)
  # boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  # boot.blacklistedKernelModules = [ "b43" "bcma" "ssb" "brcmsmac" "brcmfmac" ];
  # nixpkgs.config.allowInsecurePredicate = p: lib.hasPrefix "broadcom-sta" (lib.getName p);

  hardware.bluetooth.enable = true;

  # --- SSD e memoria --------------------------------------------------------
  # btrfs con subvolumi @ @home @nix (dispositivi e subvol stanno in
  # hardware-configuration.nix; qui si aggiungono solo le opzioni)
  fileSystems = lib.genAttrs [ "/" "/home" "/nix" ] (_: {
    options = [ "compress=zstd:1" "noatime" ];
  });
  # Controllo mensile dei checksum (trova file corrotti dal disco)
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
  services.fstrim.enable = true;
  zramSwap.enable = true;

  # --- Rete -----------------------------------------------------------------
  networking.hostName = "macmini";
  networking.networkmanager.enable = true;

  # Wi-Fi di casa, connessione automatica.
  # SSID e password NON stanno qui (finirebbero nel /nix/store, leggibile da
  # tutti) ma in un file solo-root, vedi wifi.env.example.
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ "/etc/nixos/secrets/wifi.env" ];
    profiles.casa = {
      connection = {
        id = "casa";
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$WIFI_SSID";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$WIFI_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  # --- Lingua e tastiera ----------------------------------------------------
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "it_IT.UTF-8";
  console.keyMap = "it";
  services.xserver.xkb.layout = "it";  # tastiera PC (per Apple: variant = "mac")

  # --- Desktop: LXQt su X11 -------------------------------------------------
  # X11 invece di Wayland: su nouveau/Tesla è la scelta più stabile.
  services.xserver.enable = true;
  services.xserver.desktopManager.lxqt.enable = true;
  # LightDM è molto più leggero di SDDM (che usa QML + OpenGL)
  services.xserver.displayManager.lightdm.enable = true;
  programs.nm-applet.enable = true;

  # --- Audio ----------------------------------------------------------------
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # --- Utente ---------------------------------------------------------------
  users.users.jhyrachy = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    # Chiave pubblica del PC da cui ti colleghi (contenuto di ~/.ssh/<chiave>.pub)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIaXyO7IGfCkk5OZun6dJ0XxQvHILInQMrjEjZAAo+ho jhyrachy@fedora->macmini"
    ];
  };

  # --- Tailscale (VPN privata: accesso da fuori casa, collegamento al VPS) --
  # Primo collegamento: `sudo tailscale up` e login dal link che stampa.
  services.tailscale = {
    enable = true;
    openFirewall = true;  # UDP 41641: connessioni dirette invece che via relay
  };

  # --- Accesso remoto -------------------------------------------------------
  # Solo chiavi, niente password e niente login diretto di root.
  # La porta 22 viene aperta in automatico nel firewall.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # --- Flatpak --------------------------------------------------------------
  services.flatpak.enable = true;
  # Aggiunge Flathub al primo avvio (e non fa nulla se c'è già)
  systemd.services.flatpak-repo = {
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
  };

  # Servizio firmware usato da Discover: senza, Discover mostra
  # "The name is not activatable". Parte solo quando serve.
  services.fwupd.enable = true;

  # --- Container: podman (+ comandi docker), distrobox ----------------------
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;  # `docker ...` funziona e chiama podman
    defaultNetwork.settings.dns_enabled = true;  # i container si vedono per nome
  };

  # --- Software -------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    git
    htop
    pciutils
    lm_sensors
    firefox
    distrobox
    podman-compose
    kdePackages.discover  # store grafico (Flatpak/Flathub), Qt come LXQt
  ];

  # --- Nix ------------------------------------------------------------------
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Lascia il valore che genera nixos-generate-config (= versione dell'ISO
  # usata per installare) e non cambiarlo più, anche dopo gli aggiornamenti.
  system.stateVersion = "26.05";
}
