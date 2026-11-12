# SACRED WISDOM

## Claude Code -- Native iOS Implementation Specification

**Platform:** iOS\
**Language:** Swift 6\
**UI:** SwiftUI\
**Architecture:** MVVM + Clean Architecture + Dependency Injection\
**Persistence:** SQLite + FTS5 + SwiftData\
**Voice:** Apple App Intents + Speech Framework\
**AI:** Apple Foundation Models where supported + optional remote AI\
**Minimum iOS:** iOS 17, with newer capabilities availability-gated\
**Project Type:** Offline-first, native iOS application

------------------------------------------------------------------------

# 1. PRODUCT VISION

Build a modern iOS application that provides a unified library of sacred
books from six major religious traditions.

Users should be able to:

1.  Browse holy books from different religions.
2.  Read original scripture and translations.
3.  Search across all religious books simultaneously.
4.  Ask spiritual questions using natural language.
5.  Discover related passages from different religions.
6.  Use Siri to ask questions and open relevant passages.
7.  Download scripture collections for offline access.
8.  Bookmark verses and maintain personal reading history.
9.  Listen to scripture passages where audio is available.
10. Understand the historical and spiritual context of passages.

## Core product philosophy

The application must remain neutral and respectful toward every
religion.

Scripture must always be retrieved from verified source content.
AI-generated explanations must be clearly identified as AI-generated and
never presented as authentic scripture.

------------------------------------------------------------------------

# 2. RELIGIOUS COLLECTIONS

Create an extensible content system supporting:

  -----------------------------------------------------------------------
  Religion                Collection              Organization
  ----------------------- ----------------------- -----------------------
  Hinduism                Bhagavad Gita           18 chapters and verses

  Christianity            Bible                   Old and New Testament,
                                                  books, chapters and
                                                  verses

  Islam                   Quran                   114 Surahs and Ayahs

  Judaism                 Tanakh                  Torah, Nevi'im and
                                                  Ketuvim

  Buddhism                Tripitaka and Sutras    Collections, texts and
                                                  passages

  Sikhism                 Guru Granth Sahib       Angs, hymns and
                                                  passages
  -----------------------------------------------------------------------

## Content strategy

Do not embed the complete scripture content directly in Swift source
files.

Use a content manifest and separate scripture database packages.

For every passage, preserve:

-   Stable passage ID.
-   Religion ID.
-   Collection ID.
-   Book or text ID.
-   Chapter, section or structural reference.
-   Original language.
-   Original text, if available.
-   Translation.
-   Translator and translation name.
-   Source attribution.
-   License information.

Important: Different traditions have different structural conventions.
Use a flexible hierarchy instead of assuming every text follows a
book/chapter/verse structure.

Start with verified sample content for all six traditions. Expand to
complete collections only when appropriate content and redistribution
permissions have been verified.

------------------------------------------------------------------------

# 3. APPLICATION ARCHITECTURE

Use Clean Architecture with MVVM.

## Architecture layers

**Presentation** - SwiftUI Views - ViewModels - Reusable UI components -
Navigation

**Domain** - Entities - Repository protocols - Use cases - Business
rules

**Data** - SQLite scripture database - SwiftData user data - Local
repositories - Remote repositories - Content import and download

**Services** - Search service - AI service - Siri/App Intents service -
Speech service - Audio service - Download manager

## Architecture requirements

-   Use dependency injection.
-   Use protocols for services and repositories.
-   Use async/await.
-   Use actors for shared mutable asynchronous state.
-   Use structured concurrency.
-   Avoid unnecessary singletons.
-   Keep SwiftUI views lightweight.
-   Keep business logic outside views.
-   Avoid force unwraps.
-   Use typed errors.
-   Support test dependency injection.

------------------------------------------------------------------------

# 4. XCODE PROJECT STRUCTURE

Create the following structure:

