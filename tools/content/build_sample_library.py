#!/usr/bin/env python3
"""Builds SacredWisdom/Resources/Database/sample_library.json from verified public sources.

Scripture text is extracted verbatim from each source. The only transformations are:
  * removal of editorial footnote markers such as "[12]" and zero-width spaces,
  * joining of print line-wraps into single lines and collapsing whitespace,
  * removal of a space before ; : ? ! that is a 1909 typesetting artifact (Macauliffe only),
  * Project Gutenberg's plain-text "--" rendered as an em dash (Müller only).
Everything hand-authored here is metadata: hierarchy, references, attribution, licenses, and
editorial themes. A theme is a label for what a passage explicitly speaks of; each tag names the
word in the passage's own translation text that justifies it, and the build fails if that word is absent.

Usage: python3 -I tools/content/build_sample_library.py <cache-dir> <output-json>
"""
import html, json, os, re, sys, urllib.parse, urllib.request

CACHE, OUT = sys.argv[1], sys.argv[2]
os.makedirs(CACHE, exist_ok=True)
UA = {"User-Agent": "SacredWisdomContentBuilder/1.0"}


def fetch(name, url):
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
            open(path, "wb").write(r.read())
    return open(path, encoding="utf-8").read()


def wikisource_text(name, title):
    url = "https://en.wikisource.org/w/api.php?" + urllib.parse.urlencode(
        {"action": "parse", "page": title, "prop": "text", "formatversion": 2, "format": "json"})
    h = json.loads(fetch(name, url))["parse"]["text"]
    h = re.sub(r"<style.*?</style>", "", h, flags=re.S)
    h = re.sub(r"<(br|/p|/div|/li|/tr)[^>]*>", "\n", h)
    t = html.unescape(re.sub(r"<[^>]+>", "", h))
    return [l.strip() for l in t.replace("​", "").split("\n") if l.strip()]


def clean(s):
    s = re.sub(r"\s*\[\d+\]", "", s.replace("​", "").replace("﻿", ""))
    return " ".join(s.split())


passages, sources, translations = [], {}, []


def source(id, name, url, license, attribution):
    sources[id] = dict(id=id, name=name, url=url, license=license, attribution=attribution)


def add(pid, section, seq, ref, original, texts):
    assert all(texts.values()), pid
    passages.append(dict(id=pid, sectionID=section, sequence=seq, reference=ref,
                         originalText=original, texts=texts))


# --- Hinduism: Bhagavad Gita 2.47-2.50 (Besant 4th ed. prints Sanskrit and English) ---
source("besant-1922", "The Bhagavad-Gita, tr. Annie Besant, 4th ed. (1922), via Wikisource",
       "https://en.wikisource.org/wiki/Bhagavad-Gita_(Besant_4th)", "Public domain",
       "Translated by Annie Besant (1847–1933). Sanskrit text as printed in the same edition.")
lines = wikisource_text("besant2.json", "Bhagavad-Gita_(Besant_4th)/Discourse_2")
deva = "०१२३४५६७८९"
for v in range(47, 51):
    i = next(k for k, l in enumerate(lines) if re.search(rf"\({v}\)$", l))
    num = "".join(deva[int(c)] for c in str(v))
    sk = [lines[i - 2], lines[i - 1]]
    assert sk[1].endswith(f"॥ {num} ॥"), (v, sk)
    english = clean(re.sub(rf"\s*\({v}\)$", "", lines[i]))
    add(f"gita.2.{v}", "gita.ch2", v, f"Bhagavad Gita 2.{v}", "\n".join(sk), {"gita-besant": english})

# --- Christianity: Matthew 5:3-10, KJV and WEB ---
source("kjv", "King James Version (1769 Oxford standard text), via getbible.net", "https://getbible.net",
       "Public domain (Crown rights apply in the United Kingdom)", "King James Version, 1769 Oxford standard text.")
source("web", "World English Bible, via bible-api.com", "https://worldenglish.bible", "Public domain",
       "World English Bible.")
