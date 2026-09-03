# Raze Store

Raze Store is an offline-first barcode price lookup and cart calculator for
Filipino sari-sari stores. It helps a family member or store helper find the
owner's price, calculate a customer's basket, and share a digital receipt
without turning the app into an inventory or sales-tracking system.

## MVP scope

- Browse and search every product carried by the store
- Add, edit, photograph, and delete local products
- Optionally remove a local product photo's background fully on-device
- Complete first-launch store setup and quickly add barcode, name, and price
- Scan EAN/UPC/Code 128 barcodes on-device
- Attach sub-unit prices such as pack/stick, strip/sachet, or tray/piece to one
  main barcode
- Use the separate Quick units page to update piece/pack quantities directly
- Add repeated products to one cart line and adjust quantity
- Calculate line subtotals, cash received, change, and a PHP total
- Preview, save, and share a receipt image
- Keep the unfinished cart locally across accidental restarts
- Create/restore a complete `.razestore` backup, including product photos
- Import a merge-only `.razepack` with ready-made products and offline images
- Export/import a merge-only product CSV for spreadsheet editing

The cart is intentionally temporary. Raze Store does not record sold items,
decrement stock, keep sales history, calculate profit, or track aging.

## Offline-first architecture

```text
Flutter screen
    -> Riverpod provider/controller
    -> repository interface
    -> Drift / SQLite on the device
```

Shared Philippine product data is installed from a versioned `.razepack` file.
The pack carries barcode, name, brand, size, category, an optional reference
price, and an optimized product image. Importing it once makes those products
available without a server or internet connection. Scanning checks the local
Drift database only; an already-saved barcode immediately punches one main
unit into the cart, and scanning it again increases its quantity.

Pack import is merge-only. It adds missing products but does not delete the
store's products or replace owner-edited prices, photos, units, receipt
settings, or the unfinished cart. A future pack can therefore add products,
while owners can continue correcting their own local catalog. Reference prices
are starting values rather than a promise of the price charged by every store.

The earlier `raze_store_api` prototype remains in the repository for possible
future catalog-building tools, but the Flutter app does not require or contact
it during normal use.

Background removal uses a bundled ONNX model and does not upload the chosen
photo. It requires iOS 16 or newer and increases the installed application size.

## Products, units, and categories

The barcode belongs to the main product. Its normal selling unit and price can
be a `Pack`, `Bottle`, or any other label. Optional sub-units store separate
local prices without requiring another barcode—for example, scanning a pack
can offer both `Pack · ₱150.00` and `Stick · ₱8.00`. Each choice becomes its own
cart line and receipt line.

Products with alternate units also appear on the separate **Quick units** page.
Its minus/quantity/plus controls update the unfinished cart immediately, while
the full Products page remains the place to manage product details and prices.

The product form suggests common sari-sari categories while still accepting a
custom category. Imported products can introduce more category names without a
database migration.

## Catalog files

A `.razepack` is a distributable starter/update catalog. It is a validated,
checksummed ZIP containing product records and optional optimized images.
Importing one is non-destructive and does not touch store settings or the cart.

### Import the included starter catalog

The repository includes a ready-to-import catalog containing 20 reviewed
Filipino products and 20 optimized offline images:

**[Download `filipino-sari-sari-starter-v1.razepack`](outputs/filipino-sari-sari-starter-v1.razepack?raw=1)**

- File size: 353,732 bytes (about 0.34 MiB)
- SHA-256: `9becf47835c78c485869bf25edc9ec223b1d4652307e936b29422210d3e75ff8`
- Three products have dated reference SRPs. The other products intentionally
  start at ₱0 until the store owner confirms a selling price.

To import it on a phone:

1. Download the `.razepack` and keep it in **Files** on iOS or **Downloads** on
   Android. AirDrop can also place the file on an iPhone.
2. For a new store, enter the store details, press **Save and continue**, then
   choose **Import offline catalog pack**.
3. For an existing store, open **Settings → Catalog files → Import catalog
   pack**.
4. Confirm the safe merge, choose the downloaded file, and wait for the import
   confirmation.
5. Open **Products** and set the selling price of any ₱0 item before scanning
   it into the cart.

Importing the same pack again does not duplicate its products. It also does
not overwrite locally edited prices, selling units, names, photos, receipt
settings, or the unfinished cart. A `.razepack` is shared starter data; use a
private `.razestore` backup when moving one store's complete data to another
phone.

### Build or update the starter catalog

Edit `catalog_packs/filipino-sari-sari-starter-v1/source.json` and its reviewed
images, increment the pack revision and timestamps, preserve barcode/source
identities, and retain the required attribution. Then rebuild the downloadable
file from the repository root:

```sh
python3 tool/build_catalog_pack.py \
  catalog_packs/filipino-sari-sari-starter-v1/source.json \
  outputs/filipino-sari-sari-starter-v1.razepack \
  --overwrite
```

Before publishing, import the rebuilt pack on a clean test installation and
update the file size and SHA-256 shown above. The complete source schema, image
limits, provenance rules, safety contract, and larger-pack sizing guidance are
documented in [`docs/catalog-pack-format.md`](docs/catalog-pack-format.md).

A `.razestore` file is the private, lossless backup. It contains products, main and
sub-unit prices, managed product photos, receipt/store details, and the saved
theme. Backups are checksummed and validated before restore; restoring replaces
the local catalog and clears the temporary cart. Backup files are not encrypted
and should be stored privately.

CSV is for spreadsheet interchange, not backup. It excludes photos, settings,
and the temporary cart. Import validates the entire file, then merges by product
ID and barcode in one transaction. It never deletes products missing from the
spreadsheet. Export an app-generated CSV first to get the supported columns and
`selling_units_json` format.

## Toolchain

This workspace currently uses Flutter through FVM:

```sh
/Users/rem/fvm/default/bin/flutter pub get
/Users/rem/fvm/default/bin/dart run build_runner build --force-jit --delete-conflicting-outputs
/Users/rem/fvm/default/bin/flutter analyze
/Users/rem/fvm/default/bin/flutter test
```

Run on a connected Android or iOS device with:

```sh
/Users/rem/fvm/default/bin/flutter run
```

Camera scanning and gallery export require a physical-device smoke test even
when the automated test suite passes.