``` text
SacredWisdom/
├── App/
│   ├── SacredWisdomApp.swift
│   ├── AppCoordinator.swift
│   ├── AppDependencies.swift
│   └── AppConfiguration.swift
├── Core/
│   ├── DesignSystem/
│   │   ├── Colors/
│   │   ├── Typography/
│   │   ├── Components/
│   │   └── Theme/
│   ├── Extensions/
│   ├── Utilities/
│   ├── Constants/
│   └── Errors/
├── Domain/
│   ├── Entities/
│   ├── Repositories/
│   └── UseCases/
├── Data/
│   ├── Database/
│   │   ├── SQLite/
│   │   ├── FTS5/
│   │   └── DatabaseManager.swift
│   ├── SwiftData/
│   │   ├── Models/
│   │   └── PersistenceManager.swift
│   ├── Repositories/
│   ├── DTOs/
│   └── ContentImport/
├── Features/
│   ├── Home/
│   ├── ReligionLibrary/
│   ├── ScriptureReader/
│   ├── UniversalSearch/
│   ├── VerseDetails/
│   ├── AskQuestion/
│   ├── Favorites/
│   ├── ReadingHistory/
│   ├── Downloads/
│   └── Settings/
├── Services/
│   ├── Search/
│   ├── AI/
│   ├── Siri/
│   ├── Speech/
│   ├── Audio/
│   └── Download/
├── AppIntents/
│   ├── SearchScriptureIntent.swift
│   ├── AskQuestionIntent.swift
│   ├── OpenPassageIntent.swift
│   ├── DailyVerseIntent.swift
│   └── SacredWisdomShortcuts.swift
├── Resources/
│   ├── Assets.xcassets/
│   ├── Database/
│   ├── ContentManifest/
│   └── Localizations/
└── Tests/
    ├── UnitTests/
    ├── IntegrationTests/
    └── UITests/
```

------------------------------------------------------------------------

# 5. UI DESIGN SPECIFICATION

Use the previously generated Sacred Wisdom design as the visual
reference.

## Design language

-   Background: warm ivory and subtle gradients.
-   Primary color: deep purple.
-   Secondary color: gold.
-   Cards: rounded corners.
-   Typography: elegant headings and highly readable body text.
-   Icons: consistent SF Symbols where appropriate.
-   Support Light and Dark Mode.
-   Ensure all six traditions receive equal visual prominence.

## Bottom navigation

Implement five tabs:

1.  Home
2.  Search
3.  Favorites
4.  Library
5.  Settings

## Screen 1: Splash Screen

Display: - Sacred Wisdom logo. - App name. - Tagline: Timeless
Teachings, One Journey.

## Screen 2: Home Dashboard

Display: - Welcome message. - Universal search bar. - Six religious
collection cards. - Daily scripture passage. - Ask with Siri / Ask a
Question. - Recently viewed passages. - Downloaded collections
indicator.

## Screen 3: Religion Library

Display: - Religion title. - Scripture collection. - Collection
description. - Available languages. - Download status. - Browse action.

## Screen 4: Scripture Reader

Display: - Collection title. - Chapter/section heading. - Original
text. - English translation. - Passage reference. - Previous and next
passage controls. - Font size controls. - Bookmark action. - Share
action.

## Screen 5: Universal Search

Display: - Search field. - Voice search button. - Recent queries. -
Suggested spiritual questions. - Religion filters. - Translation
filters.

## Screen 6: Search Results

Each result should display: - Religion. - Scripture collection. -
Passage reference. - Short preview. - Translation. - Bookmark action. -
Navigation indicator.

Results should be visually grouped by religion.

## Screen 7: Verse Details

Display: - Scripture title. - Exact passage reference. - Original
text. - Translation. - Translation attribution. - Explanation/context. -
Related passages from other traditions. - Audio playback. - Share and
bookmark.

## Screen 8: Ask a Question

Create a conversational question interface.

Example:

User: What do different religions say about forgiveness?

Response: - Relevant Bhagavad Gita passages. - Relevant Bible
passages. - Relevant Quran passages. - Relevant Tanakh passages. -
Relevant Buddhist passages. - Relevant Sikh passages.

Show passage previews with a View Full Passage action.

## Screen 9: Favorites

Display: - Saved passages. - Custom collections. - Notes. - Search saved
passages. - Remove bookmark.

## Screen 10: Settings

Include: - Preferred language. - Preferred translation. - Appearance. -
Font size. - Offline content management. - AI settings. - Privacy. -
About and attribution.

------------------------------------------------------------------------

# 6. DATABASE DESIGN

Use two persistence systems for different responsibilities.

## A. SQLite + FTS5

Use SQLite for scripture content because it is optimized for large
read-heavy datasets and full-text indexing.

Suggested tables:

**religions** - id - name - description - icon_name

**scripture_collections** - id - religion_id - name - language -
version - license_id

**scripture_books** - id - collection_id - title - sequence_number

**scripture_sections** - id - book_id - title - sequence_number