# KJV from getbible.net: bible-api.com's KJV drops the apostrophe in "righteousness' sake" (5:10).
kjv = [v for v in json.loads(fetch("mt5_kjv_getbible.json", "https://api.getbible.net/v2/kjv/40/5.json"))["verses"]
       if 3 <= v["verse"] <= 10]
web = json.loads(fetch("mt5_web.json", "https://bible-api.com/matthew+5:3-10?translation=web"))["verses"]
assert len(kjv) == len(web) == 8
for kv, wv in zip(kjv, web):
    assert kv["verse"] == wv["verse"]
    v = kv["verse"]
    add(f"bible.matthew.5.{v}", "bible.matthew.5", v, f"Matthew 5:{v}", None,
        {"bible-kjv": clean(kv["text"]), "bible-web": clean(wv["text"])})

# --- Islam: Surah 1 Al-Fatihah, Tanzil Uthmani Arabic and Pickthall ---
source("tanzil", "Tanzil Quran Text (Uthmani), via api.alquran.cloud", "https://tanzil.net",
       "Tanzil license: verbatim copies permitted with attribution; changes not allowed",
       "Quran text © Tanzil Project (tanzil.net).")
source("pickthall-1930", "The Meaning of the Glorious Koran, tr. Marmaduke Pickthall (1930), via api.alquran.cloud",
       "https://api.alquran.cloud", "Public domain", "Translated by Marmaduke Pickthall (1875–1936).")
q = json.loads(fetch("fatiha.json", "https://api.alquran.cloud/v1/surah/1/editions/quran-uthmani,en.pickthall"))["data"]
assert q[0]["edition"]["identifier"] == "quran-uthmani" and q[1]["edition"]["identifier"] == "en.pickthall"
for ar, en in zip(q[0]["ayahs"], q[1]["ayahs"]):
    n = ar["numberInSurah"]
    add(f"quran.1.{n}", "quran.surah1", n, f"Al-Fatihah 1:{n}", ar["text"].replace("﻿", "").strip(),
        {"quran-pickthall": clean(en["text"])})

# --- Judaism: Psalm 23, Hebrew (Westminster Leningrad Codex) and JPS 1917 ---
source("wlc", "Tanach with Nikkud (Westminster Leningrad Codex), tanach.us, via Sefaria",
       "http://www.tanach.us/Tanach.xml", "Public domain", "Hebrew text from the Westminster Leningrad Codex.")
source("jps-1917", "The Holy Scriptures: A New Translation (JPS 1917), via Sefaria",
       "https://www.sefaria.org", "Public domain", "Jewish Publication Society, 1917.")
ps = json.loads(fetch("ps23.json", "https://www.sefaria.org/api/v3/texts/Psalms.23?version=hebrew%7CTanach%20with%20Nikkud&version=english%7CThe%20Holy%20Scriptures:%20A%20New%20Translation%20(JPS%201917)"))
vers = {v["versionTitle"]: v for v in ps["versions"]}
he = vers["Tanach with Nikkud"]["text"]
en = vers["The Holy Scriptures: A New Translation (JPS 1917)"]["text"]
assert vers["Tanach with Nikkud"]["license"] == "Public Domain" and len(he) == len(en) == 6
for i, (h, e) in enumerate(zip(he, en), 1):
    add(f"tanakh.psalms.23.{i}", "tanakh.psalms.23", i, f"Psalms 23:{i}", clean(h), {"tanakh-jps1917": clean(e)})

# --- Buddhism: Dhammapada 1-6, Pali, Sujato (CC0) and Müller (1881) ---
source("suttacentral", "SuttaCentral (bilara-data): Mahāsaṅgīti Pali root text and Sujato translation",
       "https://suttacentral.net/dhp1-20/en/sujato",
       "Translation: CC0 1.0. Pali root text: ancient canon (digital edition license to be confirmed)",
       "Translated by Bhikkhu Sujato. Pali from the Mahāsaṅgīti edition.")
source("muller-1881", "The Dhammapada, tr. F. Max Müller (1881), via Project Gutenberg",
       "https://www.gutenberg.org/ebooks/2017", "Public domain", "Translated by F. Max Müller (1823–1900).")
