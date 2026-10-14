"""Windows: Python reads and writes files in the system code page unless UTF-8 mode is on, which breaks Cyrillic
brand files, transcripts and captions. Importing this module re-runs the script in UTF-8 mode once."""
import os, subprocess, sys
if os.name == "nt" and not sys.flags.utf8_mode:
    sys.exit(subprocess.run([sys.executable, "-X", "utf8", *sys.argv]).returncode)