**scripture_passages** - id - collection_id - book_id - section_id -
reference - original_text - translated_text - translation_id -
sequence_number

**translations** - id - name - language_code - translator - publisher -
attribution - license_id

**content_sources** - id - source_name - source_url - license -
attribution_text

Create an FTS5 virtual table to index searchable passage content.

Index: - Original text. - Translated text. - Book title. - Section
title. - Passage reference.

Use stable IDs for all scripture content.

## B. SwiftData

Use SwiftData for user-specific data.

Models:

**UserBookmark** - id - passageID - createdAt - note -
customCollectionID

**UserCollection** - id - name - createdAt

**ReadingHistory** - id - passageID - viewedAt

**SearchHistory** - id - query - searchedAt

**UserPreferences** - preferredLanguage - preferredTranslation - theme -
fontSize - offlinePreferences

Keep scripture data independent from user-generated data.

------------------------------------------------------------------------

# 7. UNIVERSAL SEARCH ENGINE

This is the core functionality of Sacred Wisdom.

Create:

``` swift
protocol ScriptureSearchRepository {
    func search(
        query: String,
        filters: SearchFilters
    ) async throws -> [ScriptureSearchResult]
}
```

Implement: - LocalKeywordSearchRepository - SemanticSearchRepository -
CombinedSearchRepository

## Search functionality

1.  Exact phrase search.
2.  Keyword search.
3.  Multiple keyword search.
4.  Religion filters.
5.  Collection filters.
6.  Language filters.
7.  Relevance ranking.
8.  Search suggestions.
9.  Recent searches.
10. Related passage discovery.

## Search processing

``` text
User Query
    |
    v
Query Normalization
    |
    v
Identify Search Mode
    |
    +-------------------+
    |                   |
    v                   v
Keyword Search     Semantic Search
    |                   |
    +---------+---------+
              |
              v
       Merge Results
              |
              v
       Rank and Filter
              |
              v
       Search Results
              |
              v
        Verse Details
```

Start with SQLite FTS5.

Semantic search should be optional and must not prevent local keyword
search from working.

------------------------------------------------------------------------

# 8. AI QUESTION ASSISTANT

Implement AI as a separate service.

``` swift
protocol ScriptureAIService {
    func answer(
        question: String,
        passages: [ScripturePassage]
    ) async throws -> ScriptureAIResponse
}
```

## AI workflow

1.  Receive question.
2.  Understand the user's intent.
3.  Retrieve relevant scripture passages.
4.  Pass verified passages into the AI context.
5.  Generate a neutral explanation.
6.  Return source references.
7.  Display passages separately from the generated explanation.

## AI implementation options

**Option 1: Apple Foundation Models** - Use Apple's on-device Foundation
Models framework where available. - Check device and model
availability. - Use availability checks. - Provide a non-AI fallback. -
No external AI API key required.

**Option 2: Optional online provider**

Define an abstraction for future OpenRouter or other provider
integration.

Do not make remote AI mandatory.

## AI safety and accuracy

-   AI must never invent scripture.
-   Only database passages may be displayed as quotations.
-   Every quotation must link to its source.
-   Clearly label AI-generated explanations.
-   Do not present theological interpretations as universal facts.
-   Allow users to inspect the original passage.
-   Avoid unsupported comparisons between religions.

------------------------------------------------------------------------

# 9. SIRI AND APP INTENTS

Use Apple's App Intents framework.

Do not build a custom SiriKit integration for functionality already
supported through App Intents.

## Required intents

**SearchScriptureIntent** - Accepts a search query. - Searches local
scripture. - Returns relevant references.

**AskQuestionIntent** - Accepts a spiritual question. - Retrieves
relevant passages. - Returns a concise response.

**OpenPassageIntent** - Accepts a passage identifier. - Opens the
relevant passage.

**DailyVerseIntent** - Returns the daily selected passage.

## App Shortcuts

Create shortcuts such as: - Ask Sacred Wisdom. - Search Holy Books. -
Open Daily Scripture. - Find Verses About Peace.

## Voice interaction example

User:

"Hey Siri, ask Sacred Wisdom about forgiveness."

App:

Returns relevant passages from different traditions.

Where an interactive result is required, open the application and
navigate to the search results.

Also implement optional in-app speech-to-text using Apple's Speech
framework. Keep in-app speech recognition separate from Siri invocation.

------------------------------------------------------------------------

