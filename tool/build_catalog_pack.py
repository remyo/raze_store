#!/usr/bin/env python3
"""Build a deterministic, checksummed Raze Store offline catalog pack.

The source JSON uses the same product fields as ``catalog.json`` plus an
``imageFile`` path relative to the source document. Network downloads and image
editing are intentionally outside this tool so pack inputs can be reviewed and
reproduced before release.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import zipfile
from datetime import date, datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import urlsplit


PACK_FORMAT = "raze-store-catalog-pack"
PACK_VERSION = 1
MAX_SOURCE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 768 * 1024 * 1024
MAX_CATALOG_BYTES = 24 * 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_CENTRAL_DIRECTORY_BYTES = 2 * 1024 * 1024
MAX_FILES = 10_002
MAX_PRODUCTS = 50_000
MAX_IMAGES = 10_000
MAX_IMAGE_BYTES = 8 * 1024 * 1024
MAX_IMAGE_DIMENSION = 4096
MAX_IMAGE_PIXELS = 12 * 1024 * 1024
MAX_SQLITE_INTEGER = (1 << 63) - 1
ALLOWED_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID_PATTERN = re.compile(r"[^a-zA-Z0-9_-]+")
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)

SOURCE_FIELDS = {
    "packId",
    "revision",
    "createdAt",
    "title",
    "description",
    "sourceSnapshotAt",
    "dataLicense",
    "imageLicense",
    "attribution",
    "attributionFile",
    "products",
}
PRODUCT_FIELDS = {
    "catalogProductId",
    "source",
    "sourceProductId",
    "updatedAt",
    "barcode",
    "name",
    "brand",
    "unitLabel",
    "category",
    "remoteImageUrl",
    "suggestedPriceCentavos",
    "imageFile",
    "sourceUrl",
    "imageSourceUrl",
    "imageLicense",
    "referencePrice",
}
REFERENCE_PRICE_FIELDS = {"kind", "source", "sourceUrl", "effectiveFrom", "notes"}


class PackBuildError(ValueError):
    """A source document cannot safely be turned into a catalog pack."""


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a validated .razepack from reviewed JSON and images."
    )
    parser.add_argument("source", type=Path, help="Catalog source JSON")
    parser.add_argument("output", type=Path, help="Destination .razepack")
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace the destination if it already exists",
    )
    return parser.parse_args()


def _required_string(value: Any, field: str, maximum: int) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PackBuildError(f"{field} must be a non-empty string")
    clean = value.strip()
    if len(clean) > maximum:
        raise PackBuildError(f"{field} is longer than {maximum} characters")
    return clean


def _optional_string(value: Any, field: str, maximum: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise PackBuildError(f"{field} must be a string or null")
    clean = value.strip()
    if not clean:
        return None
    if len(clean) > maximum:
        raise PackBuildError(f"{field} is longer than {maximum} characters")
    return clean


def _utc_timestamp(value: Any, field: str) -> str:
    text = _required_string(value, field, 64)
    candidate = text[:-1] + "+00:00" if text.endswith("Z") else text
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError as error:
        raise PackBuildError(f"{field} must be an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        raise PackBuildError(f"{field} must include a UTC offset")
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _https_url(value: Any, field: str, *, required: bool = False) -> str | None:
    clean = (
        _required_string(value, field, 2048)
        if required
        else _optional_string(value, field, 2048)
    )
    if clean is None:
        return None
    if any(ord(character) <= 0x20 or ord(character) == 0x7F for character in clean):
        raise PackBuildError(f"{field} must not contain control characters")
    try:
        parsed = urlsplit(clean)
        port = parsed.port
    except ValueError as error:
        raise PackBuildError(f"{field} must be a valid HTTPS URL") from error
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or port is not None and not 1 <= port <= 65_535
    ):
        raise PackBuildError(f"{field} must be an HTTPS URL without credentials")
    return clean


def _canonical_barcode(value: Any, field: str) -> str | None:
    clean = _optional_string(value, field, 160)
    if clean is not None and len(clean) == 12 and clean.isascii() and clean.isdigit():
        return f"0{clean}"
    return clean


def _reject_unknown_fields(raw: dict[str, Any], allowed: set[str], field: str) -> None:
    unknown = sorted(set(raw).difference(allowed))
    if unknown:
        raise PackBuildError(f"{field} contains unsupported field(s): {', '.join(unknown)}")


def _png_dimensions(payload: bytes) -> tuple[int, int] | None:
    if (
        len(payload) < 24
        or payload[:8] != b"\x89PNG\r\n\x1a\n"
        or payload[12:16] != b"IHDR"
        or int.from_bytes(payload[8:12], "big") != 13
    ):
        return None
    width = int.from_bytes(payload[16:20], "big")
    height = int.from_bytes(payload[20:24], "big")
    return (width, height) if width > 0 and height > 0 else None


def _is_jpeg_start_of_frame(marker: int) -> bool:
    return (
        0xC0 <= marker <= 0xC3
        or 0xC5 <= marker <= 0xC7
        or 0xC9 <= marker <= 0xCB
        or 0xCD <= marker <= 0xCF
    )


def _jpeg_dimensions(payload: bytes) -> tuple[int, int] | None:
    if len(payload) < 4 or payload[:2] != b"\xff\xd8":
        return None

    position = 2
    while position < len(payload):
        if payload[position] != 0xFF:
            return None
        position += 1
        while position < len(payload) and payload[position] == 0xFF:
            position += 1
        if position >= len(payload):
            return None
        marker = payload[position]
        position += 1
        if marker == 0x00 or marker in {0xD9, 0xDA}:
            return None
        if marker == 0xD8 or marker == 0x01 or 0xD0 <= marker <= 0xD7:
            continue
        if position + 2 > len(payload):
            return None
        segment_length = int.from_bytes(payload[position : position + 2], "big")
        position += 2
        if segment_length < 2 or position + segment_length - 2 > len(payload):
            return None
        if _is_jpeg_start_of_frame(marker):
            if segment_length < 7 or position + 5 > len(payload):
                return None
            height = int.from_bytes(payload[position + 1 : position + 3], "big")
            width = int.from_bytes(payload[position + 3 : position + 5], "big")
            return (width, height) if width > 0 and height > 0 else None
        position += segment_length - 2
    return None


def _uint24_little_endian(payload: bytes, offset: int) -> int:
    return (
        payload[offset]
        | payload[offset + 1] << 8
        | payload[offset + 2] << 16
    )


def _webp_dimensions(payload: bytes) -> tuple[int, int] | None:
    if (
        len(payload) < 21
        or payload[:4] != b"RIFF"
        or payload[8:12] != b"WEBP"
    ):
        return None
    riff_size = int.from_bytes(payload[4:8], "little")
    if riff_size + 8 != len(payload):
        return None
    chunk_size = int.from_bytes(payload[16:20], "little")
    if chunk_size + 20 > len(payload):
        return None

    chunk_type = payload[12:16]
    if chunk_type == b"VP8X":
        if chunk_size < 10 or len(payload) < 30:
            return None
        return (
            1 + _uint24_little_endian(payload, 24),
            1 + _uint24_little_endian(payload, 27),
        )
    if chunk_type == b"VP8L":
        if chunk_size < 5 or len(payload) < 25 or payload[20] != 0x2F:
            return None
        packed = int.from_bytes(payload[21:25], "little")
        return (1 + (packed & 0x3FFF), 1 + ((packed >> 14) & 0x3FFF))
    if chunk_type == b"VP8 ":
        if chunk_size < 10 or len(payload) < 30 or payload[23:26] != b"\x9d\x01\x2a":
            return None
        width = int.from_bytes(payload[26:28], "little") & 0x3FFF
        height = int.from_bytes(payload[28:30], "little") & 0x3FFF
        return (width, height) if width > 0 and height > 0 else None
    return None


def _image_dimensions(payload: bytes, suffix: str) -> tuple[int, int] | None:
    if suffix in {".jpg", ".jpeg"}:
        return _jpeg_dimensions(payload)
    if suffix == ".png":
        return _png_dimensions(payload)
    if suffix == ".webp":
        return _webp_dimensions(payload)
    return None


def _safe_image_name(stable_id: str, suffix: str, used: set[str]) -> str:
    stem = SAFE_ID_PATTERN.sub("-", stable_id).strip("-_") or "product"
    stem = stem[:100]
    candidate = f"images/{stem}{suffix.lower()}"
    counter = 2
    while candidate.casefold() in used:
        candidate = f"images/{stem}-{counter}{suffix.lower()}"
        counter += 1
    used.add(candidate.casefold())
    return candidate


def _image_bytes(source_root: Path, value: Any, field: str) -> tuple[bytes, str]:
    relative = _required_string(value, field, 1024)
    relative_path = PurePosixPath(relative.replace("\\", "/"))
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise PackBuildError(f"{field} must stay inside the source directory")
    source_path = (source_root / Path(*relative_path.parts)).resolve()
    try:
        source_path.relative_to(source_root.resolve())
    except ValueError as error:
        raise PackBuildError(f"{field} must stay inside the source directory") from error
    suffix = source_path.suffix.lower()
    if suffix not in ALLOWED_IMAGE_SUFFIXES:
        raise PackBuildError(f"{field} must be JPEG, PNG, or WebP")
    try:
        payload = source_path.read_bytes()
    except OSError as error:
        raise PackBuildError(f"Could not read {field}: {source_path}") from error
    if not payload or len(payload) > MAX_IMAGE_BYTES:
        raise PackBuildError(
            f"{field} must contain between 1 byte and {MAX_IMAGE_BYTES} bytes"
        )
    dimensions = _image_dimensions(payload, suffix)
    if dimensions is None:
        raise PackBuildError(
            f"{field} does not contain readable dimensions for its image type"
        )
    width, height = dimensions
    if (
        width > MAX_IMAGE_DIMENSION
        or height > MAX_IMAGE_DIMENSION
        or width * height > MAX_IMAGE_PIXELS
    ):
        raise PackBuildError(
            f"{field} must be no larger than {MAX_IMAGE_DIMENSION} pixels per "
            f"side or {MAX_IMAGE_PIXELS} total pixels"
        )
    return payload, suffix


def _attribution_bytes(source_root: Path, value: Any) -> bytes:
    relative = _required_string(value, "attributionFile", 1024)
    relative_path = PurePosixPath(relative.replace("\\", "/"))
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise PackBuildError("attributionFile must stay inside the source directory")
    source_path = (source_root / Path(*relative_path.parts)).resolve()
    try:
        source_path.relative_to(source_root.resolve())
        payload = source_path.read_bytes()
        payload.decode("utf-8")
    except (ValueError, OSError, UnicodeError) as error:
        raise PackBuildError(
            "attributionFile must be a readable UTF-8 file inside the source directory"
        ) from error
    if not payload or len(payload) > MAX_MANIFEST_BYTES:
        raise PackBuildError(
            f"attributionFile must be between 1 byte and {MAX_MANIFEST_BYTES} bytes"
        )
    return payload


def _json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _descriptor(path: str, payload: bytes) -> dict[str, Any]:
    digest = hashlib.sha256(payload).hexdigest()
    assert SHA256_PATTERN.fullmatch(digest)
    return {"path": path, "size": len(payload), "sha256": digest}


def _normalize_reference_price(value: Any, field: str) -> dict[str, str]:
    if not isinstance(value, dict):
        raise PackBuildError(f"{field} must be an object")
    _reject_unknown_fields(value, REFERENCE_PRICE_FIELDS, field)
    kind = _required_string(value.get("kind"), f"{field}.kind", 40)
    source = _required_string(value.get("source"), f"{field}.source", 240)
    source_url = _https_url(value.get("sourceUrl"), f"{field}.sourceUrl", required=True)
    effective_from = _required_string(
        value.get("effectiveFrom"), f"{field}.effectiveFrom", 10
    )
    try:
        date.fromisoformat(effective_from)
    except ValueError as error:
        raise PackBuildError(
            f"{field}.effectiveFrom must be an ISO-8601 calendar date"
        ) from error
    normalized = {
        "kind": kind,
        "source": source,
        "sourceUrl": source_url,
        "effectiveFrom": effective_from,
    }
    notes = _optional_string(value.get("notes"), f"{field}.notes", 1000)
    if notes is not None:
        normalized["notes"] = notes
    return normalized


def _normalize_product(
    raw: Any,
    *,
    index: int,
    source_root: Path,
    default_image_license: str | None,
    used_image_paths: set[str],
) -> tuple[dict[str, Any], tuple[str, bytes] | None]:
    label = f"products[{index}]"
    if not isinstance(raw, dict):
        raise PackBuildError(f"{label} must be an object")
    _reject_unknown_fields(raw, PRODUCT_FIELDS, label)

    product = dict(raw)
    catalog_id = _required_string(
        product.get("catalogProductId"), f"{label}.catalogProductId", 160
    )
    product["catalogProductId"] = catalog_id
    product["source"] = _required_string(product.get("source"), f"{label}.source", 64)
    product["sourceProductId"] = _required_string(
        product.get("sourceProductId"), f"{label}.sourceProductId", 160
    )
    product["updatedAt"] = _utc_timestamp(
        product.get("updatedAt"), f"{label}.updatedAt"
    )
    product["name"] = _required_string(product.get("name"), f"{label}.name", 240)
    product["sourceUrl"] = _https_url(
        product.get("sourceUrl"), f"{label}.sourceUrl", required=True
    )

    for field, maximum in (
        ("brand", 240),
        ("unitLabel", 120),
        ("category", 240),
        ("imageLicense", 160),
    ):
        clean = _optional_string(product.get(field), f"{label}.{field}", maximum)
        if clean is None:
            product.pop(field, None)
        else:
            product[field] = clean

    barcode = _canonical_barcode(product.get("barcode"), f"{label}.barcode")
    if barcode is None:
        product.pop("barcode", None)
    else:
        product["barcode"] = barcode
    for field in ("remoteImageUrl", "imageSourceUrl"):
        clean_url = _https_url(product.get(field), f"{label}.{field}")
        if clean_url is None:
            product.pop(field, None)
        else:
            product[field] = clean_url

    price = product.get("suggestedPriceCentavos")
    if price is not None and (
        not isinstance(price, int)
        or isinstance(price, bool)
        or price <= 0
        or price > MAX_SQLITE_INTEGER
    ):
        raise PackBuildError(
            f"{label}.suggestedPriceCentavos must be a positive integer or null"
        )
    reference_price = product.get("referencePrice")
    if price is None and reference_price is not None:
        raise PackBuildError(
            f"{label}.referencePrice requires suggestedPriceCentavos"
        )
    if price is not None:
        product["referencePrice"] = _normalize_reference_price(
            reference_price, f"{label}.referencePrice"
        )

    image_entry: tuple[str, bytes] | None = None
    image_file = product.pop("imageFile", None)
    product.pop("image", None)
    has_image_reference = image_file is not None or product.get("remoteImageUrl") is not None
    if has_image_reference and product.get("imageSourceUrl") is None:
        raise PackBuildError(
            f"{label}.imageSourceUrl is required when an image is referenced"
        )
    if has_image_reference and product.get("imageLicense") is None:
        if default_image_license is None:
            raise PackBuildError(
                f"{label}.imageLicense or top-level imageLicense is required "
                "when an image is referenced"
            )
        product["imageLicense"] = default_image_license
    if image_file is not None:
        payload, suffix = _image_bytes(source_root, image_file, f"{label}.imageFile")
        image_path = _safe_image_name(catalog_id, suffix, used_image_paths)
        product["image"] = image_path
        image_entry = (image_path, payload)
    return product, image_entry


def build_pack(source_path: Path, output_path: Path, *, overwrite: bool) -> dict[str, int]:
    if output_path.suffix.lower() != ".razepack":
        raise PackBuildError("The output file must end in .razepack")
    if output_path.exists() and not overwrite:
        raise PackBuildError("The output already exists; pass --overwrite to replace it")
    try:
        if source_path.stat().st_size > MAX_SOURCE_BYTES:
            raise PackBuildError(
                f"Source JSON cannot exceed {MAX_SOURCE_BYTES} bytes"
            )
        source = json.loads(source_path.read_text(encoding="utf-8"))
    except PackBuildError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise PackBuildError(f"Could not read source JSON: {source_path}") from error
    if not isinstance(source, dict):
        raise PackBuildError("The source document must be an object")
    _reject_unknown_fields(source, SOURCE_FIELDS, "source document")

    pack_id = _required_string(source.get("packId"), "packId", 160)
    revision = source.get("revision")
    if not isinstance(revision, int) or isinstance(revision, bool) or revision <= 0:
        raise PackBuildError("revision must be a positive integer")
    created_at = _utc_timestamp(source.get("createdAt"), "createdAt")
    source_snapshot_at = _utc_timestamp(
        source.get("sourceSnapshotAt"), "sourceSnapshotAt"
    )
    title = _required_string(source.get("title"), "title", 240)
    data_license = _required_string(source.get("dataLicense"), "dataLicense", 240)
    attribution = _required_string(source.get("attribution"), "attribution", 2000)
    image_license = _optional_string(source.get("imageLicense"), "imageLicense", 240)
    raw_products = source.get("products")
    if not isinstance(raw_products, list) or not raw_products:
        raise PackBuildError("products must be a non-empty list")
    if len(raw_products) > MAX_PRODUCTS:
        raise PackBuildError(f"products cannot contain more than {MAX_PRODUCTS} rows")

    products: list[dict[str, Any]] = []
    archive_entries: dict[str, bytes] = {}
    catalog_ids: set[str] = set()
    source_keys: set[tuple[str, str]] = set()
    barcodes: set[str] = set()
    used_image_paths: set[str] = set()
    for index, raw in enumerate(raw_products):
        product, image_entry = _normalize_product(
            raw,
            index=index,
            source_root=source_path.resolve().parent,
            default_image_license=image_license,
            used_image_paths=used_image_paths,
        )
        catalog_id = product["catalogProductId"]
        source_key = (product["source"].casefold(), product["sourceProductId"])
        barcode = product.get("barcode")
        if catalog_id in catalog_ids:
            raise PackBuildError(f"products[{index}] repeats catalogProductId {catalog_id}")
        if source_key in source_keys:
            raise PackBuildError(f"products[{index}] repeats a source product identity")
        if barcode is not None and barcode in barcodes:
            raise PackBuildError(f"products[{index}] repeats barcode {barcode}")
        catalog_ids.add(catalog_id)
        source_keys.add(source_key)
        if barcode is not None:
            barcodes.add(barcode)
        products.append(product)
        if image_entry is not None:
            archive_entries[image_entry[0]] = image_entry[1]

    image_count = len(archive_entries)
    if image_count > MAX_IMAGES:
        raise PackBuildError(f"A pack cannot contain more than {MAX_IMAGES} images")
    catalog_bytes = _json_bytes({"products": products})
    if len(catalog_bytes) > MAX_CATALOG_BYTES:
        raise PackBuildError(
            f"catalog.json cannot exceed {MAX_CATALOG_BYTES} bytes"
        )
    archive_entries = {"catalog.json": catalog_bytes, **archive_entries}
    attribution_file = source.get("attributionFile")
    if attribution_file is not None:
        archive_entries["ATTRIBUTION.md"] = _attribution_bytes(
            source_path.resolve().parent, attribution_file
        )
    manifest: dict[str, Any] = {
        "format": PACK_FORMAT,
        "packVersion": PACK_VERSION,
        "packId": pack_id,
        "revision": revision,
        "createdAt": created_at,
        "dataFile": "catalog.json",
        "files": [
            _descriptor(path, payload)
            for path, payload in sorted(archive_entries.items())
        ],
        "counts": {
            "products": len(products),
            "images": image_count,
        },
        "title": title,
        "dataLicense": data_license,
        "attribution": attribution,
        "sourceSnapshotAt": source_snapshot_at,
    }
    for field, maximum in (
        ("description", 2000),
        ("imageLicense", 240),
    ):
        clean = _optional_string(source.get(field), field, maximum)
        if clean is not None:
            manifest[field] = clean
    manifest_bytes = _json_bytes(manifest)
    if len(manifest_bytes) > MAX_MANIFEST_BYTES:
        raise PackBuildError(
            f"manifest.json cannot exceed {MAX_MANIFEST_BYTES} bytes"
        )

    all_entries = {"manifest.json": manifest_bytes, **archive_entries}
    if len(all_entries) > MAX_FILES:
        raise PackBuildError(f"A pack cannot contain more than {MAX_FILES} files")
    expanded_bytes = sum(len(payload) for payload in all_entries.values())
    if expanded_bytes > MAX_EXPANDED_BYTES:
        raise PackBuildError(
            f"Pack contents cannot exceed {MAX_EXPANDED_BYTES} expanded bytes"
        )
    central_directory_bytes = sum(
        46 + len(path.encode("utf-8")) for path in all_entries
    )
    if central_directory_bytes > MAX_CENTRAL_DIRECTORY_BYTES:
        raise PackBuildError(
            "The ZIP central directory would exceed the app's import limit"
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_fd, temp_name = tempfile.mkstemp(
        prefix=f".{output_path.name}.", suffix=".tmp", dir=output_path.parent
    )
    os.close(temp_fd)
    temp_path = Path(temp_name)
    try:
        with zipfile.ZipFile(
            temp_path,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
            allowZip64=False,
        ) as archive:
            for path, payload in sorted(all_entries.items()):
                info = zipfile.ZipInfo(path, date_time=ZIP_TIMESTAMP)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                archive.writestr(info, payload)
        if temp_path.stat().st_size > MAX_ARCHIVE_BYTES:
            raise PackBuildError(
                f"The compressed pack cannot exceed {MAX_ARCHIVE_BYTES} bytes"
            )
        if output_path.exists() and not overwrite:
            raise PackBuildError("The output appeared while the pack was being built")
        os.replace(temp_path, output_path)
    finally:
        temp_path.unlink(missing_ok=True)

    return {
        "products": len(products),
        "images": image_count,
        "bytes": output_path.stat().st_size,
    }


def main() -> int:
    args = _arguments()
    try:
        result = build_pack(args.source, args.output, overwrite=args.overwrite)
    except PackBuildError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    print(
        f"Built {args.output} with {result['products']} products, "
        f"{result['images']} images, and {result['bytes']} bytes."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
