# Filipino Sari-sari Starter Catalog

This directory is the reviewed source for the app's offline `.razepack`.
Revision 3 contains 208 products across broad shelf categories. Every product
has a positive suggested starting price:

- 191 exact product/unit prices from the Philippine Department of Trade and
  Industry BNPC SRP Bulletin dated 1 February 2025
- 17 exact-product Philippine retailer observations for image-backed starter
  products not listed in that bulletin

The original 20 starter rows retain their stable catalog/source identities so
installing this revision updates an earlier installation instead of creating
duplicates. Those rows retain reviewed barcodes and optimized offline images.
DTI-only rows intentionally omit barcodes and images because the bulletin does
not publish them; do not invent either value.

Build the importable file from the repository root:

```sh
python3 tool/build_catalog_pack.py \
  catalog_packs/filipino-sari-sari-starter-v1/source.json \
  outputs/filipino-sari-sari-starter-v1.razepack \
  --overwrite
```

Prices in this shared catalog are editable starting values, not a promise of a
current price in every barangay or store. DTI prices are clearly marked as
historical SRPs. Retailer observations are clearly marked `retailer_price` and
must not be presented as official SRPs. Each priced row keeps its source URL,
effective/observation date, and explanatory note in `referencePrice`.

The app imports the pack without deleting local products. An existing non-zero
store price always wins; the pack suggestion is applied only to a new product
or a matching product whose saved main price is zero. Owners can edit prices,
names, categories, and units after import.

Product metadata and images for the original 20 records come from Open Food
Facts contributors under ODbL 1.0 / DbCL 1.0 and CC BY-SA 3.0 respectively.
See `ATTRIBUTION.md` and the per-product URLs in `source.json` for full
provenance.
