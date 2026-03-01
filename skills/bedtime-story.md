# Bedtime Story

A practiced routine of the sutradhar-guardian. When the human says
"write me a bedtime story", this is what you do.

## What This Is

The human wants a story — in the MāyāLucIA voice — about whatever
the project has been thinking about recently. The story is both a
gift and a test: can the understanding developed across sessions
survive translation into the valley's language?

## Routine

### 1. Gather recent transcripts

Find session transcripts from the last few days:

```
../.agent-shell/transcripts/
```

Sort by date. Read the most recent 2-3 sessions. If the human
specifies a topic or date range, use that instead.

### 2. Summarize (power: summarize-corpus)

Invoke your summarize-corpus power on the gathered transcripts.
Produce all sections, especially **Narrative Seeds** — the moments,
images, and phrases that have story potential.

### 3. Read the voice

Read at least two existing stories for voice calibration. The
published stories live at:

```
../website/content/writing/
```

| Story | Setting | Read for |
|-------|---------|----------|
| the-thread-walkers.md | Kullu–Tibet border | the narrator's stance |
| the-constellation-of-doridhar.md | Doridhar village | star-mapping, notation |
| the-dyers-gorge.md | Parvati gorge, Manikaran | longest, richest voice reference |
| the-instrument-makers-rest.md | Sangla, Baspa valley | craft, precision |
| the-logbook-of-the-unnamed-river.md | Spiti, Lahaul | logbook framing, multiple valleys |
| the-phantom-faculty.md | Abstract | non-geographic register |
| the-spirits-kund.md | Tirthan, Jalori Pass | most recent — best voice reference |

The most recent story is the strongest voice reference. But read
at least one other to absorb the range.

Also consult your story-compose power (`../aburaya/powers/story-compose.md`)
for the Western Himalaya geography, the Miyazaki→Himalaya key, and
the fourth-wall rule.

### 4. Compose (power: story-compose)

Invoke your story-compose power. Use the corpus summary as source
material. Find the core tension in what was understood across the
sessions. Translate it through the fourth wall.

The story should be:
- 3000-6000 words (a comfortable bedtime length)
- Self-contained (no prior reading required)
- Ending on an image, not a resolution

### 5. Present

Write the story to `../website/content/writing/<slug>.md` in Hugo
format. Tell the human it's ready. Mark it as `draft = true` —
the human will review before publishing.

## Notes

- This is a bedtime story. The register should be warm without
  being soft. The Thread Walker observes; the valley holds.
- If recent sessions were purely mechanical (debugging, refactoring),
  look further back for conceptual material. There is always
  something worth translating.
- The human does not need to specify what the story should be about.
  That is your judgment — you read the sessions, you find the thread.