# 10. OFFLINE CONTENT MANAGEMENT

Create a DownloadManager.

Responsibilities: - Download scripture packages. - Track download
progress. - Pause and resume where supported. - Validate content
integrity. - Import content into local SQLite storage. - Handle failed
downloads. - Remove downloaded packages. - Display storage consumption.

## Content manifest

Each package should include: - Collection identifier. - Version. -
Language. - File size. - Source. - License. - Checksum. - Schema
version.

## Offline requirements

The application must support: - Reading downloaded content. - Keyword
search. - Favorites. - Reading history. - Previously downloaded
passages.

Core reading and search must never depend on internet access.

------------------------------------------------------------------------

# 11. AUDIO SUPPORT

Implement an AudioService abstraction.

Support: - Licensed prerecorded scripture audio. - System text-to-speech
using AVSpeechSynthesizer. - Play and pause. - Playback speed. -
Language selection. - Audio progress.

Do not generate audio for copyrighted translations without appropriate
permissions.

------------------------------------------------------------------------

# 12. DEVELOPMENT PHASES

Claude must implement one phase at a time.

## PHASE 1 -- Project Setup and Design System

Tasks: - Create Xcode project. - Configure Swift 6. - Create project
folder structure. - Implement application entry point. - Create
dependency container. - Create theme and design system. - Create
reusable components. - Implement bottom navigation. - Build home
dashboard. - Add six sample religious cards. - Add mock repository.

Acceptance criteria: - Project builds. - Home screen renders
correctly. - Navigation works. - Components are reusable. - No business
logic exists inside views.

## PHASE 2 -- Scripture Library

Tasks: - Implement religion entities. - Implement scripture collection
models. - Implement collection browsing. - Implement reader screen. -
Add sample passages for all six traditions. - Add translation
selection. - Add next/previous passage navigation.

Acceptance criteria: - All six traditions can be browsed. - Passages
display correct references. - Reader works with local sample data. -
Original and translated text are distinguishable.

## PHASE 3 -- Local Database

Tasks: - Integrate SQLite. - Implement database schema. - Implement
database migrations. - Create content import mechanism. - Implement
FTS5. - Add database repository. - Implement sample verified datasets.

Acceptance criteria: - Database initializes successfully. - Content can
be queried. - Search works offline. - Stable passage identifiers are
maintained.

## PHASE 4 -- Universal Search

Tasks: - Create search repository. - Implement query normalization. -
Implement FTS5 search. - Implement filters. - Implement result
ranking. - Build search UI. - Build search result cards. - Implement
search history.

Acceptance criteria: - A single query searches all six collections. -
Results show accurate references. - Filters work. - Search works in
airplane mode.

## PHASE 5 -- Verse Details and Favorites

Tasks: - Build passage detail screen. - Display original and translated
text. - Add attribution. - Implement related passage navigation. -
Implement bookmarks. - Implement personal notes. - Implement reading
history. - Implement sharing.

Acceptance criteria: - Search results open correct passages. - Bookmarks
persist after app restart. - Related passages open their own details. -
User notes persist.

## PHASE 6 -- Siri and Speech

Tasks: - Implement App Intents. - Create App Shortcuts. - Implement
scripture search intent. - Implement question intent. - Implement
open-passage intent. - Add speech-to-text. - Test Siri interactions.

Acceptance criteria: - Siri can invoke supported intents. - Search
results are returned correctly. - The app opens relevant passages when
required. - In-app voice input works independently.

## PHASE 7 -- AI Question Assistant

Tasks: - Create AI service protocol. - Implement retrieval-based
context. - Integrate Foundation Models where available. - Implement
optional remote AI provider abstraction. - Validate source references. -
Display AI explanations separately. - Add fallback behavior.

Acceptance criteria: - AI responses cite retrieved passages. - No
fabricated quotations are displayed. - AI is optional. - Local search
remains available without AI.

## PHASE 8 -- Offline Downloads

Tasks: - Create content manifest. - Implement package download. - Add
download progress. - Implement checksum validation. - Add package
import. - Implement deletion and storage management. - Test offline
reading.

Acceptance criteria: - Users can download a scripture collection. -
Downloaded collections work without internet. - Invalid packages are
rejected. - Storage is managed correctly.

## PHASE 9 -- Final Polish and Release

