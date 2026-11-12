import Foundation

/// Resolves a `SampleLibraryDTO` into validated domain entities with lookup indexes.
/// Any dangling reference makes the whole library invalid; nothing partial is shown.
struct SampleLibraryIndex: Sendable {
    let religions: [Religion]
    let collections: [ScriptureCollection]
    let collectionsByID: [String: ScriptureCollection]
    let translationsByCollection: [String: [Translation]]
    let booksByID: [String: ScriptureBook]
    let booksByCollection: [String: [ScriptureBook]]
    let sectionsByID: [String: ScriptureSection]
    let sectionsByBook: [String: [ScriptureSection]]
    let passagesByID: [String: ScripturePassage]
    let passagesBySection: [String: [ScripturePassage]]
    /// Passage IDs per collection in reading order (book, section, passage sequence).
    let readingOrder: [String: [String]]
    /// Position of each passage ID within its collection's `readingOrder`.
    let readingPosition: [String: Int]
    /// Editorial themes, in package order.
    let themes: [PassageTheme]
    /// Theme IDs per passage, in package order.
    let themeIDsByPassage: [String: [String]]

    init(_ dto: SampleLibraryDTO) throws(AppError) {
        func corrupt(_ message: String) -> AppError { .contentCorrupted(message) }

        var sources: [String: ContentSource] = [:]
        for s in dto.sources {
            sources[s.id] = ContentSource(id: s.id, name: s.name, url: s.url.flatMap(URL.init(string:)),
                                          license: s.license, attribution: s.attribution)
        }

        let religionIDs = Set(dto.religions.map(\.id))
        var collectionsByID: [String: ScriptureCollection] = [:]
        var collections: [ScriptureCollection] = []
        for c in dto.collections {
            guard religionIDs.contains(c.religionID) else { throw corrupt("Collection \(c.id): unknown religion") }
            var original: ContentSource?
            if let sourceID = c.originalSourceID {
                guard let source = sources[sourceID] else { throw corrupt("Collection \(c.id): unknown source") }
                original = source
            }
            let collection = ScriptureCollection(
                id: c.id, religionID: c.religionID, name: c.name, structureDescription: c.structureDescription,
                languages: c.languages, availability: c.availability, originalLanguage: c.originalLanguage,
                originalSource: original, defaultTranslationID: c.defaultTranslationID
            )
            collectionsByID[c.id] = collection
            collections.append(collection)
        }

        var translationsByID: [String: Translation] = [:]
        var translationsByCollection: [String: [Translation]] = [:]
        for t in dto.translations {
            guard collectionsByID[t.collectionID] != nil else { throw corrupt("Translation \(t.id): unknown collection") }
            guard let source = sources[t.sourceID] else { throw corrupt("Translation \(t.id): unknown source") }
            let translation = Translation(id: t.id, collectionID: t.collectionID, name: t.name, languageCode: t.languageCode,
                                          translator: t.translator, year: t.year, source: source)
            translationsByID[t.id] = translation
            translationsByCollection[t.collectionID, default: []].append(translation)
        }
        for c in collections {
            guard translationsByID[c.defaultTranslationID]?.collectionID == c.id else {
                throw corrupt("Collection \(c.id): default translation missing")
            }
        }

        var booksByID: [String: ScriptureBook] = [:]
        for b in dto.books {
            guard collectionsByID[b.collectionID] != nil else { throw corrupt("Book \(b.id): unknown collection") }
            booksByID[b.id] = ScriptureBook(id: b.id, collectionID: b.collectionID, title: b.title,
                                            division: b.division, sequence: b.sequence)
        }

        var sectionsByID: [String: ScriptureSection] = [:]
        for s in dto.sections {
            guard let book = booksByID[s.bookID] else { throw corrupt("Section \(s.id): unknown book") }
            sectionsByID[s.id] = ScriptureSection(id: s.id, bookID: s.bookID, collectionID: book.collectionID,
                                                  title: s.title, sequence: s.sequence)
        }

        var passagesByID: [String: ScripturePassage] = [:]
        for p in dto.passages {
            guard passagesByID[p.id] == nil else { throw corrupt("Duplicate passage ID \(p.id)") }
            guard let section = sectionsByID[p.sectionID], let book = booksByID[section.bookID],
                  let collection = collectionsByID[book.collectionID] else {
                throw corrupt("Passage \(p.id): unknown section")
            }
            var texts: [PassageText] = []
            for (translationID, text) in p.texts {
                guard let translation = translationsByID[translationID], translation.collectionID == collection.id else {
                    throw corrupt("Passage \(p.id): unknown translation \(translationID)")
                }
                texts.append(PassageText(translation: translation, text: text))
            }
            guard !texts.isEmpty else { throw corrupt("Passage \(p.id): no translation text") }
            let order = translationsByCollection[collection.id]?.map(\.id) ?? []
            texts.sort { lhs, rhs in
                let l = lhs.translation.id == collection.defaultTranslationID ? -1 : (order.firstIndex(of: lhs.translation.id) ?? .max)
                let r = rhs.translation.id == collection.defaultTranslationID ? -1 : (order.firstIndex(of: rhs.translation.id) ?? .max)
                return l < r
            }
            passagesByID[p.id] = ScripturePassage(
                id: p.id, religionID: collection.religionID, collectionID: collection.id, bookID: book.id,
                sectionID: section.id, sequence: p.sequence, reference: p.reference,
                originalLanguage: collection.originalLanguage, originalText: p.originalText,
                originalSource: collection.originalSource, texts: texts
            )
        }

        let themes = (dto.themes ?? []).map { PassageTheme(id: $0.id, name: $0.name) }
        let themeIDs = Set(themes.map(\.id))
        guard themeIDs.count == themes.count else { throw corrupt("Duplicate theme ID") }
        var themeIDsByPassage: [String: [String]] = [:]
        for p in dto.passages {
            for themeID in p.themes ?? [] {
                guard themeIDs.contains(themeID) else { throw corrupt("Passage \(p.id): unknown theme \(themeID)") }
                if themeIDsByPassage[p.id]?.contains(themeID) != true { themeIDsByPassage[p.id, default: []].append(themeID) }
            }
        }

        let booksByCollection = Dictionary(grouping: booksByID.values, by: \.collectionID)
            .mapValues { $0.sorted { $0.sequence < $1.sequence } }
        let sectionsByBook = Dictionary(grouping: sectionsByID.values, by: \.bookID)
            .mapValues { $0.sorted { $0.sequence < $1.sequence } }
        let passagesBySection = Dictionary(grouping: passagesByID.values, by: \.sectionID)
            .mapValues { $0.sorted { $0.sequence < $1.sequence } }

        var readingOrder: [String: [String]] = [:]
        var readingPosition: [String: Int] = [:]
        for collection in collections {
            var ids: [String] = []
            for book in booksByCollection[collection.id] ?? [] {
                for section in sectionsByBook[book.id] ?? [] {
                    ids += (passagesBySection[section.id] ?? []).map(\.id)
                }
            }
            for (position, id) in ids.enumerated() { readingPosition[id] = position }
            readingOrder[collection.id] = ids
        }

        self.religions = dto.religions.sorted { $0.sortOrder < $1.sortOrder }
        self.collections = collections
        self.collectionsByID = collectionsByID
        self.translationsByCollection = translationsByCollection
        self.booksByID = booksByID
        self.booksByCollection = booksByCollection
        self.sectionsByID = sectionsByID
        self.sectionsByBook = sectionsByBook
        self.passagesByID = passagesByID
        self.passagesBySection = passagesBySection
        self.readingOrder = readingOrder
        self.readingPosition = readingPosition
        self.themes = themes
        self.themeIDsByPassage = themeIDsByPassage
    }
}
