# Raze Store

Raze Store is an offline-first barcode price lookup and cart calculator for
Filipino sari-sari stores. It helps a family member or store helper find the
owner's price, calculate a customer's basket, and share a digital receipt
without turning the app into an inventory or sales-tracking system.

## MVP scope

- Browse and search every product carried by the store
- Add, edit, photograph, and delete local products
- Scan EAN/UPC/Code 128 barcodes on-device
- Add repeated products to one cart line and adjust quantity
- Calculate line subtotals, cash received, change, and a PHP total
- Preview, save, and share a receipt image
- Keep the unfinished cart locally across accidental restarts

The cart is intentionally temporary. Raze Store does not record sold items,
decrement stock, keep sales history, calculate profit, or track aging.

## Offline-first architecture

```text
Flutter screen
    -> Riverpod provider/controller
    -> repository interface
    -> Drift / SQLite on the device
```

The future `raze_store_api` service will supply shared Philippine product
metadata such as barcode, name, brand, size, category, and image. Each store's
selling price remains local and authoritative because prices differ by store.
The local repository is already separated from presentation code so a remote
catalog source can be added without replacing the app screens.

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
