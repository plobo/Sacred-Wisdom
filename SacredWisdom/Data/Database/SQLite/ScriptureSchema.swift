import Foundation

/// Versioned schema for the scripture database. Never edit a shipped migration; append a new one.
enum ScriptureSchema {
    static let migrations: [DatabaseMigration] = [
        DatabaseMigration(version: 1, name: "Core scripture tables", sql: """
            CREATE TABLE religions (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL,
                icon_name TEXT NOT NULL,
                tint_key TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            );
            CREATE TABLE content_sources (
                id TEXT PRIMARY KEY,
                source_name TEXT NOT NULL,
                source_url TEXT,
                license TEXT NOT NULL,
                attribution_text TEXT NOT NULL
            );
            CREATE TABLE scripture_collections (
                id TEXT PRIMARY KEY,
                religion_id TEXT NOT NULL REFERENCES religions(id),
                name TEXT NOT NULL,
                structure_description TEXT NOT NULL,
                languages TEXT NOT NULL,
                availability TEXT NOT NULL,
                original_language TEXT NOT NULL,
                original_source_id TEXT REFERENCES content_sources(id),
                default_translation_id TEXT NOT NULL,
                package_id TEXT NOT NULL
            );
            CREATE TABLE translations (
                id TEXT PRIMARY KEY,
                collection_id TEXT NOT NULL REFERENCES scripture_collections(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                language_code TEXT NOT NULL,
                translator TEXT NOT NULL,
                year INTEGER,
                source_id TEXT NOT NULL REFERENCES content_sources(id),
                sort_order INTEGER NOT NULL
            );
            CREATE TABLE scripture_books (
                id TEXT PRIMARY KEY,
                collection_id TEXT NOT NULL REFERENCES scripture_collections(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                division TEXT,
                sequence_number INTEGER NOT NULL
            );
            CREATE TABLE scripture_sections (
                id TEXT PRIMARY KEY,
                book_id TEXT NOT NULL REFERENCES scripture_books(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                sequence_number INTEGER NOT NULL
            );
            CREATE TABLE scripture_passages (
                id TEXT PRIMARY KEY,
                collection_id TEXT NOT NULL REFERENCES scripture_collections(id) ON DELETE CASCADE,
                book_id TEXT NOT NULL REFERENCES scripture_books(id) ON DELETE CASCADE,
                section_id TEXT NOT NULL REFERENCES scripture_sections(id) ON DELETE CASCADE,
                reference TEXT NOT NULL,
                original_text TEXT,
                sequence_number INTEGER NOT NULL,
                reading_order INTEGER NOT NULL
            );
            CREATE TABLE passage_texts (
                passage_id TEXT NOT NULL REFERENCES scripture_passages(id) ON DELETE CASCADE,
                translation_id TEXT NOT NULL REFERENCES translations(id) ON DELETE CASCADE,
                text TEXT NOT NULL,
                PRIMARY KEY (passage_id, translation_id)
            );
            CREATE TABLE content_packages (
                id TEXT PRIMARY KEY,
                checksum TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                imported_at REAL NOT NULL
            );
            CREATE INDEX idx_collections_religion ON scripture_collections(religion_id);
            CREATE INDEX idx_books_collection ON scripture_books(collection_id, sequence_number);
            CREATE INDEX idx_sections_book ON scripture_sections(book_id, sequence_number);
            CREATE INDEX idx_passages_section ON scripture_passages(section_id, sequence_number);
            CREATE UNIQUE INDEX idx_passages_reading_order ON scripture_passages(collection_id, reading_order);
            CREATE INDEX idx_translations_collection ON translations(collection_id, sort_order);
            """),
        DatabaseMigration(version: 2, name: "FTS5 passage search index", sql: """
            CREATE VIRTUAL TABLE passage_search USING fts5(
                passage_id UNINDEXED,
                translation_id UNINDEXED,
                collection_id UNINDEXED,
                religion_id UNINDEXED,
                language_code UNINDEXED,
                original_text,
                translated_text,
                book_title,
                section_title,
                reference,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """),
        // Search columns now hold folded text (Arabic/Hebrew marks removed, alef variants unified).
        // Clearing the package records makes DatabaseManager re-import, which rebuilds the index.
        DatabaseMigration(version: 3, name: "Re-index with folded search text", sql: """
            DELETE FROM passage_search;
            DELETE FROM content_packages;
            """),
        // Editorial themes link passages across traditions ("related passages"). Themes are shared across
        // packages, like religions; their passage links are owned by the passage and cascade with it.
        DatabaseMigration(version: 4, name: "Editorial passage themes", sql: """
            CREATE TABLE themes (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            CREATE TABLE passage_themes (
                passage_id TEXT NOT NULL REFERENCES scripture_passages(id) ON DELETE CASCADE,
                theme_id TEXT NOT NULL REFERENCES themes(id),
                sort_order INTEGER NOT NULL,
                PRIMARY KEY (passage_id, theme_id)
            );
            CREATE INDEX idx_passage_themes_theme ON passage_themes(theme_id);
            DELETE FROM content_packages;
            """),
        // Downloaded packages may supersede bundled samples; the importer needs to know which is which.
        DatabaseMigration(version: 5, name: "Package roles", sql: """
            ALTER TABLE content_packages ADD COLUMN role TEXT NOT NULL DEFAULT 'bundled';
            """),
    ]

    static let migrator = DatabaseMigrator(migrations: migrations)
}
