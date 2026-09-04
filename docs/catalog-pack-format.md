# Raze Store catalog packs

A `.razepack` is a reviewed, versioned starter catalog that the app imports
once and can use fully offline. It is different from a private `.razestore`
backup, which replaces one store's data, and from CSV, which is for
spreadsheet interchange and never carries images.

## Release source

Maintain a UTF-8 JSON source file beside any attribution file and reviewed
images. `imageFile` paths are relative to that source file. A minimal release
source looks like this:

```json
{
  "packId": "filipino-sari-sari-core",
  "revision": 1,
  "createdAt": "2026-09-03T00:00:00Z",
  "sourceSnapshotAt": "2026-09-03T00:00:00Z",
  "title": "Filipino Sari-sari Core Catalog",
  "description": "Reviewed packaged food and drink products.",
  "dataLicense": "Open Food Facts database: ODbL-1.0; contents: DbCL-1.0",
  "imageLicense": "Open Food Facts product images: CC-BY-SA-3.0",
  "attribution": "Product data and images are from Open Food Facts contributors.",
  "attributionFile": "ATTRIBUTION.md",
  "products": [
    {
      "catalogProductId": "off:4807770270055",
      "source": "open_food_facts",
      "sourceProductId": "4807770270055",
      "updatedAt": "2026-09-03T00:00:00Z",
      "barcode": "4807770270055",
      "name": "Instant Pancit Canton Original Flavour",
      "brand": "Lucky Me!",
      "unitLabel": "60 g",
      "category": "Instant noodles",
      "remoteImageUrl": "https://images.openfoodfacts.org/example.400.jpg",
      "imageFile": "images/4807770270055.jpg",
      "sourceUrl": "https://world.openfoodfacts.org/product/4807770270055",
      "imageSourceUrl": "https://images.openfoodfacts.org/example.400.jpg",
      "imageLicense": "CC-BY-SA-3.0"
    }
  ]
}
```

Required product fields are `catalogProductId`, `source`, `sourceProductId`,
`updatedAt`, `name`, and `sourceUrl`. `barcode`, `brand`, `unitLabel`,
`category`, `remoteImageUrl`, `suggestedPriceCentavos`, and image fields are
optional. A 12-digit numeric UPC is canonicalized to its zero-prefixed EAN-13
form, matching the app. Do not change `catalogProductId`, `source`, or
`sourceProductId` between revisions for the same real product.

Use broad shelf categories that stay useful as filters when the catalog grows,
such as `Canned Goods`, `Snacks`, `Biscuits`, `Bread`, `Beverages`, or
`Instant Noodles`. Put the specific kind in the product name instead of making
categories such as `Canned tuna`, `Corned beef`, or `Prawn crackers`.

A suggested price is an integer number of Philippine centavos. Include one
only for an exact product-and-size match from a dated, reviewable source. The
builder then requires an audit record:

```json
"suggestedPriceCentavos": 4075,
"referencePrice": {
  "kind": "srp",
  "source": "DTI BNPC SRP Bulletin",
  "sourceUrl": "https://www.dti.gov.ph/example.pdf",
  "effectiveFrom": "2025-02-01",
  "notes": "Historical reference; not a current store-specific price."
}
```

When no exact reference exists, omit both fields. A new product then imports
with a zero price for the owner to confirm; never estimate, average, or invent
a barcode or selling price. `sourceUrl`, `imageSourceUrl`, `imageLicense`, and
`referencePrice` remain in `catalog.json` for release audits even though the
current app does not use those fields during normal operation.

## Build and inspect

From the repository root:

```sh
python3 tool/build_catalog_pack.py \
  catalog_packs/filipino-sari-sari-core/source.json \
  outputs/filipino-sari-sari-core-r1.razepack
```

Pass `--overwrite` only when intentionally replacing an existing build. Given
identical inputs, the tool writes the same sorted JSON, fixed ZIP timestamps,
and SHA-256 checksums. It validates source paths, HTTPS provenance URLs,
timestamps, duplicate identities/barcodes, image signatures, and the app's
archive limits before publishing the output atomically.

The resulting ZIP contains:

```text
manifest.json
catalog.json
ATTRIBUTION.md          optional, but recommended for every public release
images/<safe-name>.jpg  optional; JPEG, PNG, or WebP
```

`manifest.json` uses `format: "raze-store-catalog-pack"`, `packVersion: 1`, a
positive `revision`, `dataFile: "catalog.json"`, product/image counts, and a
descriptor (`path`, byte `size`, and lowercase SHA-256) for every other file.
Checksums detect damage or tampering; they are not a publisher signature.
Distribute packs through a trusted channel and publish an out-of-band release
checksum when authenticity matters.

