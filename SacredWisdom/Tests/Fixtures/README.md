Test fixtures (not shipped in the app).

`tampered-packages/` holds the Dhammapada chapter package with one word changed ("hatred" → "HATRED", same
length), listed under the *original* checksum. Downloads from it must be rejected by checksum validation.
Regenerate after rebuilding `content/packages` with the snippet in the Phase 8 notes in docs/ARCHITECTURE.md.
