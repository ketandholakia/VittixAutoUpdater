import base64
import hashlib
import importlib.util
import json
import re
from pathlib import Path

import pytest

cryptography = pytest.importorskip("cryptography")
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature


SCRIPT = Path(__file__).resolve().parents[1] / "generate_manifest.py"
SPEC = importlib.util.spec_from_file_location("vittix_manifest_generator", SCRIPT)
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)
VECTOR = json.loads(
    (Path(__file__).parent / "vectors" / "manifest-signature-vector.json").read_text()
)


def test_shared_delphi_signature_vector():
    manifest_bytes = bytes.fromhex(VECTOR["manifest_hex"])
    public_hex = VECTOR["public_key_xy_hex"]
    assert generator.signing_key_id(public_hex) == VECTOR["key_id"]
    signature = base64.b64decode(VECTOR["signature_base64"], validate=True)
    r = int.from_bytes(signature[:32], "big")
    s = int.from_bytes(signature[32:], "big")
    public_bytes = bytes.fromhex(public_hex)
    public_key = ec.EllipticCurvePublicNumbers(
        int.from_bytes(public_bytes[:32], "big"),
        int.from_bytes(public_bytes[32:], "big"),
        ec.SECP256R1(),
    ).public_key()
    public_key.verify(
        encode_dss_signature(r, s), manifest_bytes, ec.ECDSA(hashes.SHA256())
    )


def test_generator_key_id_is_sha256_of_raw_xy():
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_hex = generator.public_key_xy_hex(private_key)
    assert generator.signing_key_id(public_hex) == hashlib.sha256(
        bytes.fromhex(public_hex)
    ).hexdigest()


def test_manifest_generator_writes_utf8_lf(tmp_path):
    manifest_path = tmp_path / "manifest.json"
    generator.update_manifest_file(
        str(manifest_path), "Demo", {"Demo": {"release_notes": "café"}}
    )
    raw = manifest_path.read_bytes()
    assert b"\r\n" not in raw
    assert "café" in raw.decode("utf-8")


def test_generator_signs_exact_file_bytes_with_v1_envelope(tmp_path):
    private_key = ec.generate_private_key(ec.SECP256R1())
    private_path = tmp_path / "disposable-test-key.pem"
    private_path.write_bytes(
        private_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    manifest_path = tmp_path / "manifest.json"
    manifest_bytes = b'{"Demo":{"version":"1.2.3.4","checksum":"sha256:abc"}}\n'
    manifest_path.write_bytes(manifest_bytes)

    generator.sign_manifest_file(str(manifest_path), str(private_path))

    envelope = (tmp_path / "manifest.json.sig").read_text("ascii").strip()
    prefix, key_id, signature_text = envelope.split(":", 2)
    assert prefix == "VAU-ECDSA-P256-SHA256-v1"
    public_hex = generator.public_key_xy_hex(private_key)
    assert key_id == generator.signing_key_id(public_hex)
    raw_signature = base64.b64decode(signature_text, validate=True)
    assert len(raw_signature) == 64
    r = int.from_bytes(raw_signature[:32], "big")
    s = int.from_bytes(raw_signature[32:], "big")
    der_signature = encode_dss_signature(r, s)
    private_key.public_key().verify(
        der_signature, manifest_bytes, ec.ECDSA(hashes.SHA256())
    )
    with pytest.raises(Exception):
        private_key.public_key().verify(
            der_signature, manifest_bytes + b" ", ec.ECDSA(hashes.SHA256())
        )


def test_generator_uses_whole_seconds_in_utc(tmp_path):
    payload = tmp_path / "payload.zip"
    payload.write_bytes(b"test payload")
    entry = generator.generate_manifest(
        "Demo", "1.0.0.65535", payload, "https://updates.example.test",
        min_version="0.1.2",
    )["Demo"]
    assert entry["version"] == "1.0.0.65535"
    assert entry["min_version"] == "0.1.2"
    assert entry["issued_at"] == entry["release_date"]
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", entry["issued_at"])


@pytest.mark.parametrize("version", ["1.2.3.65536", "1.$10", "1.+2", "1.2.", "1.2.3.4.5"])
def test_generator_rejects_invalid_version_parts(tmp_path, version):
    payload = tmp_path / "payload.zip"
    payload.write_bytes(b"test payload")
    with pytest.raises(ValueError, match="Version"):
        generator.generate_manifest("Demo", version, payload, "https://updates.example.test")
    with pytest.raises(ValueError, match="Minimum version"):
        generator.generate_manifest(
            "Demo", "1.2.3", payload, "https://updates.example.test", min_version=version
        )
