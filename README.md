# Raze Store

Raze Store is an offline-first barcode price lookup and cart calculator for
Filipino sari-sari stores. It helps a family member or store helper find the
owner's price, calculate a customer's basket, and share a digital receipt
without turning the app into an inventory or sales-tracking system.

## MVP scope

- Browse and search every product carried by the store
- Add, edit, photograph, and delete local products
- Complete first-launch store setup and quickly add barcode, name, and price
- Scan EAN/UPC/Code 128 barcodes on-device
- Attach sub-unit prices such as pack/stick, strip/sachet, or tray/piece to one
  main barcode
- Add repeated products to one cart line and adjust quantity
- Calculate line subtotals, cash received, change, and a PHP total
- Preview, save, and share a receipt image
- Keep the unfinished cart locally across accidental restarts
- Create/restore a complete `.razestore` backup, including product photos
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

The separate `raze_store_api` service supplies shared Philippine product
metadata such as barcode, name, brand, size, category, and image. Each store's
selling price remains local and authoritative because prices differ by store.
Scanning checks Drift first and calls the API only after a local miss. A shared
catalog result must be given a local selling price before it can enter the cart.
If the API resolves an alternate barcode, the app saves the code that was
actually scanned so that package works offline on the next scan. Storing every
alternate barcode for one product is a later local-schema enhancement; another
alias still needs the API connection.

## Shared catalog API

Debug builds connect to a local API automatically:

- Android emulator: `http://10.0.2.2:8000/api/v1/`
- iOS simulator: `http://127.0.0.1:8000/api/v1/`

For a physical phone, bind Django to `0.0.0.0:8000`, add the Mac's LAN address
to `DJANGO_ALLOWED_HOSTS`, and provide that address when running Flutter:

```sh
/Users/rem/fvm/default/bin/flutter run \
  --dart-define=RAZE_STORE_API_BASE_URL=http://192.168.x.x:8000/api/v1/
```

Release builds intentionally have no default endpoint and require HTTPS:

```sh
/Users/rem/fvm/default/bin/flutter build ipa --release \
  --dart-define=RAZE_STORE_API_BASE_URL=https://api.example.com/api/v1/
```

The app calls only public read endpoints: health, category suggestions,
paginated product search, and barcode lookup. Never put Django staff
credentials in the Flutter build.

## Products, units, and categories

The barcode belongs to the main product. Its normal selling unit and price can
be a `Pack`, `Bottle`, or any other label. Optional sub-units store separate
local prices without requiring another barcode—for example, scanning a pack
can offer both `Pack · ₱150.00` and `Stick · ₱8.00`. Each choice becomes its own
cart line and receipt line.

The product form suggests common sari-sari categories while still accepting a
custom category. This keeps the app usable offline and allows a future API to
add more category names without a database migration.

## Catalog files

A `.razestore` file is the lossless backup. It contains products, main and
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
