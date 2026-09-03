# Filipino Sari-sari Starter Catalog v1

This is a small, reviewed proof source for the app's offline `.razepack`
workflow. It contains 20 packaged food and drink products and one optimized
256 px image per product. It is intentionally not described as a complete
Philippine catalog.

Build it from the repository root:

```sh
python3 tool/build_catalog_pack.py \
  catalog_packs/filipino-sari-sari-starter-v1/source.json \
  outputs/filipino-sari-sari-starter-v1.razepack
```

Only three rows contain `suggestedPriceCentavos`. Those values are exact
product/size matches from the dated DTI BNPC SRP bulletin named in each row;
they are historical references, not guaranteed current store prices. The other
products intentionally import at zero so the owner must confirm a selling
price before they can be added to the cart.

Product metadata comes from Open Food Facts contributors under ODbL 1.0 / DbCL
1.0. Product images come from Open Food Facts contributors under CC BY-SA 3.0.
Each source row retains the original product and image URLs. Package artwork
may be subject to additional third-party rights.

Do not scale this by inventing barcodes or prices. A larger release should be
built from the Open Food Facts bulk export and bulk image dataset, deduplicated,
category-balanced, and manually checked before publication.
