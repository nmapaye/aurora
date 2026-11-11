# Drink photo logging

Owner request (Nov 10, 2026): take or choose a photo of a drink, infer it with
the person's confirmation, and use a comprehensive database for caffeine values.

## Flow

1. Composer camera button → **Log from Photo** sheet → **Take Photo** (system
   camera; iOS asks for camera permission at this point only) or **Choose Photo**
   (PhotosPicker runs out of process; no photo-library permission is requested).
2. The photo is read **on device** by Apple frameworks only:
   - Vision `VNRecognizeTextRequest` (label text and container size),
   - Vision `VNDetectBarcodesRequest` (UPC/EAN → exact database lookup),
   - Vision `VNClassifyImageRequest` (drink kind words).

   No language model reads the photo. An earlier iOS 27 Foundation Models
   image-attachment path was removed (Nov 10, 2026): it was behind
   `compiler(>=6.4)`, and CI builds with Xcode 26.6 / Swift 6.3, so it could
   never be type-checked or tested before shipping. Re-adding it needs an SDK
   that CI builds, with tests. Never Private Cloud Compute, never a
   third-party or network model.
3. AuroraCore matches that evidence against the bundled database
   (`DrinkPhotoMatcher`): barcode first, then IDF-weighted token match with
   one-letter OCR tolerance and a brand bonus. Below the threshold it asks
   instead of guessing.
4. Confirmation card (`DrinkPhotoConfirmation`): drink candidates (or database
   search), size (label volume read by Vision, or the record's listed servings;
   a label size is preselected only when one of the record's own servings is
   the same size, so a misread label is never picked for the person),
   caffeine mg with its source line, editable amount, and time. **Save** is the
   only write; `autosaveEnabled` is `false` with no override. The saved entry's
   note keeps the provenance (dataset, FDC id, serving). After Save the
   conversation shows the standard "Caffeine saved" card with Undo for that
   entry.
   - **Not in Database**: when nothing matches (or the person taps **Enter It
     Yourself**), they name the drink and type the amount. The note says
     "Typed by you · not in Aurora’s database"; no database number is used.
5. The photo is held in memory and dropped when the sheet closes. It is never
   written to disk or the photo library, and never sent anywhere.

## No invented numbers

- Every mg comes from a USDA FoodData Central record or, for the named brands
  below, the maker's own website or label: the listed serving's mg,
  or the record's per-100 value times a label volume. For gram-based records a
  label volume converts only through that record's own "1 fl oz" portion weight;
  otherwise the person picks a listed serving.
- Container sizes come only from text Vision read in the photo. Model output is
  search words only; its numbers are never used (tested).
- A typed amount is marked "Typed by you (database: N mg)".
- The database fails closed: `CaffeineDatabase.load` rejects the file if any
  serving mg isn't reproducible from its per-100 value, a source is unknown, or
  a record has neither an FDC id nor an https page with its retrieval date.

## Database

`AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json`, built by
`scripts/build_caffeine_db.py` from USDA FoodData Central bulk downloads:

| Source | Release | Entries |
| --- | --- | --- |
| FNDDS 2021-2023 (survey foods: coffee, tea, energy drinks, sodas with portion sizes) | 2024-10-31 | 201 |
| SR Legacy (beverages) | 2018-04 | 79 |
| Global Branded Food Products (label data with caffeine, liquids, with GTIN) | 2026-10-29 | 165 |

License: CC0 1.0 Universal (public domain). USDA asks for attribution, which
is in the JSON per source and shown behind the card's (i) button. Rebuild:

```
python3 scripts/build_caffeine_db.py --fndds surveyDownload.json \
  --sr FoodData_Central_sr_legacy_food_json_2018-04.json \
  --branded-dir FoodData_Central_branded_food_csv_2026-10-29 \
  --out AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json
```

### Named brands: the maker's own website or label

