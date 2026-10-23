"""Windows layer, imported first by every script in this skill (does nothing on a Mac or Linux).
- UTF-8 mode: without it Python reads and writes files in the system code page (cp1251/cp1252), which breaks Cyrillic
  brand files, transcripts and captions, and printing a ✅ crashes. The script re-runs itself once with -X utf8.
- Programs: `npx`/`node` are .cmd files on Windows, `nice` doesn't exist, and plain `bash` can be WSL's bash, not Git Bash.
  subprocess is taught to find the right one, so the scripts themselves stay the same as the Mac version.
- fcntl (file locks for the render queue) and os.symlink (needs admin rights on Windows: hard link / junction / copy) get Windows stand-ins.
- fontTools/OpenCV installed in ~/reels/.venv are found (a Windows venv keeps them in Lib/site-packages)."""
import os, sys

if os.name == "nt":
    import shutil, subprocess, types
    from pathlib import Path

    if not sys.flags.utf8_mode:
        sys.exit(subprocess.run([sys.executable, "-X", "utf8", *sys.argv]).returncode)

    _home = Path(os.environ.get("REELS_HOME", "~/reels")).expanduser()
    _sp = _home / ".venv" / "Lib" / "site-packages"
    if _sp.is_dir() and str(_sp) not in sys.path: sys.path.append(str(_sp))

    def _git_bash():
        for c in (os.environ.get("CLAUDE_CODE_GIT_BASH_PATH"), shutil.which("bash"),
                  r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files\Git\usr\bin\bash.exe",
                  os.path.expandvars(r"%LOCALAPPDATA%\Programs\Git\bin\bash.exe")):
            if c and os.path.isfile(c) and "system32" not in c.lower() and "windowsapps" not in c.lower(): return c
        return "bash"

    def _fix(args):
        if isinstance(args, (str, bytes)) or not args: return args
        a = [str(x) for x in args]
        if a[0] == "nice":                                   # nice -n 15 cmd ... -> cmd ...
            a = a[3:] if len(a) > 2 and a[1] == "-n" else a[1:]
        if a and a[0] == "bash": a[0] = _git_bash()
        elif a and not os.path.dirname(a[0]):
            w = shutil.which(a[0])                           # npx -> C:\Program Files\nodejs\npx.cmd
            if w: a[0] = w
        return a

    _Popen = subprocess.Popen
    class _WinPopen(_Popen):
        def __init__(self, args, *a, **k): super().__init__(_fix(args), *a, **k)
    subprocess.Popen = _WinPopen

    try: import fcntl  # noqa: F401  (never on Windows, but keep a real one if it exists)
    except ImportError:
        import msvcrt, time
        def flock(f, op):
            f.seek(0)
            while True:
                try: msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1); return
                except OSError:
                    if op & 4: raise BlockingIOError("locked")
                    time.sleep(0.2)
        sys.modules["fcntl"] = types.SimpleNamespace(flock=flock, LOCK_EX=2, LOCK_NB=4, LOCK_UN=8)

    # Symlinks need admin rights or Developer Mode, which a student's PC doesn't have. Never make one, even where it would
    # work (the CI runner is admin), so every machine takes the same path: a file becomes a hard link (a copy across
    # drives), a folder a junction (a copy if that fails). Python's rmtree removes a junction without touching its contents.
    def _link_or_copy(src, dst, *a, **k):
        src, dst = os.path.abspath(src), os.path.abspath(dst)
        if os.path.isdir(src):
            try:
                import _winapi; return _winapi.CreateJunction(src, dst)
            except OSError: return shutil.copytree(src, dst)
        try: return os.link(src, dst)
        except OSError: shutil.copy(src, dst)
    os.symlink = _link_or_copy