dhp = json.loads(fetch("dhp.json", "https://suttacentral.net/api/bilarasuttas/dhp1-20/sujato"))
mul = fetch("muller.txt", "https://www.gutenberg.org/cache/epub/2017/pg2017.txt").replace("\r\n", "\n")
mul = mul[mul.index("Chapter I. The Twin-Verses"):]
for v in range(1, 7):
    # Segment :0 / :0.n are editorial story titles (vatthu), not verse text.
    keys = [k for k in dhp["keys_order"] if re.fullmatch(rf"dhp{v}:[1-9]\d*", k)]
    pali = "\n".join(dhp["root_text"][k].strip() for k in keys)
    suj = "\n".join(dhp["translation_text"][k].strip() for k in keys)
    m = re.search(rf"\n{v}\. (.*?)\n\n", mul, re.S)
    add(f"dhammapada.{v}", "dhammapada.ch1", v, f"Dhammapada {v}", pali,
        {"dhp-sujato": suj, "dhp-muller": clean(m.group(1).replace("--", "—"))})

# --- Sikhism: Ang 1 (Mool Mantar, Salok, Pauris 1-2), Gurmukhi and Macauliffe (1909) ---
source("banidb", "Gurmukhi text of Sri Guru Granth Sahib, via BaniDB (Khalis Foundation)",
       "https://www.banidb.com", "Gurbani text: public domain (database terms to be confirmed)",
       "Gurmukhi text via BaniDB.")
source("macauliffe-1909", "The Sikh Religion, Vol. 1, tr. Max Arthur Macauliffe (1909), via Wikisource",
       "https://en.wikisource.org/wiki/The_Sikh_Religion/Volume_1/Japji", "Public domain",
       "Translated by Max Arthur Macauliffe (1841–1913).")
ang = {p["verseId"]: p["verse"]["unicode"] for p in json.loads(fetch("ang1.json", "https://api.banidb.com/v2/angs/1/G"))["page"]}
mac = wikisource_text("japji.json", "The_Sikh_Religion/Volume_1/Japji")
start = next(i for i, l in enumerate(mac) if l.startswith("THE JAPJI"))
mac = mac[start + 1:]


def mac_block(first, stop):
    a = next(i for i, l in enumerate(mac) if l.startswith(first))
    b = next(i for i in range(a + 1, len(mac)) if mac[i] == stop or mac[i].startswith(stop))
    s = clean(" ".join(mac[a:b]))
    return re.sub(r"\s+([;:?!])", r"\1", s)


i1, i2, i3 = mac.index("I"), mac.index("II"), mac.index("III")
sikh = [
    ("ggs.1.mool-mantar", "Ang 1 · Mool Mantar", [1], mac_block("There is but one God", "Repeat His Name")),
    ("ggs.1.salok", "Ang 1 · Japji Sahib, Salok", [3, 4], mac_block("The True One was in the beginning", "I")),
    ("ggs.1.pauri-1", "Ang 1 · Japji Sahib, Pauri 1", range(5, 11),
     re.sub(r"\s+([;:?!])", r"\1", clean(" ".join(mac[i1 + 1:i2])))),
    ("ggs.1.pauri-2", "Ang 1 · Japji Sahib, Pauri 2", range(11, 17),
     re.sub(r"\s+([;:?!])", r"\1", clean(" ".join(mac[i2 + 1:i3])))),
]
assert ang[4].endswith("॥੧॥") and ang[10].endswith("॥੧॥") and ang[16].endswith("॥੨॥")
for seq, (pid, ref, ids, en) in enumerate(sikh, 1):
    add(pid, "ggs.ang1", seq, ref, "\n".join(ang[i] for i in ids), {"ggs-macauliffe": en})

