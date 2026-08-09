#!/usr/bin/env python3
"""Mission OS P15/P16 QEMU monitor driver (named interaction sequences).

Usage: p15-run.py <sequence>

Sequences (each is a full canned interaction; all text is hardcoded here so
nothing passes through shell quoting):

  probe-grub   type GRUB rescue commands, snap each result
  login        ctrl-alt-f2, login as root/mission on tty2
  run-verify   mount evidence disk, run verify.sh, poweroff
  wait30       idle 30s then snap (general purpose)
  snapnow      snap a frame named snapnow

Output frames: <EVID>/frames/<name>.ppm
"""
import os
import socket
import sys
import time

SOCK = "/tmp/p15-monitor.sock"
# Evidence directory (host-specific; override with MOS_EVID).
EVID = os.environ.get("MOS_EVID", os.path.expanduser("~/mos-audit-evidence/p15-p16"))
# Root password for the throwaway QEMU test VM only (never shipped).
# Must be provided by the operator when re-running the login sequences.
ROOT_PW = os.environ.get("MOS_TEST_ROOT_PW") or "<set-MOS_TEST_ROOT_PW>"

KEYS = {
    " ": "spc", "/": "slash", ".": "dot", "-": "minus", "_": "shift-minus",
    "=": "equal", "+": "shift-equal", ":": "shift-semicolon", ";": "semicolon",
    ",": "comma", "(": "shift-9", ")": "shift-0", "'": "apostrophe",
    '"': "shift-apostrophe", "*": "shift-8", "&": "shift-7", "!": "shift-1",
    "@": "shift-2", "#": "shift-3", "$": "shift-4", "%": "shift-5",
    "^": "shift-6", "~": "shift-grave_accent", "`": "grave_accent",
    "<": "less", ">": "shift-less", "?": "shift-slash", "\\": "backslash",
}


def send(cmd, delay=0.15):
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
    out = data.decode("utf-8", errors="replace").strip()
    if out and "error" in out.lower():
        print("MON: " + out[:300])
    return out


def snap(name):
    send("screendump %s/frames/%s.ppm" % (EVID, name))
    print("SNAP %s" % name)


def wait(secs):
    time.sleep(secs)


def typ(text):
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
        time.sleep(0.07)


def k(keys):
    send("sendkey " + keys)


SEQ = {
    "probe-grub": [
        ("type", "ls"), ("key", "ret"), ("w", 1), ("snap", "grub-ls"),
        ("type", "ls (hd0,gpt1)/"), ("key", "ret"), ("w", 1), ("snap", "grub-gpt1"),
        ("type", "ls (hd0,gpt2)/"), ("key", "ret"), ("w", 1), ("snap", "grub-gpt2"),
        ("type", "ls (hd0,gpt2)/boot/grub/"), ("key", "ret"), ("w", 1), ("snap", "grub-grubdir"),
    ],
    "login": [
        ("key", "ctrl-alt-f2"), ("w", 2), ("snap", "login-tty2-a"),
        ("type", "root"), ("key", "ret"), ("w", 1), ("snap", "login-user"),
        ("type", ROOT_PW), ("key", "ret"), ("w", 2), ("snap", "login-shell"),
    ],
    "run-verify": [
        ("type", "mkdir -p /mnt/v"), ("key", "ret"), ("w", 1),
        ("type", "mount /dev/vdb /mnt/v"), ("key", "ret"), ("w", 1),
        ("type", "bash /mnt/v/verify.sh"), ("key", "ret"), ("w", 7), ("snap", "verify-done"),
        ("type", "poweroff"), ("key", "ret"), ("w", 3), ("snap", "poweroff"),
    ],
    "manual-chain": [
        ("key", "ret"), ("w", 0.5),
        ("type", "set root=(hd0,gpt2)"), ("key", "ret"), ("w", 1), ("snap", "chain-1"),
        ("type", "set prefix=(hd0,gpt2)/boot/grub"), ("key", "ret"), ("w", 1), ("snap", "chain-2"),
        ("type", "insmod normal"), ("key", "ret"), ("w", 1), ("snap", "chain-3"),
        ("type", "normal"), ("key", "ret"), ("w", 5), ("snap", "chain-4"),
    ],
    "konsole": [
        ("key", "alt-f2"), ("w", 3), ("snap", "konsole-1"),
        ("type", "konsole"), ("key", "ret"), ("w", 4), ("snap", "konsole-2"),
    ],
    "su-root": [
        ("type", "su -"), ("key", "ret"), ("w", 2), ("snap", "su-1"),
        ("type", ROOT_PW), ("key", "ret"), ("w", 3), ("snap", "su-2"),
    ],
    "probe-set": [
        ("type", "set"), ("key", "ret"), ("w", 1), ("snap", "probe-set-1"),
        ("type", "configfile (hd0,gpt1)/EFI/MISSION_OS/grub.cfg"), ("key", "ret"), ("w", 4), ("snap", "probe-set-2"),
    ],
    "vt2": [("key", "ctrl-alt-f2"), ("w", 3), ("snap", "vt2-1")],
    "wait30": [("w", 30), ("snap", "idle30")],
    "snapnow": [("snap", "snapnow")],
}


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "snapnow"
    if name == "quit":
        send("quit")
        return
    if name == "poweroff":
        send("system_powerdown")
        return
    if name == "reset":
        send("system_reset")
        return
    if name == "burst":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        gap = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
        for i in range(n):
            snap("b%02d" % i)
            if i < n - 1:
                wait(gap)
        return
    if name not in SEQ:
        print("unknown sequence: %s" % name)
        sys.exit(1)
    for step in SEQ[name]:
        kind = step[0]
        arg = step[1]
        if kind == "type":
            typ(arg)
        elif kind == "key":
            k(arg)
        elif kind == "w":
            wait(arg)
        elif kind == "snap":
            snap(arg)


if __name__ == "__main__":
    main()
