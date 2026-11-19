#!/usr/bin/env python3
"""Merge the manufacturer brand records into the bundled caffeine database.

Reads docs/caffeine-brands-provenance.json (values copied by hand from each
maker's own website or label, with URL, date, serving and quote) and writes
them into AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json under the
"manufacturer" source. No network access and no values of its own: a brand
without a provenance record is not added and shows Not in Database.
Run after scripts/build_caffeine_db.py, which rewrites the database file.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROVENANCE = ROOT / "docs/caffeine-brands-provenance.json"
DB = ROOT / "AuroraCore/Sources/AuroraCore/Resources/caffeine-db.json"

SOURCE = {
    "id": "manufacturer",
    "name": "Manufacturer",
    "release": "2026-11-10",
    "license": "Caffeine amounts as published by each drink's maker on its own website or label",
    "url": "",
    "citation": "Each record names the maker's page it was copied from and the date it was read; see docs/caffeine-brands-provenance.json.",
}
NOTICE = ("Caffeine values copied from USDA FoodData Central records and, for named brands, from each maker's "
          "own website or label. Serving mg = record caffeine per 100 g or mL x the record's own portion size, "
          "rounded to a whole mg.")


def main() -> None:
    prov = json.loads(PROVENANCE.read_text())
    db = json.loads(DB.read_text())
    db["notice"] = NOTICE
    db["sources"] = [s for s in db["sources"] if s["id"] != SOURCE["id"]] + [SOURCE]
    db["entries"] = [e for e in db["entries"] if e.get("source") != SOURCE["id"]]
    for r in prov["records"]:
        ml, mg = r["servingMl"], r["mg"]
        assert ml > 0 and 1 <= mg <= 1999, r["id"]
        per100 = r["per100mL"]
        assert int(round(per100 * ml / 100)) == mg, f"{r['id']}: per100mL does not reproduce mg"
        assert r["url"].startswith("https://") and r["retrievedAt"] and r["quote"], r["id"]
        entry = {"id": r["id"], "source": SOURCE["id"], "name": r["name"]}
        if r.get("brand"):
            entry["brand"] = r["brand"]
        entry.update({
            "category": r["category"], "per100": per100, "basis": "mL",
            "servings": [{"label": r["servingSize"], "amount": float(ml), "unit": "mL", "mg": mg}],
            "url": r["url"], "retrieved": r["retrievedAt"],
        })
        db["entries"].append(entry)
    with DB.open("w", encoding="utf-8") as fh:
        json.dump(db, fh, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
        fh.write("\n")
    print(f"merged {len(prov['records'])} manufacturer records into {DB.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
