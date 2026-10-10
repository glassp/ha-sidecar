"""Starts the lab Home Assistant without the crash at exit:  python run_hass.py -c ./config --skip-pip

Some of Home Assistant's compiled extensions (Bluetooth, pyobjc, ... on macOS with Python 3.14) segfault while the interpreter tears
its modules down at exit, which macOS reports as "Python quit unexpectedly" every time the lab is stopped or restarted. Home Assistant
itself has shut down cleanly by then, so this wrapper lets it finish, flushes the logs and leaves with os._exit, which skips that
teardown. Stop the lab with SIGTERM (`pkill -f run_hass.py`) so that Home Assistant saves its state first.
"""

import logging
import os
import sys

from homeassistant.__main__ import main

code = main()
logging.shutdown()
sys.stdout.flush()
sys.stderr.flush()
os._exit(code if isinstance(code, int) else 0)