# --- Editorial themes (cross-tradition "related passages") ---
# theme id -> (display name, {passage id: evidence word that must appear in one of its translations})
THEMES = {
    "mercy": ("Mercy", {"bible.matthew.5.7": "merciful", "quran.1.1": "merciful", "quran.1.3": "merciful",
                        "tanakh.psalms.23.6": "mercy"}),
    "divine-name": ("The Divine Name", {"quran.1.1": "name", "tanakh.psalms.23.3": "name",
                                        "ggs.1.mool-mantar": "name"}),
    "guidance": ("Guidance on the Path", {"quran.1.6": "path", "quran.1.7": "path",
                                          "tanakh.psalms.23.2": "leadeth", "tanakh.psalms.23.3": "paths"}),
    "purity": ("Purity of Heart and Mind", {"bible.matthew.5.8": "pure", "dhammapada.2": "pure"}),
    "spiritual-hunger": ("Hunger for the Divine", {"bible.matthew.5.6": "hunger", "ggs.1.pauri-1": "hunger"}),
    "peace": ("Peace and the End of Hatred", {"bible.matthew.5.9": "peacemakers", "dhammapada.3": "hatred",
                                              "dhammapada.4": "hatred", "dhammapada.5": "hatred",
                                              "dhammapada.6": "conflicts"}),
    "comfort": ("Comfort in Sorrow", {"bible.matthew.5.4": "comforted", "tanakh.psalms.23.4": "comfort"}),
    "action-consequence": ("Action and Its Fruits", {"gita.2.47": "fruits", "gita.2.49": "fruit",
                                                     "dhammapada.1": "follows", "dhammapada.2": "follows"}),
    "sovereignty": ("God's Sovereignty", {"quran.1.2": "lord of the worlds", "quran.1.4": "master",
                                          "ggs.1.pauri-2": "all are subject"}),
}
by_id = {p["id"]: p for p in passages}
for theme_id, (_, tagged) in THEMES.items():
    for pid, evidence in tagged.items():
        texts = by_id[pid]["texts"].values()
        assert any(evidence in t.lower() for t in texts), f"{theme_id}: '{evidence}' not in {pid}"
        by_id[pid].setdefault("themes", []).append(theme_id)
for p in passages:
    p.setdefault("themes", [])

# --- Metadata ---
def tr(id, coll, name, lang, translator, year, src):
    translations.append(dict(id=id, collectionID=coll, name=name, languageCode=lang,
                             translator=translator, year=year, sourceID=src))

tr("gita-besant", "bhagavad-gita", "Annie Besant (1922)", "en", "Annie Besant", 1922, "besant-1922")
tr("bible-kjv", "bible", "King James Version", "en", "King James translators", 1769, "kjv")
tr("bible-web", "bible", "World English Bible", "en", "World English Bible translators", 2000, "web")
tr("quran-pickthall", "quran", "Pickthall (1930)", "en", "Marmaduke Pickthall", 1930, "pickthall-1930")
tr("tanakh-jps1917", "tanakh", "JPS 1917", "en", "Jewish Publication Society", 1917, "jps-1917")
tr("dhp-sujato", "tripitaka", "Bhikkhu Sujato", "en", "Bhikkhu Sujato", 2021, "suttacentral")
tr("dhp-muller", "tripitaka", "F. Max Müller (1881)", "en", "F. Max Müller", 1881, "muller-1881")
tr("ggs-macauliffe", "guru-granth-sahib", "Macauliffe (1909)", "en", "Max Arthur Macauliffe", 1909, "macauliffe-1909")

