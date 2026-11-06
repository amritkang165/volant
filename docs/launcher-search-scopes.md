# Launcher search scopes

Contacts, Files and Clipboard can be searched on their own the way Raycast does it, by name, as well
as through the typed shortcuts `@`, `/` and `clip`. This is the first piece of the onboarding work:
the shortcuts were not discoverable, and the Welcome flow will point at these commands.

## Behavior

- **Command rows.** Typing `contacts` or `people`, `files` or `file`, or `clipboard` or
  `clipboard history` puts Search Contacts, Search Files or Search Clipboard first. The empty
  launcher's Commands list includes all three.
- **Entering.** Return or Tab on one of those rows enters the scope. The search field clears, a Back
  chip names the scope, and the placeholder says what to type. Tab elsewhere still opens AI Chat.
- **Searching.** Inside a scope every keystroke searches only that source, through the same typed
  shortcut (`@term`, `/term`, `clip term`), so both ways in return the same results. No other source
  sees the text: `define x` inside Contacts searches contacts for "define x".
- **Leaving.** Escape clears typed text first, then leaves; Delete in an empty field leaves; the Back
  chip leaves. These match list extensions, which share the same `LauncherScope` state.
- **In one go.** `contacts jane`, `people jane`, `files report`, `clipboard invoice` and
  `clipboard history invoice` search at once without entering the scope.
- **Unchanged.** `@name`, `/term` and `clip term` work as before. Bare `clip` still lists clipboard
  history directly, so Return there keeps pasting the newest item; singular `file` followed by a term
  stays an ordinary search, so app names such as "File Merge" still match.

## Privacy

Contacts asks for access only when a name is typed in the Contacts scope or after `@`, never on
entering the scope. Files and Clipboard behave exactly as their shortcuts do; nothing new is read,
stored or logged.

## Implementation

`SearchScope` in VolantCore holds the words, the one-go parsing and each scope's typed shortcut.
`LauncherModel.scope` is a `LauncherScope` (a list extension or a built-in source); `routedQuery`
maps a built-in scope or a one-go query to its shortcut, and `searchSingleSource` runs the `/`, `@`
and `clip` searches for both. `contacts`, `people`, `files`, `file` and `clipboard` are reserved in
`LauncherRouting`, so aliases, quicklinks and snippets cannot take them.

## Evidence and limits

- `SearchScopeTests` (Core): words, one-go parsing, shortcut routing, reserved words.
- `LauncherSearchScopeTests` (app): command rows first, Return and Tab entry, Contacts asking nothing
  until typed, typing searching one source, Escape and empty Back, one-go queries, the unchanged
  shortcuts. Contact and file search are recorders; no host prompts or searches the Mac.
- Native Actions fixture `search-scopes`: the three scopes entered with real Return and Tab key
  events, Escape and Delete, fictional contacts, files and clips, rendered light and dark at every
  launcher size in Tart.
- Not verified: the real Contacts permission prompt from the scope in the signed app. Live
  Spotlight results inside the Files scope found nothing in Volant Dev because the sandboxed query
  could not see the owner's files; the query now runs in the agent helper (see
  [file search](file-search.md)).
- An existing alias, quicklink or snippet named `contacts`, `people`, `files`, `file` or `clipboard`
  is now refused when edited, like other reserved words.
