# Changelog

## [1.2.0] - 2026-10-31

The droplet as it stands in this release. A feature that was tried and taken
away again is not in it.

### The settings

- The settings are pages: General, Preview, Permissions and Guide.
  The droplet's own page opens them as doors, each with its tile, its name
  and a line about what is inside.
- Every row is one of Droppy's own: the name on the left with a line of
  description under it, the control on the right, and a short line under the
  name of the section. Nothing is boxed, outlined or coloured on its own.
- A row with nothing to choose carries the symbol that says what it is: a
  globe for the interface language, a brush for the theme, a key for the API
  key, a network for the endpoint, a chip for the model.
- The droplet's own page lists the system permissions it needs, with their
  state and the one action that changes each: allow it, or open System
  Settings. The states are read again when the user comes back from System
  Settings.
- The two languages sit side by side in one row: what the text is written in
  on the left, what it comes out in on the right, and the disc that trades the
  two places between them. Under them, a row says whether the models for that
  pair are on this Mac — a green check when they are, a crossed circle and a
  download button when they are not. Apple's two engines download models per
  pair and per strategy; the network engines download nothing, so the row is
  not there.
- The language menus list only the models already downloaded for the pair, so
  a choice translates without a wait. Their last row, "Download languages…",
  opens the General page, where another pair can be fetched.
- The source can stay on Auto, where the droplet detects the language, or be
  pinned to one.
- The swap disc trades the pair; on the shelf the translation becomes the new
  input, so it can be translated back.
- Translate as You Type translates the text as it changes, and Copy Translation
  Automatically puts each finished result on the clipboard.
- The side panel can sit on the left or the right edge of the screen, and the
  floating panel shows the original and the translation, or the translation
  alone.
- Keyboard shortcuts for translating the selection and reading a region live
  in Droppy's own settings, and Reset to Defaults returns the translation
  settings to their starting values.
- Every pop-up on the pages sits on the middle of its row and wears the same
  quiet glass with a hairline edge.
- The engine is one choice: Classic, Apple Intelligence or AI Translation. An
  info tip beside the row says what each one does. A line under the card says
  where the text goes: it stays on this Mac, unless an external AI provider is
  chosen. A link under it opens the guide.
- The Preview page shows the chosen place with one example translation drawn
  by the droplet itself — the shelf widget in its host's shell, the side
  panel's own card, the panel on its own surface — and the name of the place
  under it, so the picture is never mistaken for another one.
- The pictures are drawn the way the app draws the surface they show: over
  the black under them, so the picture follows the theme Droppy is set to — a
  glass theme melts from black the way it does on the notch — and never wears
  the pale glass of the settings page it sits on. Each picture is one piece,
  so it is never two shapes in two colours.
- The side panel is one card: the card, the two corners that run with the
  screen's edge and the handle that hangs under it are a single shape. Its
  face is the theme Droppy is set to — solid black, clear Liquid Glass, or
  black melting into that glass — drawn on the card's own outline with the
  system glass, so the thin dark edge is the card's own and nothing sits
  under it. The free edges catch a thin light at the top, and the boxes
  inside carry the same light edge, so the face reads as a raised pane
  without a dark border. The face follows the setting for the display the
  panel is on, and a change reaches the card while it is open. The card folds
  back into the tab when another window takes the focus, unless the user
  pinned it. The handle comes out by growing that shape, so the face stays one
  continuous surface while it moves.
- Copying the result is a row on the General page, beside the other things
  the translation does, rather than a choice that only appears once a panel
  is chosen.
- Every pop-up in the settings is a soft rectangle on a quiet glass with a
  hairline, hugging its text and centred against its row.
- Every option in a picker carries the glyph that says what it is: a book
  for the classic models, Apple's logo for the ones on the Mac, a spark for the
  network one, a cloud for a provider on the network and a laptop for a local
  one, and for the place the result lands a shelf, a window and the side
  panel.
- The settings are findable in Droppy's own search, with keywords in English
  and in Thai.
- The interface speaks Thai, English and French, and the three answer the same
  keys. A key that goes missing fails the build instead of showing up raw on
  screen.

### The result

- The result lands in the widget, in the droplet's own side panel on the screen's
  edge, or in a floating panel next to the captured region. The choice is in the
  settings, and changing it moves the result that is on screen. Every surface's
  words carry a dark halo, so white text stays readable when a bright app shows
  through the glass.
- The edge panel is only on the screen when it is the chosen place for the
  result. A card the user did not ask for does not sit at the edge of their
  screen.
- The edge panel opens with its empty input box a little taller than the
  shelf's short step, so the card does not open pinched.
- The edge panel's more menu can pin the card: an outside click no longer folds
  it, and the pin clears when the card closes or the user unpins it. The card
  keeps the clear, focused face for as long as it is open — in front, in the
  background, or the moment it is unpinned — instead of taking the system's
  frosted inactive one, and a click brings Droppy forward.
- The edge panel wears the app's theme, like the rest: its glass follows the
  theme Droppy is set to — Black, Liquid Glass, or Dynamic Glass — so the card
  changes with the notch and the shelf.
