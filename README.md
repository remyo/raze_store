# Raze Store

Raze Store is an offline-first barcode price lookup and cart calculator for
Filipino sari-sari stores. It helps a family member or store helper find the
owner's price, calculate a customer's basket, share a digital receipt, and
review simple sales history without turning the app into an inventory system.

## MVP scope

- Browse and search every product carried by the store
- Navigate with three focused tabs: Home, Scan, and Profile
- Add, edit, photograph, and delete local products with a guided camera frame
- Warn when a product photo is too dark and offer the camera flashlight
- Optionally remove a local product photo's background fully on-device
- Read a photographed product label on-device and review suggested form details
- Complete first-launch store setup and quickly add barcode, name, and price
- Scan EAN/UPC/Code 128 barcodes on-device
- Show an immediate confirmation when a scanned product is punched into cart
- Configure scan sound, vibration, and a 500–2000 ms repeat-scan cooldown
- Automatically add the main selling unit or ask which unit to sell
- Jump directly to the badge-aware cart from Home or the barcode scanner
- Attach sub-unit prices such as pack/stick, strip/sachet, or tray/piece to one
  main barcode
- Choose broad built-in categories and manage reusable custom categories
- Use the separate Quick units page to update piece/pack quantities directly
- Add repeated products to one cart line and adjust quantity
- Calculate line subtotals, cash received, change, and a PHP total
- Complete a cart into a saved local sale, then save or share its receipt image
- Filter sales by Today, 7 days, this month, or a custom inclusive date range
- Reopen a historical receipt or permanently delete an individual sale
- Keep the unfinished cart locally across accidental restarts
- Review database, product-image, and temporary-file sizes in Storage Manager
- Create/restore a complete `.razestore` backup, including sales and photos
- Receive weekly or monthly in-app backup reminders, or turn them off
- Review `.razepack` files in separate New and Existing lists, then import
  only checked products and details
- Undo the most recently reviewed catalog-pack import without rolling back
  later sales or settings
- Export/import a merge-only product CSV for spreadsheet editing

Sales history is intentionally lightweight. Completing a sale stores an
immutable snapshot of its cart lines, prices, cash received, and receipt/store
details, then clears the unfinished cart. Previewing a receipt does not create
a sale. Raze Store still does not decrement stock, calculate profit, or track
inventory aging. Deleting a sale removes only that history record, not its
products.

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
Drift database only. A priced product is punched into the cart using its main
selling unit by default. Turn off **Add main unit automatically** in **Profile →
Settings → Barcode scanner** when the seller should choose pack, piece,
stick, or another configured unit after each scan.

Pack import is always non-deleting and uses a review-before-apply flow. The app
fully validates and stages the file first without changing the catalog, then
separates **New products** from **Existing products**. Product rows begin
unchecked. The owner can search, select only trusted rows, and independently
allow barcode, product name, brand, category, size/unit, suggested price, and
catalog image details. An existing non-zero main price always wins; a pack
suggestion is used only for a new product or to fill an existing ₱0 price. The
owner's selected photo, sub-unit prices, products missing from the pack,
receipt settings, and sales remain protected. Reference prices are starting
values rather than a promise of the price charged by every store.

A reviewed import that changes at least one product creates one device-local
**Undo last import** checkpoint. Undo removes products created by that import,
removes their unfinished-cart rows, and restores updated products without
replacing later sales, settings, or the rest of the catalog. If an affected
product was edited after import, undo stops without changing anything so the
newer owner edit cannot be lost. A later import that changes products replaces
the checkpoint; a no-change import keeps it. Bulk product deletion clears it.

The earlier `raze_store_api` prototype remains in the repository for possible
future catalog-building tools, but the Flutter app does not require or contact
it during normal use.

Background removal uses a bundled ONNX model and does not upload the chosen
photo. Product-label text recognition also runs on-device using the bundled
Latin ML Kit model; detected values are suggestions and are never saved without
review. The form does not infer a barcode from photographed digits, and it only
suggests a price when the label explicitly contains a ₱, PHP, or standalone P
currency marker. These
models require iOS 16 or newer and increase the installed application size.

