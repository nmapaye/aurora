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

- Every mg comes from a USDA FoodData Central record: the listed serving's mg,
  or the record's per-100 value times a label volume. For gram-based records a
  label volume converts only through that record's own "1 fl oz" portion weight;
  otherwise the person picks a listed serving.
- Container sizes come only from text Vision read in the photo. Model output is
  search words only; its numbers are never used (tested).
- A typed amount is marked "Typed by you (database: N mg)".
- The database fails closed: `CaffeineDatabase.load` rejects the file if any
  serving mg isn't reproducible from its per-100 value or a source is unknown.

## Database

`AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json`, built by
`scripts/build_caffeine_db.py` from USDA FoodData Central bulk downloads:

| Source | Release | Entries |
| --- | --- | --- |
| FNDDS 2021-2023 (survey foods: coffee, tea, energy drinks, sodas with portion sizes) | 2024-10-31 | 201 |
| SR Legacy (beverages) | 2018-04 | 79 |
| Global Branded Food Products (label data with caffeine, liquids, with GTIN) | 2026-10-29 | 165 |

License: CC0 1.0 Universal (public domain). USDA asks for attribution, which
is in the JSON per source and shown on the card. Rebuild:

```
python3 scripts/build_caffeine_db.py --fndds surveyDownload.json \
  --sr FoodData_Central_sr_legacy_food_json_2018-04.json \
  --branded-dir FoodData_Central_branded_food_csv_2026-10-29 \
  --out AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json
```

### Sources evaluated and not bundled

- **Caffeine Informer**: its terms (updated Jan 21, 2021) grant a royalty-free
  license to the caffeine amounts if you link to and credit caffeineinformer.com.
  It has no bulk export, so bundling would mean collecting page by page. Not
  done here; an owner decision.
- **Open Food Facts**: ODbL (share-alike database obligations). Caffeine is
  rarely filled in. Not bundled.
- **CSPI and similar charts**: copyrighted editorial tables. Not bundled.

### Known coverage limits

Brands named in Nov 10 feedback, checked against the bundled database and the
full USDA inputs (`DrinkPhotoCoverageAndGuardTests.namedBrandCoverageIsRecorded`):

| Brand | Brand-specific record | In USDA FDC with caffeine |
| --- | --- | --- |
| Celsius, Starbucks, Bang, Ghost, Prime, 5-hour, C4, matcha, Dr Pepper | No | No (Branded label data has no caffeine for them; Starbucks and Dr Pepper have generic FNDDS coffee and pepper-type soft drink records) |
| Alani | No | Only Alani Nu powder "energy sticks" (5.8 g), not the canned drink; not bundled (the build keeps liquid label data only) |

Adding these needs a licensable source with provenance; that's an owner
decision.

US label data rarely reports caffeine, so the Branded set is mostly
Coca-Cola-family drinks, Gold Peak, Polar and a few energy brands. Major energy
drinks (Red Bull, Monster, Rockstar, NOS, AMP, Full Throttle, Vault, XS) are in
FNDDS/SR as generic records with can sizes. Coffee-shop menu items (Starbucks
sizes, for example) are covered only by generic FNDDS coffee records
(small/medium/large and fl oz portions), not by chain-specific values.