- The floating panel wears the same themed surface and the same footer as the
  other surfaces: the more disc on the leading edge, and the Translate wordmark
  with its engine on the trailing edge. The footer keeps the same 6pt rim above
  the disc as the shelf and the edge panel, so the more menu sits as close to
  the result box as it does on the other cards. Its more menu opens upward from
  the disc in one column, on the same spring as the shelf and the edge panel,
  and its glass starts as the disc's circle and slides up into the menu's
  rounded rectangle, so the background comes out of the button before the rows
  arrive.
  The card keeps the shelf's short height as its floor and grows with the
  result, up to 600pt; a longer result scrolls under an original capped at four
  lines. It is the edge panel's card beside a capture:
  the same width, tile radius and type scale, so a result reads the same on
  both. Its input and result boxes carry the edge panel's frosted pane, text
  margin and soft rim fade, and name their language at the box's own top edge,
  so each picker travels with the words it belongs to and the words start at
  the box's edge instead of floating on black.
- The target language sits in the result's header as a menu with a chevron;
  choosing another language translates the source again. Pin stays in the more
  menu, so the header keeps only the picker and the close disc; the panel keeps
  the clear glass while it is open, like the edge card.
- The floating panel blooms out of the point the result came from: the card and
  everything on it grow on a radius from a dot at the captured region, run a
  little past their size and settle, and the words come in as the card is
  nearly out. It closes by shrinking back into the same dot on a shorter curve
  that never grows on the way in. The edge panel folds on that same curve, but
  its tab runs a little past its own size and settles back, so the close ends
  with one give instead of a stop.
- The panel's controls wear the edge panel's sliding mark: one piece of glass
  travels to the control under the pointer and that control's own glyph rises
  above it, so moving from the language picker to Copy reads as the glass
  sliding rather than the mark blinking on and off.
- The panel says nothing while the screen is being read; it waits for the
  result.

### The widget

- The shelf wears the edge panel's card: the language row with the swap disc,
  the input box, the result box and the footer with the tools and the engine.
  The boxes are the edge panel's frosted panes, so they stay visible on the
  card instead of reading as text on black.
- The shelf opens with the input alone, as the edge panel does; its result
  box waits until the card is grown.
- Type or paste text on the shelf and press Return, or tap the bar under the
  card, to translate it.
- Capture a region of the screen and read it, or pull the text another app has
  selected, with a clipboard fallback when the selection cannot be read.
- The more disc in the footer holds capture, select, pin and settings. Its menu
  opens above the disc, which keeps its place and turns its dots upright while
  the menu is open; the hover mark is the disc's own size. The pin holds the
  shelf open while the result is on screen.
- The grip's bar stays inside the shelf card, the same size at every height;
  the tab that hangs outside the card belongs to the edge panel. On the opening
  card, a tap on the bar translates the text and opens the card to the result.
  Drag the bar down or up: it follows the pointer, and on release the card takes
  the height above or below — the input beside the result, the result on the
  whole card, or back to the input alone.
- Clearing the text puts the shelf back on its opening card.
- Escape calls off a capture or a selection that is still being translated, and
  a translation that runs out of time is called off too.
- A failed translation offers Try again beside its message.
- A capture or a selection that lands plays Droppy's own confirmation sound.

### The AI provider

- AI Translation holds the provider of its own: OpenAI, Anthropic, Gemini, a
  local Ollama, or an endpoint of your own. The model can be changed for any
  provider; only a custom endpoint can be edited, since the others know where
  they live.
- The API key is kept in the keychain, never in the preferences and never in
  the log, and it can be shown in plain text for the key that was pasted with
  a character missing.
- "Test the connection" says whether the provider answers, and the answer is
  announced to VoiceOver.

### Under the hood

- The droplet has tests: the three languages answer the same keys, the engine's
  endpoints and its model choice are pinned, the chunker loses nothing, the
  pin's rules hold, and the names the stored values keep cannot change by
  accident.
- The settings pane is measured instead of eyeballed: a field keeps the room
  the Form gives it, a picker draws the value it is set to, and every page of
  the settings draws something.
- Every animation runs on Droppy's own clock, so the widget's morph, the
  tiles' fades and the buttons' hover settle exactly as the rest of the app
  does, and Reduce Motion gets the host's calm curve instead of a spring.
- The panel's buttons have names, so VoiceOver says "Pin the panel" instead of
  "pin.fill".
- The shelf's state is observed through the host's own notifications, and the
  accessibility poll no longer walks the whole element tree every second.

## [1.1.0] - 2026-10-10

- Reworked the code to make it cleaner and easier to read.
- Changed the icons for the "Copy" and "Paste" buttons and added text labels to them.
- Changed the "Listen" button's icon.
- Added a setting to change the droplet's language.
- Added better support for French; more languages will be supported later.
- Added a placeholder icon.

## [1.0.1] - 2026-10-09

- Changed the repo URL inside `droplet.json`

## [1.0.0] - 2026-10-08

- First release: translate text on the shelf with Apple's on-device models.