## Products, units, and categories

The barcode belongs to the main product. Its normal selling unit and price can
be a `Pack`, `Bottle`, or any other label. Optional sub-units store separate
local prices without requiring another barcode—for example, scanning a pack
can offer both `Pack · ₱150.00` and `Stick · ₱8.00`. Each choice becomes its own
cart line and receipt line. If the main unit has no price but a priced sub-unit
exists, scanning opens the unit chooser instead of adding a free cart item.

One canonical barcode can belong to only one saved product. The database and
catalog importer both enforce this rule, including equivalent UPC-A/EAN-13
representations. If a barcode is entered on another product, the app keeps the
original, creates no duplicate, and offers to open the existing product.

Products with alternate units also appear on the separate **Quick units** page.
Its minus/quantity/plus controls update the unfinished cart immediately, while
the full Products page remains the place to manage product details and prices.

The product form suggests broad sari-sari shelf categories such as **Canned
Goods**, **Snacks**, **Biscuits**, and **Bread**, while still accepting a custom
category. Keep the product subtype in its name instead of creating narrow
filters such as “Tuna Can.” Imported products can introduce more category names
without a database migration. Open **Profile → Settings → Product
categories** to add or remove reusable custom choices. A custom category in use
by a saved product cannot be deleted until those products are moved to another
category.

Open **Profile → Settings → Delete multiple products** to search the full
catalog, select individual rows, or select every product matching the current
filter. The app shows the exact count before deletion, clears only affected
unfinished-cart rows, and never changes completed sales or their receipt
snapshots. Managed images are removed only when no remaining product, cart row,
or historical sale still references them. A successful bulk deletion also
clears **Undo last import**, because its older checkpoint is no longer safe to
apply. Restore a `.razestore` backup if products were deleted accidentally.

## Scanner and backup settings

Open **Profile → Settings → Barcode scanner** to control the confirmation
sound, vibration, automatic main-unit behavior, and repeat-scan cooldown. The
default cooldown is 500 ms. Repeated camera frames do not add duplicates: the
same barcode must leave the frame for the selected cooldown before it can be
punched again. A different barcode can be scanned immediately. Sound and
vibration happen only after a camera scan is successfully written to the cart.

Backup reminders are device-local and require no notification permission. They
start weekly by default and can be changed to monthly or Off. The first reminder
waits for a complete interval; **Later** postpones it for one day, while a
successfully saved `.razestore` file resets the interval. A due backup is marked
on the Profile tab and can be created directly from Profile.

## Catalog files

A `.razepack` is a distributable starter/update catalog. It is a validated,
checksummed ZIP containing product records and optional optimized images.
Importing one is non-destructive and does not touch store settings or the cart.

### Import the included starter catalog

The repository includes a ready-to-import revision 3 catalog containing 208
common Philippine products. All 208 rows have a positive suggested starting
price; the original 20 barcode products also include optimized offline images:

**[Download `filipino-sari-sari-starter-v1.razepack`](outputs/filipino-sari-sari-starter-v1.razepack?raw=1)**

- File size: 364,731 bytes (about 0.35 MiB)
- SHA-256: `1b7e801280937461ad592307ae6056ace2a73e6b8b4653aba9e95a2fd302fe1d`
- 191 prices are exact product/unit matches from the dated DTI BNPC SRP
  bulletin; 17 are exact-product Philippine retailer observations
- No catalog row starts at ₱0.00
- DTI-only rows omit barcodes and images because the bulletin does not publish
  them; they remain searchable and editable in the app

To import it on a phone:

1. Download the `.razepack` and keep it in **Files** on iOS or **Downloads** on
   Android. AirDrop can also place the file on an iPhone.
2. For a new store, enter the store details, press **Save and continue**, then
   choose **Import offline catalog pack**.
3. For an existing store, open **Profile → Settings → Catalog files → Choose
   and review catalog pack**.
