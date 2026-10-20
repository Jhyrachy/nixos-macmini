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
  hardware.bluetooth.powerOnBoot = false;  # si accende solo quando serve

  # --- Risparmio energetico -------------------------------------------------
  # È un server: non deve mai andare in sospensione
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # Wi-Fi sempre pienamente attivo: è l'unica connessione del server e il
  # risparmio energetico del Wi-Fi può causare ritardi o disconnessioni.
  networking.networkmanager.wifi.powersave = false;

  # powertop --auto-tune all'avvio (sospensione automatica di USB, PCI, audio...)
  powerManagement.powertop = {
    enable = true;
    # ...ma tastiera e mouse USB restano sempre attivi (niente ritardi)
    postStart = ''
      for i in /sys/bus/usb/devices/*:*; do
        if [ "$(cat "$i/bInterfaceClass" 2>/dev/null)" = "03" ]; then
          echo on > "$i/../power/control"
        fi
      done
    '';
  };

  # Monitor in standby dopo 10 minuti di inattività (anche sulla schermata
  # di login). È il risparmio più grande: un monitor acceso consuma più del Mac.
  services.xserver.serverFlagsSection = ''
    Option "BlankTime" "10"
    Option "StandbyTime" "10"
    Option "SuspendTime" "10"
    Option "OffTime" "10"
  '';
  # Nella sessione LXQt lo schermo lo gestisce xscreensaver: schermo nero
  # (niente animazioni, che consumano CPU e GPU) e monitor spento dopo 10 min.
  # Se lo modifichi dalle impostazioni di LXQt, vince ~/.xscreensaver.
  services.xserver.displayManager.sessionCommands = ''
    ${pkgs.xset}/bin/xset s 600 600 +dpms dpms 600 600 600
    ${pkgs.xrdb}/bin/xrdb -merge <<'EOF'
    xscreensaver.mode: blank
    xscreensaver.timeout: 0:10:00
    xscreensaver.dpmsEnabled: True
    xscreensaver.dpmsStandby: 0:10:00
    xscreensaver.dpmsSuspend: 0:10:00
    xscreensaver.dpmsOff: 0:10:00
    EOF
  '';

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

  # --- Container ------------------------------------------------------------
  # Docker per i servizi (stack compose gestiti da Dockge, come sul VPS)
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;  # pulizia settimanale di immagini e container inutilizzati
      dates = "weekly";
    };
    # Log dei container: su NixOS vanno nel journal (driver journald), che ha
    # già i suoi limiti di spazio. NON aggiungere max-size/max-file: valgono
    # solo per il driver json-file e con journald Docker non parte.
  };

  # Podman resta per distrobox (rootless, per l'utente)
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;  # i container si vedono per nome
  };

  # Dockge: interfaccia web per gli stack in /opt/stacks (http://macmini:5001)
  virtualisation.oci-containers = {
    backend = "docker";
    containers.dockge = {
      image = "louislam/dockge:1";
      ports = [ "5001:5001" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/opt/dockge:/app/data"
        # Il percorso deve essere uguale dentro e fuori dal container
        "/opt/stacks:/opt/stacks"
      ];
      environment.DOCKGE_STACKS_DIR = "/opt/stacks";
    };
  };
  systemd.tmpfiles.rules = [
    "d /opt/stacks 0755 root root -"
    "d /opt/dockge 0755 root root -"
  ];

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

  # --- Aggiornamenti automatici ---------------------------------------------
  # Ogni notte: aggiornamenti del canale stabile (nixos-26.05) e rebuild da
  # /etc/nixos. Riavvia da solo SOLO se è cambiato il kernel, tra le 4 e le 6.
  # Ricorda: a dicembre 2026 passare al canale 26.11 (la 26.05 va fuori supporto).
  system.autoUpgrade = {
    enable = true;
    channel = "https://nixos.org/channels/nixos-26.05";
    dates = "04:00";
    randomizedDelaySec = "45min";
    allowReboot = true;
    rebootWindow = {
      lower = "04:00";
      upper = "06:00";
    };
  };

  # App Flatpak aggiornate ogni settimana
  systemd.services.flatpak-update = {
    description = "Aggiorna le app Flatpak";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig.Type = "oneshot";
    script = "flatpak update -y --noninteractive";
  };
  systemd.timers.flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

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