Tasks: - Implement accessibility. - Add Dynamic Type. - Add Dark Mode. -
Add Arabic and Hebrew RTL support. - Optimize search. - Improve error
handling. - Add loading states. - Add performance testing. - Complete UI
automation. - Prepare App Store assets.

Acceptance criteria: - All primary workflows function. - Unit and UI
tests pass. - No critical accessibility issues. - App builds for release
configuration.

------------------------------------------------------------------------

# 13. TESTING REQUIREMENTS

Use XCTest and Swift Testing where appropriate.

## Unit tests

-   Religion repository.
-   Scripture repository.
-   SQLite queries.
-   FTS5 ranking.
-   Search filters.
-   Passage navigation.
-   Bookmark persistence.
-   Reading history.
-   Download validation.
-   AI source validation.

## Integration tests

-   Database initialization.
-   Content import.
-   Search across six traditions.
-   Offline transitions.
-   App Intents.
-   Download management.
-   SwiftData persistence.

## UI tests

-   Home screen navigation.
-   Religion collection selection.
-   Search query.
-   Result selection.
-   Verse details.
-   Bookmark creation.
-   Settings changes.
-   Offline reading.

## Test data

Maintain a separate test database containing verified passages and their
expected references.

Never use fabricated test quotations as evidence of real scripture.

------------------------------------------------------------------------

# 14. CLAUDE CODE DEVELOPMENT RULES

Follow these rules throughout the project.

1.  Never implement every phase in a single response.
2.  Analyze the repository before creating or modifying files.
3.  Preserve existing working code.
4.  Follow Swift 6 concurrency safety.
5.  Use async/await for asynchronous operations.
6.  Use actors for shared mutable state where appropriate.
7.  Use dependency injection.
8.  Avoid massive ViewModels.
9.  Avoid massive SwiftUI views.
10. Use reusable components.
11. Never hardcode scripture content inside views.
12. Never fabricate scripture references.
13. Respect translation licenses.
14. Support offline functionality.
15. Handle all loading, empty and error states.
16. Include accessibility identifiers for UI testing.
17. Write unit tests for business logic.
18. Build after every major implementation step.
19. Fix compiler warnings and errors before proceeding.
20. Document architectural decisions.

------------------------------------------------------------------------

# 15. CLAUDE CODE EXECUTION PROMPT

Use the following prompt after placing this document in the project root
as `IMPLEMENTATION_PLAN.md`.

## BEGIN PROMPT

You are the senior iOS architect and SwiftUI engineer responsible for
implementing Sacred Wisdom.

Read `IMPLEMENTATION_PLAN.md` completely before writing code.

Your responsibilities:

1.  Understand the complete application architecture.
2.  Inspect the current Xcode project.
3.  Identify existing implementations before creating new files.
4.  Follow the defined folder structure and design system.
5.  Use Swift 6 and modern SwiftUI APIs.
6.  Implement features with clean architecture and MVVM.
7.  Write testable, modular code.
8.  Use mock repositories until real scripture datasets are available.
9.  Never fabricate scripture content.
10. Ensure all features have proper loading, empty and error states.

### Execution strategy

Start with Phase 1 only.

Before coding: - Explain the architecture. - List the files you intend
to create. - Identify required frameworks. - Identify any Xcode
configuration changes.

Then implement Phase 1.

After implementation: - Run an iOS Simulator build. - Resolve all
compilation errors. - Run available unit tests. - Provide a summary of
created files. - Explain what is working. - List remaining tasks.

Do not automatically proceed to Phase 2.

Wait for explicit approval before implementing the next phase.

For every subsequent phase: - Review existing code. - Implement only the
requested phase. - Preserve existing architecture. - Add relevant
tests. - Build and validate. - Report completion.

## END PROMPT

------------------------------------------------------------------------

# 16. INITIAL MVP PRIORITY

The first usable version should focus on these features:

  Priority   Feature
  ---------- ---------------------------
  P0         Home dashboard
  P0         Six religious collections
  P0         Scripture reader
  P0         Local SQLite database
  P0         Universal keyword search
  P0         Verse details
  P1         Favorites
  P1         Reading history
  P1         Siri/App Intents
  P1         Offline downloads
  P2         AI question assistant
  P2         Semantic search
  P2         Audio and text-to-speech

## Final product goal

Deliver an elegant, reliable and offline-first iOS application that lets
people explore sacred teachings across different religions.

The experience should make it easy to ask a question, discover authentic
passages, understand their context and explore related teachings without
requiring users to navigate six separate applications.
