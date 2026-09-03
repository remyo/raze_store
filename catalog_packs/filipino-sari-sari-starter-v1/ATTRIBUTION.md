# Data, image, and price attribution

## Philippine DTI suggested retail prices

This pack reproduces factual product names, units, regional/market qualifiers,
and 191 historical prices from the Philippines Department of Trade and
Industry **Suggested Retail Prices of Basic Necessities and Prime Commodities
as of 1 February 2025**:

https://www.dti.gov.ph/wp-content/uploads/2025/08/BNPCSRPBULLETIN01FEBRUARY2025.002.pdf

The source PDF used for this revision has SHA-256
`5f5b119ad6f3e9112c20ee6efab0b39d5da7be4c51afc7426c78aa8eced66aaf`.
Each row identifies the bulletin, effective date, and source URL in
`referencePrice`. These are historical suggested retail prices, not guaranteed
current or store-specific prices. Qualifiers such as NCR, Luzon, Visayas and
Mindanao, supermarket (SMKT), and wet market (WMKT) are retained because they
can affect the listed price.

## Open Food Facts product records and images

The original 20 image-backed product records are based on contributions to Open
Food Facts and are reused under the Open Database License 1.0. Individual
database contents are under the Database Contents License 1.0.

Their bundled product images are based on Open Food Facts contributions and are
reused at 256 px under Creative Commons Attribution-ShareAlike 3.0. Each record
retains its source product page and original image URL. Package artwork and
trademarks may be subject to additional third-party rights.

Open Food Facts: https://world.openfoodfacts.org/

## Retailer-observed starting prices

Seventeen image-backed products are not exact entries in the DTI bulletin.
Their positive starting prices are exact-product observations from Philippine
retailer pages, checked on 3 September 2026 and labeled `retailer_price` rather
than `srp`. The retailer name, product URL, observation date, and warning that
prices vary are retained on every affected record in `source.json` and in the
built `catalog.json`.

These observations come from AtHome Online Store, Citimart, Daily Supermarket,
Ever Supermarket, Gaisano, Iloilo Supermart, Puregold, Shield Drugstore, Sta.
Lucia Grocers, and Talcreco. Retailer pages and prices can change after the
snapshot date; the store owner's confirmed local selling price is authoritative.
