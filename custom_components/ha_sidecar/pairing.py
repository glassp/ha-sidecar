"""Client side of the pairing handshake with a tablet (docs/PAIRING.md)."""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
from dataclasses import dataclass
from typing import Any

import aiohttp
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

INFO = b"ha-sidecar-pair-v1"
DEFAULT_PORT = 8750


class PairingError(Exception):
    """`code` is a key under config.error in strings.json."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def normalize_code(code: str) -> str:
    """Codes are typed by people: ignore case, dashes and spaces."""
    return "".join(ch for ch in code.upper() if ch.isalnum())


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def _unb64(data: str) -> bytes:
    return base64.b64decode(data)


@dataclass
class Tablet:
    device_id: str
    name: str
    model: str


class TabletPairing:
    """One handshake: `hello` (keys + comparison number) then `finish` (authorise + hand over credentials)."""

    def __init__(self, session: aiohttp.ClientSession, host: str, port: int) -> None:
        self._http = session
        self._base = f"http://[{host}]:{port}" if ":" in host else f"http://{host}:{port}"
        self._session_id = ""
        self._enc = b""
        self._mac = b""
        self.sas = ""
        self.tablet: Tablet | None = None

    async def _request(self, method: str, path: str, body: dict[str, Any] | None = None, timeout: float = 10) -> dict:
        try:
            async with self._http.request(
                method, f"{self._base}/pair/v1/{path}", json=body, timeout=aiohttp.ClientTimeout(total=timeout)
            ) as resp:
                data = await resp.json(content_type=None)
                if resp.status != 200:
                    raise PairingError(str(data.get("error", "pairing_failed")) if isinstance(data, dict) else "pairing_failed")
                return data
        except PairingError:
            raise
        except (aiohttp.ClientError, asyncio.TimeoutError, ValueError) as err:
            raise PairingError("cannot_connect") from err

    async def info(self) -> Tablet:
        data = await self._request("GET", "info")
        if not data.get("id"):
            raise PairingError("bad_response")
        if data.get("pairing") is False:
            raise PairingError("not_pairing")
        return Tablet(str(data["id"]), str(data.get("name") or data["id"]), str(data.get("model") or ""))

    async def hello(self, ha_name: str, mode: str) -> Tablet:
        """Exchange keys. In `confirm` mode the tablet now shows [sas] and asks its user to allow."""
        key = ec.generate_private_key(ec.SECP256R1())
        nonce = os.urandom(16)
        data = await self._request(
            "POST",
            "hello",
            {
                "v": 1,
                "mode": mode,
                "ha_name": ha_name,
                "ha_nonce": _b64(nonce),
                "ha_pub": _b64(key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)),
            },
        )
        try:
            peer = serialization.load_der_public_key(_unb64(data["tablet_pub"]))
            tablet_nonce = _unb64(data["tablet_nonce"])
            shared = key.exchange(ec.ECDH(), peer)  # type: ignore[arg-type]
            okm = HKDF(algorithm=hashes.SHA256(), length=68, salt=nonce + tablet_nonce, info=INFO).derive(shared)
            self._session_id = data["session"]
        except (KeyError, ValueError, TypeError) as err:
            raise PairingError("bad_response") from err
        self._enc, self._mac = okm[:32], okm[32:64]
        self.sas = f"{int.from_bytes(okm[64:68], 'big') % 1_000_000:06d}"
        self.tablet = Tablet(str(data["id"]), str(data.get("name") or data["id"]), str(data.get("model") or ""))
        return self.tablet

    async def finish(self, credentials: dict[str, Any], code: str | None) -> None:
        """Authorise (with the tablet's [code], or the user's Allow in confirm mode) and send the credentials."""
        iv = os.urandom(12)
        sealed = AESGCM(self._enc).encrypt(iv, json.dumps(credentials).encode(), INFO + self._session_id.encode())
        body: dict[str, Any] = {"session": self._session_id, "iv": _b64(iv), "ct": _b64(sealed)}
        if code is not None:
            body["proof"] = _b64(hmac.new(self._mac, b"ha-proof\x00" + normalize_code(code).encode(), hashlib.sha256).digest())
        # confirm mode waits for the person at the tablet
        await self._request("POST", "finish", body, timeout=100)
