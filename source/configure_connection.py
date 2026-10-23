#!/usr/bin/env python3
"""Enable PhotoCraft's documented control environment for normal GUI launches.
No running application is stopped, no document is read, no token is printed.
"""
import os
from pathlib import Path
import plistlib
import shlex
import subprocess


def install():
    support = Path.home() / 'Library/Application Support/ArtCraft Detourage IA'
    support.mkdir(parents=True, exist_ok=True, mode=0o700)
    values = {
        'PHOTOCRAFT_CONTROL_PORT': '47863',
        'PHOTOCRAFT_CONTROL_TOKEN_FILE': str(support / 'control.token'),
        'PHOTOCRAFT_AUTOMATION_READ_ROOT': str(support / 'work'),
        'PHOTOCRAFT_AUTOMATION_WRITE_ROOT': str(support / 'work'),
    }
    script = support / 'connection-environment.command'
    content = '#!/bin/sh\nset -eu\n' + ''.join('/bin/launchctl setenv '+shlex.quote(k)+' '+shlex.quote(v)+'\n' for k,v in values.items())
    if not script.exists() or script.read_text() != content:
        script.write_text(content)
    script.chmod(0o700)
    agents = Path.home() / 'Library/LaunchAgents'
    agents.mkdir(parents=True,exist_ok=True)
    label = 'local.artcraft.detourage-connection'
    plist = agents / (label+'.plist')
    payload = plistlib.dumps({'Label':label,'ProgramArguments':['/bin/sh',str(script)],'RunAtLoad':True})
    if not plist.exists() or plist.read_bytes() != payload:
        plist.write_bytes(payload)
    plist.chmod(0o600)
    # Set this GUI session immediately; RunAtLoad repeats it after each login.
    for key,value in values.items():
        subprocess.run(['/bin/launchctl','setenv',key,value],check=True,capture_output=True)
    domain = 'gui/'+str(os.getuid())
    loaded = subprocess.run(['/bin/launchctl','print',domain+'/'+label],capture_output=True)
    if loaded.returncode:
        subprocess.run(['/bin/launchctl','bootstrap',domain,str(plist)],check=True,capture_output=True)
    for key,value in values.items():
        result=subprocess.run(['/bin/launchctl','getenv',key],check=True,capture_output=True,text=True)
        if result.stdout.strip()!=value:raise RuntimeError('Configuration de connexion non appliquée')
    print('Connexion des prochains lancements PhotoCraft configurée.')


if __name__=='__main__':
    install()