library = {
    "schemaVersion": 3,
    "religions": [
        {"id": "hinduism", "name": "Hinduism", "summary": "Ancient dharmic tradition of the Indian subcontinent.", "emblem": "ॐ", "tintKey": "saffron", "sortOrder": 0},
        {"id": "christianity", "name": "Christianity", "summary": "Faith centered on the life and teachings of Jesus.", "emblem": "✝", "tintKey": "sapphire", "sortOrder": 1},
        {"id": "islam", "name": "Islam", "summary": "Monotheistic faith revealed through the Prophet Muhammad.", "emblem": "☪", "tintKey": "emerald", "sortOrder": 2},
        {"id": "judaism", "name": "Judaism", "summary": "Covenantal tradition of the Hebrew Bible and Jewish people.", "emblem": "✡", "tintKey": "azure", "sortOrder": 3},
        {"id": "buddhism", "name": "Buddhism", "summary": "Path of awakening taught by the Buddha.", "emblem": "☸", "tintKey": "amber", "sortOrder": 4},
        {"id": "sikhism", "name": "Sikhism", "summary": "Faith founded by Guru Nanak in the Punjab.", "emblem": "☬", "tintKey": "indigo", "sortOrder": 5},
    ],
    "sources": list(sources.values()),
    "collections": [
        {"id": "bhagavad-gita", "religionID": "hinduism", "name": "Bhagavad Gita", "structureDescription": "18 chapters and verses", "languages": ["sa", "en"], "availability": "bundled", "originalLanguage": "sa", "originalSourceID": "besant-1922", "defaultTranslationID": "gita-besant"},
        {"id": "bible", "religionID": "christianity", "name": "Bible", "structureDescription": "Old and New Testament, books, chapters and verses", "languages": ["en"], "availability": "bundled", "originalLanguage": "en", "originalSourceID": None, "defaultTranslationID": "bible-kjv"},
        {"id": "quran", "religionID": "islam", "name": "Quran", "structureDescription": "114 Surahs and Ayahs", "languages": ["ar", "en"], "availability": "bundled", "originalLanguage": "ar", "originalSourceID": "tanzil", "defaultTranslationID": "quran-pickthall"},
        {"id": "tanakh", "religionID": "judaism", "name": "Tanakh", "structureDescription": "Torah, Nevi'im and Ketuvim", "languages": ["he", "en"], "availability": "bundled", "originalLanguage": "he", "originalSourceID": "wlc", "defaultTranslationID": "tanakh-jps1917"},
        {"id": "tripitaka", "religionID": "buddhism", "name": "Tripitaka and Sutras", "structureDescription": "Collections, texts and passages", "languages": ["pi", "en"], "availability": "bundled", "originalLanguage": "pi", "originalSourceID": "suttacentral", "defaultTranslationID": "dhp-sujato"},
        {"id": "guru-granth-sahib", "religionID": "sikhism", "name": "Guru Granth Sahib", "structureDescription": "Angs, hymns and passages", "languages": ["pa", "en"], "availability": "bundled", "originalLanguage": "pa", "originalSourceID": "banidb", "defaultTranslationID": "ggs-macauliffe"},
    ],
    "translations": translations,
    "books": [
        {"id": "gita", "collectionID": "bhagavad-gita", "title": "Bhagavad Gita", "division": "Bhishma Parva, Mahabharata", "sequence": 1},
        {"id": "bible.matthew", "collectionID": "bible", "title": "Matthew", "division": "New Testament", "sequence": 40},
        {"id": "quran", "collectionID": "quran", "title": "The Quran", "division": None, "sequence": 1},
        {"id": "tanakh.psalms", "collectionID": "tanakh", "title": "Psalms (Tehillim)", "division": "Ketuvim", "sequence": 14},
        {"id": "dhammapada", "collectionID": "tripitaka", "title": "Dhammapada", "division": "Khuddaka Nikāya, Sutta Piṭaka", "sequence": 1},
        {"id": "ggs.japji", "collectionID": "guru-granth-sahib", "title": "Japji Sahib", "division": "Guru Nanak", "sequence": 1},
    ],
    "sections": [
        {"id": "gita.ch2", "bookID": "gita", "title": "Chapter 2", "sequence": 2},
        {"id": "bible.matthew.5", "bookID": "bible.matthew", "title": "Chapter 5", "sequence": 5},
        {"id": "quran.surah1", "bookID": "quran", "title": "Surah 1 · Al-Fatihah (The Opening)", "sequence": 1},
        {"id": "tanakh.psalms.23", "bookID": "tanakh.psalms", "title": "Psalm 23", "sequence": 23},
        {"id": "dhammapada.ch1", "bookID": "dhammapada", "title": "Chapter 1 · Yamakavagga (Pairs)", "sequence": 1},
        {"id": "ggs.ang1", "bookID": "ggs.japji", "title": "Ang 1", "sequence": 1},
    ],
    "themes": [{"id": k, "name": v[0]} for k, v in THEMES.items()],
    "passages": passages,
}
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(library, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"wrote {len(passages)} passages, {len(translations)} translations, {len(sources)} sources -> {OUT}")
