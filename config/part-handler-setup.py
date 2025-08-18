#part-handler

import base64
from io import StringIO

import pathlib
from typing import Any

from cloudinit.cloud import Cloud

def list_types():
    return(["application/x-setup-config", "application/x-provision-config", "application/x-per-boot", "application/x-provision-file"])

def handle_part(data: Cloud, ctype: str, filename: str, payload: Any):
    configdir = pathlib.Path("/var/lib/cloud/instance/config")
    provisiondir = pathlib.Path("/var/lib/cloud/instance/provision")
    perbootdir = pathlib.Path("/var/lib/cloud/scripts/per-boot")

    if ctype == "__begin__":
        configdir.mkdir(parents=True, exist_ok=True)
        provisiondir.mkdir(parents=True, exist_ok=True)
        perbootdir.mkdir(parents=True, exist_ok=True)
        return

    if ctype == "__end__":
        return
    
    file = None
    content = None

    if ctype == "application/x-setup-config":
        file = configdir.joinpath(filename.strip())
        content = payload
    
    if ctype == "application/x-provision-config":
        file = provisiondir.joinpath(filename.strip())
        content = payload
    
    if ctype == "application/x-per-boot":
        file = perbootdir.joinpath(filename.strip())
        content = payload
    
    if ctype == "application/x-provision-file":
        with StringIO(payload.decode('utf-8')) as bio:
            path = bio.readline().strip()
            pathobj = provisiondir.joinpath(path)
            pathobj.mkdir(parents=True, exist_ok=True)
            file = pathobj.joinpath(filename.strip())
            content = base64.b64decode(bio.readline())

    file.touch()
    file.chmod(0o600)
    with file.open("wb") as f:
        f.write(content)
