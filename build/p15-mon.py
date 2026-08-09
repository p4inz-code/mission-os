#!/usr/bin/env python3
"""Mission OS P15/P16 QEMU monitor driver.

Usage:
  p15-mon.py <cmd> [args...]

Commands:
  snap <name>          screendump to EVID/frames/<name>.ppm
  type <text>          type text (letters, digits, spc - / . _) via sendkey
  wait <seconds>       sleep
  sendkey <keys>       raw sendkey (e.g. ret, ctrl-alt-f2)
  anything else        sent verbatim as a QEMU monitor command
"""
import os
import socket
import sys
import time

SOCK = "/tmp/p15-monitor.sock"
# Evidence directory (host-specific; override with MOS_EVID).
EVID = os.environ.get("MOS_EVID", os.path.expanduser("~/mos-audit-evidence/p15-p16"))

KEYS = {
    " ": "spc", "/": "slash", ".": "dot", "-": "minus", "_": "shift-minus",
    "=": "equal", "+": "shift-equal", ":": "shift-semicolon", ";": "semicolon",
    ",": "comma", "(": "shift-9", ")": "shift-0", "'": "apostrophe",
    '"': "shift-apostrophe", "*": "shift-8", "&": "shift-7", "!": "shift-1",
    "@": "shift-2", "#": "shift-3", "$": "shift-4", "%": "shift-5",
    "^": "shift-6", "~": "shift-grave_accent", "`": "grave_accent",
    "<": "less", ">": "shift-less", "?": "shift-slash", "\\": "backslash",
}


def send(cmd, delay=0.12):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(SOCK)
    s.sendall((cmd + "\n").encode())
    time.sleep(delay)
    data = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
            if len(chunk) < 65536:
                break
    except socket.timeout:
        pass
    s.close()
    return data.decode("utf-8", errors="replace")


def main():
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a == "snap":
            i += 1
            name = args[i]
            send("screendump %s/frames/%s.ppm" % (EVID, name))
        elif a == "type":
            i += 1
            text = args[i]
            for ch in text:
                if ch.isalpha():
                    if ch.isupper():
                        send("sendkey shift-" + ch.lower())
                    else:
                        send("sendkey " + ch)
                elif ch.isdigit():
                    send("sendkey " + ch)
                elif ch in KEYS:
                    send("sendkey " + KEYS[ch])
                elif ch == "\n":
                    send("sendkey ret")
                else:
                    print("UNMAPPED char: %r" % ch)
                time.sleep(0.06)
        elif a == "wait":
            i += 1
            time.sleep(float(args[i]))
        else:
            out = send(a)
            if out.strip():
                print(out.strip())
        i += 1


if __name__ == "__main__":
    main()
