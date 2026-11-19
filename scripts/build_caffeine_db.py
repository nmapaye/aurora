#!/usr/bin/env python3
"""Build Aurora's bundled offline caffeine database from USDA FoodData Central.

All inputs are USDA FoodData Central bulk downloads, public domain under
CC0 1.0 (https://fdc.nal.usda.gov/api-guide/#bkmk-9). No other source is read.
Every caffeine value in the output is copied from an FDC record: the record's
caffeine per 100 g (or per 100 mL for Branded label data) and, for each
serving, that record's own portion weight. The only arithmetic is
mg = per100 * portion / 100, rounded to a whole mg (Aurora stores whole mg).

Usage:
  build_caffeine_db.py --fndds surveyDownload.json \
      --sr FoodData_Central_sr_legacy_food_json_2018-04.json \
      --branded-dir FoodData_Central_branded_food_csv_2026-10-29 \
      --out AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json
"""
import argparse, csv, json, math, os, re, sys

CAFFEINE = 1057
FL_OZ_ML = 29.5735
VERSION = "2026.11.1"

FNDDS_CATEGORIES = {
    "Coffee": "coffee", "Tea": "tea",
    "Sport and energy drinks": "energy", "Diet sport and energy drinks": "energy",
    "Soft drinks": "soda", "Diet soft drinks": "soda",
    "Flavored milk, whole": "other", "Flavored milk, reduced fat": "other",
    "Flavored milk, lowfat": "other", "Flavored milk, nonfat": "other",
    "Milk shakes and other dairy drinks": "other", "Plant-based milk": "other",
    "Nutritional beverages": "other", "Liquor and cocktails": "other",
}
BRANDED_CATEGORIES = re.compile(r"beverage|drink|coffee|tea|soda|water", re.I)
DRY = re.compile(r"not reconstituted|\bdry\b|powder(?!, prepared)|instant, regular|instant, with chicory|syrup$|\bmix\b(?!.*prepared)", re.I)


def category_for(text):
    t = text.lower()
    if "energy" in t: return "energy"
    if "espresso" in t or "coffee" in t or "latte" in t or "cappuccino" in t or "mocha" in t or "cold brew" in t: return "coffee"
    if "matcha" in t: return "tea"
    if "tea" in t: return "tea"
    if "cola" in t or "soda" in t or "carbonated" in t or "soft drink" in t or "pepper" in t: return "soda"
    return "other"


def serving(label, amount, per100, unit):
    if amount is None or amount <= 0: return None
    # Half away from zero, matching Swift's rounded(); Python's round() is banker's.
    mg = int(math.floor(per100 * amount / 100 + 0.5))
    if mg < 1: return None
    return {"label": label, "amount": round(amount, 1), "unit": unit, "mg": mg}


def per_fl_oz(portions):
    for label, grams in portions:
        if re.fullmatch(r"1 fl oz|fl oz", label.strip().lower()) and grams > 0:
            return round(grams, 2)
    return None


def fndds(path):
    out = []
    for f in json.load(open(path))["SurveyFoods"]:
        cat = f.get("wweiaFoodCategory", {}).get("wweiaFoodCategoryDescription", "")
        if cat not in FNDDS_CATEGORIES or DRY.search(f["description"]): continue
        caf = [n.get("amount", 0) for n in f["foodNutrients"] if n["nutrient"]["id"] == CAFFEINE]
        if not caf or caf[0] <= 0: continue
        portions = [(p["portionDescription"], p["gramWeight"]) for p in f["foodPortions"]
                    if p["gramWeight"] > 0 and p["portionDescription"] != "Quantity not specified"]
        servings = [s for s in (serving(l, g, caf[0], "g") for l, g in sorted(portions, key=lambda x: x[1])) if s]
        brand = re.search(r"\(([^)]+)\)", f["description"])
        out.append({
            "id": f"fdc:{f['fdcId']}", "fdcId": f["fdcId"], "source": "fndds-2021-2023",
            "name": f["description"], "brand": brand.group(1) if brand else None,
            "category": FNDDS_CATEGORIES[cat] if FNDDS_CATEGORIES[cat] != "other" else category_for(f["description"]),
            "per100": caf[0], "basis": "g", "gramsPerFlOz": per_fl_oz(portions), "servings": servings,
        })
    return out


def sr_legacy(path):
    out = []
    for f in json.load(open(path))["SRLegacyFoods"]:
        if f["foodCategory"]["description"] != "Beverages" or DRY.search(f["description"]): continue
        caf = [n.get("amount", 0) for n in f["foodNutrients"] if n["nutrient"]["id"] == CAFFEINE]
        if not caf or caf[0] <= 0: continue
        portions = []
        for p in f.get("foodPortions", []):
            if p.get("gramWeight", 0) <= 0: continue
            amount = p.get("amount") or 1
            label = f"{amount:g} {p.get('modifier', '').strip()}".strip()
            portions.append((label, p["gramWeight"]))
        servings = [s for s in (serving(l, g, caf[0], "g") for l, g in sorted(portions, key=lambda x: x[1])) if s]
        name = re.sub(r"^Beverages,\s*", "", f["description"]).strip()
        name = name[:1].upper() + name[1:]
        out.append({
            "id": f"fdc:{f['fdcId']}", "fdcId": f["fdcId"], "source": "sr-legacy-2018",
            "name": name, "brand": None, "category": category_for(name),
            "per100": caf[0], "basis": "g", "gramsPerFlOz": per_fl_oz(portions), "servings": servings,
        })
    return out