4. Choose the downloaded file. No products are added yet: review the **New
   products** and **Existing products** tabs, search the list, and check only
   the rows you want. **Select shown** selects only the currently visible
   filtered page, never hidden search results. Each compact row shows an
   available preview image, product name, barcode, and price with the selection
   checkbox on the right. Existing rows use the current phone identity so an
   incoming rename cannot disguise the product being updated; tap a row to
   compare everything.
5. Open the collapsed **Choose details to import** section only when you want
   to change which fields are allowed. Then press **Apply** and verify the exact
   new/existing counts in the confirmation. A pack suggestion can fill a ₱0
   price but never replaces a non-zero store price.
6. Open **Home** to check the imported starting prices. If the wrong rows
   were applied, use **Profile → Settings → Catalog files → Undo last import**
   before editing those products.

Importing the same pack again does not duplicate its products; matching rows
appear under **Existing products** for an explicit decision. Checked fields can
replace catalog name, barcode, brand, category, main unit, and image details,
while the owner's photo, sub-unit prices, and non-zero main price stay. File
checks prove that the archive is structurally safe and internally consistent,
not that its author wrote trustworthy product details, so all rows start
unchecked. A `.razepack` is shared starter data; use a private `.razestore`
backup when moving one store's complete data to another phone.

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

Before publishing, import the rebuilt pack on a clean test installation. The
complete source schema, image limits, provenance rules, safety contract, and
larger-pack sizing guidance are documented in
[`docs/catalog-pack-format.md`](docs/catalog-pack-format.md). Source-specific
provenance is recorded in
[`catalog_packs/filipino-sari-sari-starter-v1/ATTRIBUTION.md`](catalog_packs/filipino-sari-sari-starter-v1/ATTRIBUTION.md).

A `.razestore` file is the private, lossless backup. It contains products, main
and sub-unit prices, managed product photos, completed sales, receipt/store
details, custom categories, and the saved theme.
It also keeps scanner sound, vibration, cooldown, automatic-unit behavior, and
the selected backup-reminder frequency. Reminder timing itself—the last backup,
first-reminder anchor, and one-day snooze—stays local to each phone.
Backups are checksummed and validated before restore; restoring replaces the
local catalog and sales history and clears the temporary cart. Backup files are
not encrypted and should be stored privately.

CSV is for spreadsheet interchange, not backup. It excludes photos, settings,
and the temporary cart. Import validates the entire file, then merges by product
ID and barcode in one transaction. It never deletes products missing from the
spreadsheet. Export an app-generated CSV first to get the supported columns and
`selling_units_json` format.

## Sales and storage

Open **Profile → Sales** to review completed checkouts newest first. **Today** is
the default; **7D**, **This month**, **3 months**, **This year**, and **Custom**
recalculate the revenue, transaction, and item totals for the same date range.
Open a transaction to see its saved lines and payment, recreate its receipt, or
delete it after an explicit confirmation.

To remove several transactions, tap **Select**, choose individual rows or use
**Select all** for every transaction in the active date range, then tap **Delete**.
The confirmation shows the number of selected sales and the active period before
anything is removed. Deleting sales also removes their saved receipt lines, but
never deletes products from the catalog.

Open **Profile → Settings → Storage manager** to measure the local database, managed
product images, temporary receipt copies, background-removal files, and other
cache. Safe cleanup removes only rebuildable temporary files. Product data,
sales, managed product images, gallery receipts, `.razestore` backups, and
catalog/CSV exports are never cleanup targets. Gallery and Files copies live
outside the app, so their sizes are not included in the displayed total. The
installed app binary, bundled background-removal model, and OS/native support
data are also outside this measured total; use the phone's system Storage page
for the complete installed size. SQLite can reuse freed database space, so
deleting records may not shrink the database immediately and its WAL sidecar
can change size later.

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

Barcode scanning, guided photo framing, low-light detection, the flashlight,
label reading, and gallery export require a physical-device smoke test even when
the automated test suite passes.
