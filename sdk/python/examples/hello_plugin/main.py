#!/usr/bin/env python3
"""Hello Plugin — lists sandboxes when initialized."""

import sys
import os

# Add the SDK to the path (for development; in production use pip install)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from sbx_plugin import SbxPlugin

plugin = SbxPlugin()


@plugin.on("initialize")
async def on_init(params):
    sandboxes = await plugin.sandbox.list()
    await plugin.ui.log(f"Hello from Python plugin! Found {len(sandboxes)} sandbox(es).")

    for sb in sandboxes:
        await plugin.ui.log(f"  - {sb.name} [{sb.status}] workspace: {sb.workspace}")


@plugin.on("event/onSandboxStopped")
async def on_sandbox_stopped(params):
    await plugin.ui.log(f"Sandbox stopped: {params.get('name', 'unknown')}")


plugin.start()