def branded(directory):
    csv.field_size_limit(10**9)
    caf = {}
    with open(os.path.join(directory, "food_nutrient.csv"), encoding="utf-8") as fh:
        for r in csv.reader(fh):
            if len(r) > 3 and r[2] == str(CAFFEINE):
                try: caf[r[1]] = float(r[3])
                except ValueError: pass
    rows = {}
    with open(os.path.join(directory, "branded_food.csv"), encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["fdc_id"] in caf and caf[r["fdc_id"]] > 0: rows[r["fdc_id"]] = r
    with open(os.path.join(directory, "food.csv"), encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["fdc_id"] in rows: rows[r["fdc_id"]]["description"] = r["description"]
    best = {}
    for fid, r in rows.items():
        unit = r["serving_size_unit"].strip().upper()
        if unit not in ("ML", "MLT"): continue  # liquid label data only; mg per 100 mL
        if r.get("discontinued_date"): continue
        if not BRANDED_CATEGORIES.search(r["branded_food_category"] or "") and not BRANDED_CATEGORIES.search(r.get("description", "")): continue
        if DRY.search(r.get("description", "")): continue
        try: size = float(r["serving_size"])
        except ValueError: continue
        per100 = caf[fid]
        if per100 > 100: continue  # implausible for a ready-to-drink label (per 100 mL); excluded, not corrected
        label = (r["household_serving_fulltext"] or "").strip() or f"{size:g} mL"
        label = f"{label} ({size:g} mL)" if "ml" not in label.lower() else label
        s = serving(label, size, per100, "mL")
        if not s: continue
        name = r.get("description", "").strip()
        brand = re.sub(r"-\d{6,}$", "", (r["brand_name"] or r["brand_owner"] or "").strip()) or None
        key = r["gtin_upc"].lstrip("0") or fid
        entry = {
            "id": f"fdc:{fid}", "fdcId": int(fid), "source": "branded-2026-10",
            "name": name, "brand": brand, "category": category_for(name + " " + (r["branded_food_category"] or "")),
            "per100": per100, "basis": "mL", "gramsPerFlOz": None, "servings": [s],
            "gtin": r["gtin_upc"].strip() or None, "modified": r["modified_date"],
        }
        if key not in best or entry["modified"] > best[key]["modified"]: best[key] = entry
    out = list(best.values())
    for e in out: e.pop("modified")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fndds", required=True); ap.add_argument("--sr", required=True)
    ap.add_argument("--branded-dir", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    entries = fndds(a.fndds) + sr_legacy(a.sr) + branded(a.branded_dir)
    entries = [e for e in entries if e["servings"] or e["gramsPerFlOz"] or e["basis"] == "mL"]
    for e in entries:
        e["name"] = re.sub(r"\s+", " ", e["name"]).strip()
        if e.get("gramsPerFlOz") is None: e.pop("gramsPerFlOz", None)
        if not e.get("gtin"): e.pop("gtin", None)
        if not e.get("brand"): e.pop("brand", None)
    entries.sort(key=lambda e: (e["source"], e["name"].lower(), e["fdcId"]))
    db = {
        "schema": 1, "version": VERSION,
        "notice": "Caffeine values copied from USDA FoodData Central records. Serving mg = record caffeine per 100 g or mL x the record's own portion size, rounded to a whole mg.",
        "sources": [
            {"id": "fndds-2021-2023", "name": "USDA FoodData Central, Survey (FNDDS) 2021-2023", "release": "2024-10-31",
             "license": "CC0 1.0 Universal (public domain)", "url": "https://fdc.nal.usda.gov/",
             "citation": "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central: Food and Nutrient Database for Dietary Studies 2021-2023. 2024. fdc.nal.usda.gov."},
            {"id": "sr-legacy-2018", "name": "USDA FoodData Central, SR Legacy", "release": "2018-04",
             "license": "CC0 1.0 Universal (public domain)", "url": "https://fdc.nal.usda.gov/",
             "citation": "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central: SR Legacy. 2018. fdc.nal.usda.gov."},
            {"id": "branded-2026-10", "name": "USDA FoodData Central, Global Branded Food Products Database", "release": "2026-10-29",
             "license": "CC0 1.0 Universal (public domain)", "url": "https://fdc.nal.usda.gov/",
             "citation": "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central: USDA Global Branded Food Products Database. Version Current: October 2026. fdc.nal.usda.gov. Label data are manufacturer submissions."},
        ],
        "entries": entries,
    }
    with open(a.out, "w") as fh:
        json.dump(db, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
        fh.write("\n")
    by = {}
    for e in entries: by[e["source"]] = by.get(e["source"], 0) + 1
    print(f"{len(entries)} entries", by, file=sys.stderr)


if __name__ == "__main__":
    main()