USDA has no drink record with caffeine for the brands named in Nov 10 feedback,
so each one gets a record only when its maker states the amount in mg on its
own website or label. No aggregators, retailers or encyclopedias. The values
were read by hand on Nov 10, 2026. `docs/caffeine-brands-provenance.json`
holds each record's page URL, retrieval date, serving size, a verbatim quote
and the SHA-256 of what was read. `scripts/merge-manufacturer-caffeine.py`
(no network) writes those records into the database under the "manufacturer"
source. Run it after `build_caffeine_db.py`, which rewrites the file:

```
python3 scripts/merge-manufacturer-caffeine.py
```

On the card, one short line sits under the amount, showing source and serving only:
"Manufacturer · 1 Can (12 fl oz)", "USDA · 1 Cup (8 fl oz)", "Typed by You". The (i)
button next to it holds the rest: the full source line (FDC id or page), the
release or retrieved date, the credit, and "Visit USDA FoodData Central" or
"View Source Page" (the maker's page). There's no Settings credit; caveats belong
in the Terms text (#87's `LegalCopy`), not in the app UI.

| Brand | Record | Serving | mg | Source |
| --- | --- | --- | --- | --- |
| Celsius | Celsius Energy Drink | 1 can (12 fl oz, 355 mL) | 200 | celsius.com/essential-facts |
| Bang | Bang Energy | 1 can (16 fl oz, 473 mL) | 300 | bangenergy.com product page |
| Prime | Prime Energy | 1 can (12 fl oz, 355 mL) | 200 | PRIME help center (drinkprime.com/pages/faq) |
| Alani Nu | Alani Nu Energy Drink | 1 can (12 fl oz, 355 mL) | 200 | alaninu.com product page |
| C4 | C4 Performance Energy | 1 can (16 fl oz, 473 mL) | 200 | label image on cellucor.com |
| Starbucks | none | | | Starbucks lists a range (Grande Pike Place: 315 mg - 390 mg), not one value: Not in Database |
| Ghost Energy | none | | | No mg for the canned drink on a GHOST or Keurig Dr Pepper page: Not in Database |
| Dr Pepper | none | | | Keurig Dr Pepper publishes 41 mg and 43 mg for the same 12 fl oz product: Not in Database |
| 5-hour Energy | none | | | Berry is sold as Regular Strength, and its page shows "230mg of Caffeine" beside "Caffeine (200mg)": Not in Database |
| Matcha | none | | | Manual entry only |

The rule (CPO, Nov 10): store one published number for one exact product and
serving, or store nothing. Never pick between numbers, average them or scale
them. So a maker's record is used only at its recorded serving
(`Entry.publishedServingsOnly`): a label size that is that serving selects it,
and any other size, read from the photo or picked, falls back to Not in Database
and manual entry. The same applies to USDA Global Branded Food Products label
records (source id `branded-…`; CPO, Nov 10: one exact product), including a
Branded record that lists no serving, which is always Not in Database.
`CaffeineDatabase.mg(for:volume:)` never converts a maker's or Branded record.
Generic USDA foods (FNDDS, SR Legacy) still convert a picked cup or a label size
through their own per-100 value. Where a
page gives only fl oz, mL is fl oz x 29.5735, rounded; that's a unit conversion
of the published serving, not a scaled amount. Flavors and variants (for example
Celsius Essentials, Prime's 16 oz can) aren't included. The person confirms or
types the amount either way.

### Sources evaluated and not bundled

- **Open Food Facts**: ODbL (share-alike database obligations). Caffeine is
  rarely filled in. Not bundled.
- **CSPI and similar charts**: copyrighted editorial tables. Not bundled.

### Known coverage limits

US label data rarely reports caffeine, so the Branded set is mostly
Coca-Cola-family drinks, Gold Peak, Polar and a few energy brands. Major energy
drinks (Red Bull, Monster, Rockstar, NOS, AMP, Full Throttle, Vault, XS) are in
FNDDS/SR as generic records with can sizes. Coffee-shop menu items (Starbucks
sizes, for example) are covered only by generic FNDDS coffee records
(small/medium/large and fl oz portions), not by chain-specific values.
