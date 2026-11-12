#!/usr/bin/env python3
"""Builds the downloadable content packages and their manifest (content/packages/).

Each package is a full chapter that supersedes the bundled sample of the same collection. Text is extracted
verbatim from the same sources and with the same rules as build_sample_library.py (it reads that script's
cache and never touches the network). Metadata, IDs and theme tags are copied from the bundled sample library
so passage IDs (and therefore bookmarks, notes and history) carry over unchanged.

Usage: python3 -I tools/content/build_download_packages.py <cache-dir> <sample_library.json> <output-dir>
"""
import hashlib, html, json, os, re, sys

CACHE, SAMPLE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
sample = json.load(open(SAMPLE, encoding="utf-8"))


def cached(name):
    path = os.path.join(CACHE, name)
    assert os.path.exists(path), f"missing cache file {name}: run build_sample_library.py first"
    return open(path, encoding="utf-8").read()


def wikisource_lines(name):
    h = json.loads(cached(name))["parse"]["text"]
    h = re.sub(r"<style.*?</style>", "", h, flags=re.S)
    h = re.sub(r"<(br|/p|/div|/li|/tr)[^>]*>", "\n", h)
    t = html.unescape(re.sub(r"<[^>]+>", "", h))
    return [l.strip() for l in t.replace("​", "").split("\n") if l.strip()]


def clean(s):
    s = re.sub(r"\s*\[\d+\]", "", s.replace("​", "").replace("﻿", ""))
    return " ".join(s.split())


def by_id(key, ident):
    return next(x for x in sample[key] if x["id"] == ident)


# --- Bhagavad Gita, Discourse 2 (all 72 verses), Besant 1922 ---
def gita():
    lines = wikisource_lines("besant2.json")
    deva = "०१२३४५६७८९"
    passages = []
    for v in range(1, 73):
        i = next(k for k, l in enumerate(lines) if l.endswith(f"({v})"))
        english = clean(re.sub(rf"\s*\({v}\)$", "", lines[i]))
        j = i - 1
        if lines[j].endswith("said:"):  # speaker heading printed before the English verse
            english = f"{lines[j]} {english}"
            j -= 1
        numeral = "".join(deva[int(c)] for c in str(v))
        assert re.search(rf"॥\s*{numeral}\s*॥$", lines[j]), (v, lines[j])
        sanskrit = [lines[j - 1], lines[j]]
        assert "॥" not in lines[j - 1], (v, lines[j - 1])
        if lines[j - 2].endswith("उवाच ।"):  # Sanskrit speaker line
            sanskrit.insert(0, lines[j - 2])
        passages.append(dict(id=f"gita.2.{v}", sectionID="gita.ch2", sequence=v, reference=f"Bhagavad Gita 2.{v}",
                             originalText="\n".join(sanskrit), texts={"gita-besant": english}))
    return passages


# --- Matthew 5 (all 48 verses), KJV; WEB where cached (5:3-10) ---
def matthew():
    kjv = json.loads(cached("mt5_kjv_getbible.json"))["verses"]
    web = {v["verse"]: clean(v["text"]) for v in json.loads(cached("mt5_web.json"))["verses"]}
    assert [v["verse"] for v in kjv] == list(range(1, 49))
    passages = []
    for kv in kjv:
        n = kv["verse"]
        texts = {"bible-kjv": clean(kv["text"])}
        if n in web:
            texts["bible-web"] = web[n]
        passages.append(dict(id=f"bible.matthew.5.{n}", sectionID="bible.matthew.5", sequence=n,
                             reference=f"Matthew 5:{n}", originalText=None, texts=texts))
    return passages


# --- Dhammapada, Chapter 1 Yamakavagga (verses 1-20): Pali, Sujato, Müller ---
def dhammapada():
    dhp = json.loads(cached("dhp.json"))
    mul = cached("muller.txt").replace("\r\n", "\n")
    mul = mul[mul.index("Chapter I. The Twin-Verses"):mul.index("Chapter II.")]
    passages = []
    for v in range(1, 21):
        keys = [k for k in dhp["keys_order"] if re.fullmatch(rf"dhp{v}:[1-9]\d*", k)]
        assert keys, v
        pali = "\n".join(dhp["root_text"][k].strip() for k in keys)
        suj = "\n".join(dhp["translation_text"][k].strip() for k in keys)
        m = re.search(rf"\n{v}\. (.*?)\n\n", mul, re.S)
        assert m, v
        passages.append(dict(id=f"dhammapada.{v}", sectionID="dhammapada.ch1", sequence=v, reference=f"Dhammapada {v}",
                             originalText=pali, texts={"dhp-sujato": suj, "dhp-muller": clean(m.group(1).replace("--", "—"))}))
    return passages


PACKAGES = [
    ("bhagavad-gita-ch2", "bhagavad-gita", "gita", "Bhagavad Gita · Chapter 2 (complete)", gita),
    ("bible-matthew-5", "bible", "bible.matthew", "Bible · Matthew 5 (complete)", matthew),
    ("dhammapada-ch1", "tripitaka", "dhammapada", "Dhammapada · Chapter 1 (complete)", dhammapada),
]

def license_summary(sources):
    """Distinct licenses, dropping one that another merely extends ("Public domain" vs "Public domain (...)")."""
    licenses = sorted({s["license"] for s in sources})
    return "; ".join(l for l in licenses if not any(o != l and o.startswith(l) for o in licenses))


sample_passages = {p["id"]: p for p in sample["passages"]}
manifest = []
for package_id, collection_id, book_id, title, build in PACKAGES:
    passages = build()
    # Every sample passage of this collection must reappear with identical text, so IDs and content agree.
    for p in passages:
        if p["id"] in sample_passages:
            s = sample_passages[p["id"]]
            assert s["texts"] == p["texts"] and s["originalText"] == p["originalText"], f"{p['id']} differs from sample"
            p["themes"] = s.get("themes", [])
        else:
            p["themes"] = []
    collection = dict(by_id("collections", collection_id), availability="downloaded")
    translations = [t for t in sample["translations"] if t["collectionID"] == collection_id]
    source_ids = {t["sourceID"] for t in translations} | ({collection["originalSourceID"]} - {None})
    used_themes = {t for p in passages for t in p["themes"]}
    package = {
        "schemaVersion": 3,
        "religions": [by_id("religions", collection["religionID"])],
        "sources": [s for s in sample["sources"] if s["id"] in source_ids],
        "collections": [collection],
        "translations": translations,
        "books": [by_id("books", book_id)],
        "sections": [s for s in sample["sections"] if s["bookID"] == book_id],
        "themes": [t for t in sample["themes"] if t["id"] in used_themes],
        "passages": passages,
    }
    data = (json.dumps(package, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    file_name = f"{package_id}.json"
    open(os.path.join(OUT, file_name), "wb").write(data)
    sources = [s for s in sample["sources"] if s["id"] in source_ids]
    manifest.append({
        "id": package_id, "collectionID": collection_id, "title": title, "version": 1,
        "languages": collection["languages"], "fileSize": len(data),
        "sources": [s["name"] for s in sources],
        "license": license_summary(sources),
        "sha256": hashlib.sha256(data).hexdigest(), "schemaVersion": 3,
        "passageCount": len(passages), "path": file_name,
    })
    print(f"{package_id}: {len(passages)} passages, {len(data)} bytes")

with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump({"manifestVersion": 1, "packages": manifest}, f, ensure_ascii=False, indent=2)
    f.write("\n")
