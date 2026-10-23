#!/usr/bin/env python3
"""A capability-scoped companion bridge for PhotoCraft's public control protocol.

PhotoCraft must have been launched with --control, --control-token-file and both
automation roots set to the same --root used here. No app bundle is patched.
The default result is a soft selection. --output mask adds a non-destructive
layer mask only when the active layer does not already have one.

The host does not expose an atomic compare-revision-and-edit command. This
bridge checks revision, document identity, tab order and active layer around
each expensive operation, and immediately before applying. Avoid editing the
document while inference runs. Future incompatible hosts fail closed.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, wait
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import uuid


PROTOCOL = "PhotoCraft control JSON-lines"
REQUIRED_COMMANDS = {
    "session.inspect", "document.inspect", "document.activate", "file.close",
    "select.loadSelection", "layer.layerMask.revealSelection",
}
MAX_REPLY = 64 * 1024 * 1024


class BridgeError(RuntimeError):
    def __init__(self, message, kind="bridge"):
        super().__init__(message)
        self.kind = kind


class ControlClient:
    """One authenticated loopback connection, with no mutation retries."""

    def __init__(self, port, token_file, timeout=65):
        self.socket = None
        self.stream = None
        self.sequence = 0
        try:
            token = Path(token_file).read_text().strip()
        except OSError as error:
            raise BridgeError("Le fichier d’authentification est introuvable. Ouvrez PhotoCraft depuis le compagnon IA.", "connection") from error
        if len(token) != 64 or any(c not in "0123456789abcdefABCDEF" for c in token):
            raise BridgeError("Le fichier d’authentification PhotoCraft est invalide.", "authentication")
        try:
            self.socket = socket.create_connection(("127.0.0.1", port), timeout=timeout)
            self.stream = self.socket.makefile("rb")
            self.call("auth", {"token": token})
        except (OSError, BridgeError):
            self.close()
            raise

    def close(self):
        if self.stream is not None:
            self.stream.close()
            self.stream = None
        if self.socket is not None:
            self.socket.close()
            self.socket = None

    def call(self, method, params=None):
        self.sequence += 1
        request = {"id": self.sequence, "method": method, "params": params or {}}
        try:
            self.socket.sendall(json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode() + b"\n")
            line = self.stream.readline(MAX_REPLY + 1)
        except socket.timeout as error:
            raise BridgeError("PhotoCraft ne répond pas. Une commande peut encore s’exécuter ; vérifiez le document avant de recommencer.", "timeout") from error
        except OSError as error:
            raise BridgeError("La connexion à PhotoCraft a été interrompue.", "connection") from error
        if not line or len(line) > MAX_REPLY or not line.endswith(b"\n"):
            raise BridgeError("Réponse PhotoCraft vide ou trop volumineuse.", "protocol")
        try:
            reply = json.loads(line)
        except (ValueError, UnicodeDecodeError) as error:
            raise BridgeError("Réponse PhotoCraft invalide.", "protocol") from error
        if not isinstance(reply, dict) or reply.get("id") != self.sequence or not isinstance(reply.get("ok"), bool):
            raise BridgeError("La version de PhotoCraft utilise un protocole incompatible.", "protocol")
        if not reply["ok"]:
            message = str(reply.get("error", "Commande refusée par PhotoCraft."))
            # Never re-send a command on an ambiguous host timeout.
            raise BridgeError("PhotoCraft : " + message, "host")
        return reply.get("result")

    def execute(self, command, params=None):
        return self.call("engine.execute", {"command": command, "params": params or {}})

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def flatten_layers(layers):
    result = []
    for layer in layers:
        result.append(layer)
        result.extend(flatten_layers(layer.get("children", [])))
    return result


def document_key(document):
    """Conservative identity; the protocol exposes no immutable document UUID."""
    try:
        return (
            document["name"], document.get("path"), document["width"], document["height"],
            document["mode"], document["depth"], document["revision"], document["activeLayer"],
            tuple(layer["id"] for layer in flatten_layers(document["layers"])),
        )
    except (KeyError, TypeError) as error:
        raise BridgeError("Les informations du document sont incompatibles avec cette version du compagnon.", "compatibility") from error


def session_key(session):
    try:
        return tuple((d["index"], d["name"], d.get("path"), d["width"], d["height"], d["revision"]) for d in session["documents"])
    except (KeyError, TypeError) as error:
        raise BridgeError("La liste des documents PhotoCraft est incompatible.", "compatibility") from error


def inspect_ready(client, require_document=True):
    state = client.call("ui.inspect")
    if not isinstance(state, dict) or not isinstance(state.get("session"), dict):
        raise BridgeError("Impossible de lire la session PhotoCraft.", "compatibility")
    if require_document:
        if not isinstance(state.get("document"), dict) or state["session"].get("active") is None:
            raise BridgeError("Ouvrez une photo dans PhotoCraft avant de lancer le détourage.", "document")
        jobs = state.get("jobs")
        if not isinstance(jobs, dict) or any(not isinstance(jobs.get(key), list) for key in ("running", "opening", "saving")):
            raise BridgeError("Les informations des opérations PhotoCraft sont incompatibles.", "compatibility")
        if state.get("dialogs") or state.get("cameraRaw") or jobs.get("focus") is not None or any(jobs[key] for key in ("running", "opening", "saving")):
            raise BridgeError("Terminez la boîte de dialogue ou l’opération en cours dans PhotoCraft.", "busy")
        if state["document"].get("quickMask"):
            raise BridgeError("Quittez le mode Masque rapide avant de lancer le détourage.", "document")
        document_key(state["document"])
    return state


def check_capabilities(client):
    commands = client.call("engine.commands")
    if not isinstance(commands, list):
        raise BridgeError("Le registre de commandes PhotoCraft est incompatible.", "compatibility")
    available = {command.get("id") for command in commands if isinstance(command, dict)}
    missing = sorted(REQUIRED_COMMANDS - available)
    if missing:
        raise BridgeError("Mise à jour PhotoCraft incompatible : commandes absentes : " + ", ".join(missing), "compatibility")
    state = inspect_ready(client, require_document=False)
    document = state.get("document")
    return {
        "ok": True, "compatible": True, "protocol": PROTOCOL,
        "activeDocument": document.get("name") if isinstance(document, dict) else None,
    }


def assert_unchanged(client, initial, require_active=True):
    state = inspect_ready(client)
    if session_key(state["session"]) != session_key(initial["session"]):
        raise BridgeError("Les documents ont changé pendant le calcul. Relancez le détourage sur la photo souhaitée.", "stale")
    if require_active and state["session"]["active"] != initial["session"]["active"]:
        raise BridgeError("Le document actif a changé pendant le calcul. Aucun résultat n’a été appliqué.", "stale")
    if document_key(state["document"]) != document_key(initial["document"]):
        raise BridgeError("La photo ou le calque actif a changé pendant le calcul. Aucun résultat n’a été appliqué.", "stale")
    return state


def png_info(path, mask=False):
    try:
        with Path(path).open("rb") as handle:
            header = handle.read(33)
    except OSError as error:
        raise BridgeError("Le moteur n’a pas produit le fichier PNG attendu.", "engine") from error
    if len(header) != 33 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise BridgeError("Le résultat du moteur n’est pas une image PNG valide.", "engine")
    width, height, depth, color = struct.unpack(">IIBB", header[16:26])
    if width < 1 or height < 1 or depth not in (8, 16):
        raise BridgeError("Les dimensions ou la profondeur du PNG sont invalides.", "engine")
    if mask and color != 0:
        raise BridgeError("Le moteur doit produire un masque PNG en niveaux de gris, sans canal alpha.", "engine")
    return width, height


def active_mask_target(document):
    layer = next((layer for layer in flatten_layers(document["layers"]) if layer["id"] == document["activeLayer"]), None)
    if layer is None:
        raise BridgeError("Sélectionnez un calque avant de créer son masque.", "document")
    if layer.get("hasMask"):
        raise BridgeError("Ce calque possède déjà un masque. Choisissez « Sélection » pour préserver ce masque.", "document")
    return layer["id"]


def verify_original(client, initial, expected_revision=None):
    """Read a specified original without changing the active tab."""
    index = initial["session"]["active"]
    current = client.execute("document.inspect", {"document": index})
    expected = dict(initial["document"])
    if expected_revision is not None:
        expected["revision"] = expected_revision
    if document_key(current) != document_key(expected):
        raise BridgeError("La photo a été modifiée pendant l’import du masque. Le résultat est conservé en PNG.", "stale")
    return current


def cleanup_matte(client, matte_index, matte_key, initial=None):
    """Only close our own unchanged temporary document; never discard user work."""
    session = client.execute("session.inspect")
    rows = session.get("documents", [])
    if matte_index >= len(rows) or rows[matte_index].get("dirty") is not False:
        return False
    document = client.execute("document.inspect", {"document": matte_index})
    if document_key(document) != matte_key:
        return False
    # Session.close keeps an earlier active tab, but when closing the active last
    # tab it chooses the preceding tab. During an import failure that may not be
    # the original photo. Restore it only while it is still unchanged and our own
    # temporary tab was active; never override a user-selected different tab.
    restore_original = False
    if initial is not None and session.get("active") == matte_index:
        try:
            verify_original(client, initial)
            restore_original = True
        except BridgeError:
            pass
    client.execute("file.close", {"document": matte_index})
    if restore_original:
        verify_original(client, initial)
        client.execute("document.activate", {"document": initial["session"]["active"]})
    return True


def run_inference(client, runner, arguments, interval=10):
    """Keep the authenticated channel alive during a slow local inference.

    PhotoCraft closes idle control sockets after 30 seconds. Only the main
    thread touches the client, using read-only session.inspect; no edit is ever
    retried. If a ping fails, wait for the bounded worker to finish before
    cleaning up its input, then propagate the error without applying a mask.
    """
    with ThreadPoolExecutor(max_workers=1, thread_name_prefix="matting") as pool:
        future = pool.submit(runner, arguments, capture_output=True, text=True, timeout=600, check=False)
        while not wait([future], timeout=interval).done:
            client.execute("session.inspect")
        return future.result()


def run_cutout(client, root, engine, mode="person", output="selection", runner=subprocess.run):
    check_capabilities(client)
    initial = inspect_ready(client)
    original_index = initial["session"]["active"]
    document = initial["document"]
    target_layer = active_mask_target(document) if output == "mask" else None
    width, height = document["width"], document["height"]
    root = Path(root).resolve()
    if not root.is_dir():
        raise BridgeError("Le dossier de travail du compagnon est introuvable.", "configuration")
    if not Path(engine).is_file() or not os.access(engine, os.X_OK):
        raise BridgeError("Le moteur de détourage est absent ou non exécutable.", "configuration")
    job = root / ("job-" + uuid.uuid4().hex)
    job.mkdir(mode=0o700)
    input_path, matte_path = job / "input.png", job / "matte.png"
    relative_input, relative_matte = input_path.relative_to(root).as_posix(), matte_path.relative_to(root).as_posix()
    matte_index, matte_key = None, None
    success = False
    cleanup_warning = None
    try:
        # A flat automation save is a copy: it neither retargets nor marks the source saved.
        client.call("app.save", {"path": relative_input})
        assert_unchanged(client, initial)
        if png_info(input_path) != (width, height):
            raise BridgeError("L’export PhotoCraft n’a pas les dimensions attendues.", "compatibility")
        try:
            completed = run_inference(client, runner, [str(engine), "--input", str(input_path), "--mask", str(matte_path), "--mode", mode])
        except subprocess.TimeoutExpired as error:
            raise BridgeError("Le calcul du détourage a dépassé dix minutes. Aucun résultat n’a été appliqué.", "engine") from error
        if completed.returncode:
            detail = (completed.stderr or completed.stdout or "").strip()[-1500:]
            raise BridgeError("Le moteur de détourage a échoué." + (" " + detail if detail else ""), "engine")
        if png_info(matte_path, mask=True) != (width, height):
            raise BridgeError("Le masque ne correspond pas aux dimensions de la photo.", "engine")
        assert_unchanged(client, initial)
        client.call("app.open", {"path": relative_matte})
        imported = inspect_ready(client)
        matte_index = imported["session"]["active"]
        count = len(initial["session"]["documents"])
        # Opening a file must append exactly one tab. A changed host must not redirect edits.
        if matte_index != count or len(imported["session"]["documents"]) != count + 1:
            matte_index = None
            raise BridgeError("PhotoCraft a changé l’ordre des documents pendant l’import. Aucun masque n’a été appliqué.", "stale")
        matte_doc = imported["document"]
        # Automation may report a sandbox-relative path rather than an absolute
        # filesystem path. Both are scoped to this launch's automation root.
        if not matte_doc.get("path") or (root / matte_doc["path"]).resolve() != matte_path.resolve():
            matte_index = None
            raise BridgeError("Le document ouvert ne correspond pas au masque temporaire. Aucun résultat n’a été appliqué.", "stale")
        matte_key = document_key(matte_doc)
        if (matte_doc["width"], matte_doc["height"]) != (width, height):
            raise BridgeError("PhotoCraft a importé le masque avec des dimensions inattendues.", "compatibility")
        if matte_doc["mode"] != "Grayscale" or matte_doc["activeLayer"] is None:
            raise BridgeError("PhotoCraft n’a pas conservé les niveaux de gris du masque. Aucun résultat n’a été appliqué.", "compatibility")
        if session_key(imported["session"])[:count] != session_key(initial["session"]):
            raise BridgeError("Un document a changé pendant l’import du masque.", "stale")
        verify_original(client, initial)
        client.execute("document.activate", {"document": original_index})
        state = inspect_ready(client)
        if state["session"]["active"] != original_index or document_key(state["document"]) != document_key(document):
            raise BridgeError("La photo active a changé avant l’application. Aucun résultat n’a été appliqué.", "stale")
        if output == "mask":
            active_mask_target(state["document"])
        # Raw grayscale channel values become continuous selection coverage, never a threshold.
        selected = client.execute("select.loadSelection", {"document": matte_index, "layer": matte_doc["activeLayer"], "channel": "composite", "operation": "new"})
        if isinstance(selected, dict) and selected.get("selected") is False:
            raise BridgeError("Aucun sujet détecté. Essayez l’autre mode de détourage.", "empty")
        if output == "mask":
            # One selection edit occurred; any extra revision signals concurrent user work.
            verify_original(client, initial, expected_revision=document["revision"] + 1)
            client.execute("layer.layerMask.revealSelection", {"layer": target_layer})
        success = True
        result = {"ok": True, "output": output, "mode": mode, "width": width, "height": height,
                  "document": document["name"], "protocol": PROTOCOL,
                  "matte": str(matte_path), "job": str(job)}
        return result
    finally:
        if matte_index is not None and matte_key is not None:
            try:
                if not cleanup_matte(client, matte_index, matte_key, initial):
                    cleanup_warning = "Le document temporaire a été conservé car il a été modifié."
            except (BridgeError, OSError):
                cleanup_warning = "Le masque temporaire reste ouvert dans PhotoCraft."
        # Keep only an unsuccessful matte for recovery; input contains the user's photo.
        try:
            input_path.unlink(missing_ok=True)
        except OSError:
            pass
        if success:
            if cleanup_warning:
                result["warning"] = cleanup_warning
        elif not matte_path.exists():
            shutil.rmtree(job, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Détourage IA pour PhotoCraft, via son protocole public.")
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--engine")
    parser.add_argument("--mode", choices=("person", "subject"), default="person")
    parser.add_argument("--output", choices=("selection", "mask"), default="selection")
    parser.add_argument("--diagnose", action="store_true")
    args = parser.parse_args(argv)
    try:
        if not 1 <= args.port <= 65535:
            raise BridgeError("Port PhotoCraft invalide.", "configuration")
        if not args.diagnose and not args.engine:
            raise BridgeError("Le chemin du moteur de détourage est requis.", "configuration")
        with ControlClient(args.port, args.token_file) as client:
            result = check_capabilities(client) if args.diagnose else run_cutout(client, args.root, args.engine, args.mode, args.output)
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except BridgeError as error:
        print(json.dumps({"ok": False, "error": str(error), "kind": error.kind}, ensure_ascii=False))
        return 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({"ok": False, "error": "Impossible de terminer le détourage : " + str(error), "kind": "connection" if isinstance(error, OSError) else "compatibility"}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    sys.exit(main())