App-compatible limits are 512 MiB compressed, 768 MiB expanded, 24 MiB for
`catalog.json`, 1 MiB each for the manifest and attribution, 8 MiB per image,
4,096 pixels on either image side, 12,582,912 total pixels (12 × 1,024 ×
1,024), 10,002 total files, 50,000 products, and 10,000 images. ZIP64, links,
path traversal, duplicate names, unlisted files, unreadable image dimensions,
and mismatched image extensions are rejected.

## Import and revision semantics

The app validates and stages the complete pack before changing local data, then
matches each row by `(source, sourceProductId)` or canonical barcode. It shows
matches under **Existing products** and unmatched rows under **New products**.
Every row begins unchecked. The owner chooses the trusted products and the
fields the pack may contribute: barcode, name, brand, category, main unit,
suggested price, and image. Applying the review is one atomic database change;
an invalid file, stale review, or conflicting local edit changes nothing.

Selected new rows are created with their required product name. Their optional
details are populated only when the corresponding field was allowed. Selected
existing rows keep their local ID, owner photo, selling units, and every
non-zero main price. A selected suggested price may fill a zero main price but
cannot replace a non-zero one. Products absent from the pack, unselected rows,
settings, receipt data, sales, and the unfinished cart are not changed by the
import. Shared source identity is linked for selected rows so future revisions
can match them reliably.

An import that changes at least one product creates a one-level local undo
checkpoint. Undo removes newly imported products and their unfinished-cart
rows, and restores updated products exactly. It refuses to run if an affected
product changed afterward. A later changing import replaces that checkpoint;
a no-change import retains it, and bulk product deletion clears it because
replaying the older checkpoint would be unsafe.

Use one stable `packId` and monotonically increasing revisions for a release
line. The app records the applied revision for undo metadata but does not use it
to block an older pack, so owners should still review every proposed detail and
publishers should distribute releases in order. If a release grows too large,
create stable category packs instead of changing identities or relying on
deletion.

## Provenance and licensing

For Open Food Facts, build hundreds or thousands of rows from its official
[bulk database export](https://openfoodfacts.github.io/openfoodfacts-server/api/)
and
[bulk image dataset](https://openfoodfacts.github.io/openfoodfacts-server/api/how-to-download-images/),
not repeated public API searches. Preserve each exact GTIN and original page
and image URL, deduplicate canonical barcodes, balance sari-sari categories,
and manually review product name, brand, package size, front image, and
Philippine relevance before release.

Open Food Facts database data is offered under ODbL 1.0 and individual
contents under DbCL; its contributed product images are offered under CC
BY-SA 3.0. Follow the current
[Open Food Facts licensing guidance](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/)
and attribution/share-alike requirements. Packaging art and trademarks can
carry additional rights. Cropping, resizing, or removing a background does
not remove those rights, so retain the original image URL and license for every
derived image. Record equivalent provenance and permission for any other data
source.

Prices need separate provenance because Open Food Facts is not a Philippine
price authority. Only publish a value from an exact, dated product-and-size
match such as a DTI bulletin; keep its URL and effective date and treat it as a
starting reference, never a guaranteed current retail price.

## Image and file-size guidance

Bundle one reviewed front image per product, normally 256–400 px on the long
edge. Prefer JPEG or WebP at roughly 20–80 KiB. Use PNG only when transparency
materially helps; mass background removal often makes files larger and creates
derivatives that still require attribution. Keep the original outside the
pack for reproducible releases. The builder reads only format headers to check
dimensions; it does not fully decode or repair an image. Validate the rendered
source image separately during editorial review.

The checked-in revision 3 starter contains 208 products and 20 optimized 256 px
JPEGs. Most DTI-only rows have no image because their source does not publish
one, so the built pack remains well under 1 MiB. Practical planning ranges are:

| Products | Metadata only | With one optimized image each |
| ---: | ---: | ---: |
| 500 | 0.5–3 MiB | 10–40 MiB |
| 1,000 | 1–5 MiB | 20–80 MiB |
| 5,000 | 5–25 MiB | 100–400 MiB |
| 9,000 | 10–45 MiB | 180–500+ MiB; split before the 512 MiB cap |

Full-resolution or background-removed PNGs can reach roughly 0.2–1 GiB per
1,000 products. Start with a reviewed 500–1,000-product core pack, measure the
actual output, and release additional category packs rather than making one
oversized download.
