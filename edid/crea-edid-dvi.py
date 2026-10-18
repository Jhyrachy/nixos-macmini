#!/usr/bin/env python3
"""Trasforma un EDID HDMI in un EDID "solo DVI".

Tiene solo il blocco base (128 byte), azzera il numero di estensioni
(via il blocco CTA-861 che dichiara HDMI/YCbCr) e ricalcola il checksum.

Uso:  python3 crea-edid-dvi.py originale.bin nuovo-dvi.bin
Su NixOS senza python:  nix-shell -p python3 --run "python3 crea-edid-dvi.py a.bin b.bin"
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, "rb").read()[:128])
if len(d) != 128 or d[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
    sys.exit(f"{src}: non sembra un EDID valido")
d[126] = 0                      # nessun blocco di estensione
d[127] = (-sum(d[:127])) % 256  # checksum: la somma dei 128 byte deve fare 0 mod 256
open(dst, "wb").write(d)
print(f"{dst} creato (128 byte, estensioni rimosse)")
