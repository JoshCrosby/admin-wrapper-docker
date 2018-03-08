#!/usr/bin/env python3
# vim:set expandtab ts=4 sw=4 ai ft=python:
#
# This is an "outside" container script, that pulls in the repo built
# version and then runs the inside scripts
#
# Derived from Protos Library; License by GNU Affrero; Created 2017 Brandon Gillespie

import os
import os.path
import sys
import subprocess
import pwd

SVC_USER = "jenkins"
SVC_USER_HOME = os.path.expanduser("~" + SVC_USER)
MY_HOME = os.path.expanduser("~")
SUDO_HOME = MY_HOME
if os.environ.get("SUDO_USER"):
    SUDO_HOME = os.path.expanduser("~" + os.environ.get("SUDO_USER"))

def DEBUG(*args):
    if os.getenv('DEBUG'):
        sys.stderr.write("DEBUG: " + args[0].format(*args[1:]) + "\n")

def run_or_die(*exc, **kwargs):
    out = run_capture(*exc, **kwargs)
    if out['error']:
        print(out['output'])
        print(out['err'])
        sys.exit(1)

def run(*exc, **kwargs):
    if len(exc) == 1:
        exc = exc[0]
        kwargs['shell'] = True
    else:
        exc = list(exc)
    DEBUG("run>>> {}", exc)
    return subprocess.call(exc, **kwargs)

def run_capture(*exc, **kwargs):
    kwargs['stderr'] = subprocess.PIPE
    kwargs['stdout'] = subprocess.PIPE
    if len(exc) == 1:
        exc = exc[0]
        kwargs['shell'] = True
    else:
        exc = list(exc)

    DEBUG("runc>>> {}", exc)
    sys.stdout.flush()
    sys.stderr.flush()
    sub = subprocess.Popen(exc, **kwargs)
    output, outerr = sub.communicate()
    if isinstance(output, bytes): # grr python 2/3
        output = output.decode()
    if isinstance(outerr, bytes): # grr python 2/3
        outerr = outerr.decode()
    return {'code': sub.returncode, 'error': sub.returncode != 0, 'out': output, 'err': outerr or ''}

def whoami():
    return pwd.getpwuid(os.getuid())[0]

def as_svc_user(func, *exc):
    curuser = whoami()

    if curuser != SVC_USER:
        exc = ["sudo", "-s", "-H", "-u", SVC_USER] + list(exc)
        return func(*exc)
    return func(*exc)

