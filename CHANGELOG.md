# Changelog

## [1.2.0] - 2026-10-31

The droplet as it stands in this release. A feature that was tried and taken
away again is not in it.

### The settings

- The settings are pages: Translation, Display, Permissions and Guide.
  The droplet's own page opens them as doors, each with its tile, its name
  and a line about what is inside.
- Every row is one of Droppy's own: the name on the left with a line of
  description under it, the control on the right, and a short line under the
  name of the section. Nothing is boxed, outlined or coloured on its own.
- A row with nothing to choose carries the symbol that says what it is: a
  globe for the interface language, a brush for the theme, a key for the API
  key, a network for the endpoint, a chip for the model.
- The droplet's own page lists the system permissions it needs. One already
  given wears a green check and the word Granted; the one still to ask carries
  a Grant button, and one the user refused says where it can be changed —
  System Settings, which is opened for them. A permission that does not exist
  on this Mac is not listed at all. The states are read again when the user
  comes back from System Settings.
- The two languages sit side by side in one row: what the text is written in
  on the left, what it comes out in on the right, and the disc that trades the
  two places between them. Under them, a row says whether the models for that
  pair are on this Mac — a green check when they are, a crossed circle and a
  download button when they are not. Apple's two engines download models per
  pair and per strategy; the network engines download nothing, so the row is
  not there.
- The language menus list only the models already downloaded for the pair, so
  a choice translates without a wait. Their last row, "Download languages…",
  opens the Translation page, where another pair can be fetched.
- The source can stay on Auto, where the droplet detects the language, or be
  pinned to one.
- The swap disc trades the pair; on the shelf the translation becomes the new
  input, so it can be translated back.
- Translate as You Type translates the text as it changes, and Copy Translation
  Automatically puts each finished result on the clipboard.
- The side panel can sit on the left or the right edge of the screen. The side
  panel and the floating panel show the original and the translation, or the
  translation alone in a card only as tall as that result, with the target
  language picker above the box and a close in its top corner. Both keep the
  shelf widget's side margin, so the boxes sit at the same distance from the
  card's edges wherever they appear. Drag the card to move it,
  and drag the side panel's handle to pull the result out or fold it away.
- Keyboard shortcuts for translating the selection, reading a region and
  opening the droplet live in Droppy's own settings, and every one starts
  unbound so the user picks the key. The one that opens the droplet brings up
  whichever place the Display page chooses, with the caret in the input, so
  one key reaches all three. Reset to Defaults returns the translation
  settings to their starting values.
- Every pop-up on the pages sits on the middle of its row and wears the same
  quiet glass with a hairline edge.
- The engine is one choice: Classic, Apple Intelligence or AI Translation. An
  info tip beside the row says what each one does. A line under the card says
  where the text goes: it stays on this Mac, unless an external AI provider is
  chosen. A link under it opens the guide.
- The Display page shows the chosen place with one example translation drawn
  by the droplet itself: the shelf widget in its host's shell, the edge
  panel's own card on the chosen edge, or the floating panel on its own
  surface. The picture follows every picker as it moves — the place, the
  two boxes or the translation alone, and the side the panel docks to — and
  the Screen edge row sits under it, only while the side panel is chosen.
- Every picture is drawn at one width, so the place never changes how large
  the example reads, and it is drawn the way the app draws that surface: the
  host's own shelf surface, or the droplet's own card, over the black under
  it, so a glass theme melts from black the way it does on the notch instead
  of wearing the pale glass of the settings page. Each picture is one piece,
  never two shapes in two colours.
- The Guide is four sections, not a numbered walkthrough: the three ways to
  start — typing on the shelf, capturing a region, reading a selection — what
  happens to the text once it is in, the keys it answers to, and the pin. Each
  line carries the symbol of the thing it names.
- The side panel is one card: the card, the two corners that run with the
  screen's edge and the handle that hangs under it are a single shape. Its
  face is the theme Droppy is set to — solid black, clear Liquid Glass, or
  black melting into that glass — drawn on the card's own outline with the
  system glass, so the thin dark edge is the card's own and nothing sits
  under it. The free edges catch a thin light at the top. The input and result
  boxes have no surface of their own: their words sit straight on the face,
  so the pane reads as one piece without a dark border. The face follows the
  setting for the display the
  panel is on, and a change reaches the card while it is open. The card folds
  back into the tab when another window takes the focus, unless the user
  pinned it. The handle comes out by growing that shape, so the face stays one
  continuous surface while it moves.
- Copying the result is a row on the Translation page, beside the other things
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

- The result lands in the widget, in the droplet's own side panel, or in a
  floating panel next to the captured region. The choice is in the
  settings, and changing it moves the result that is on screen. Every surface's
  words carry a dark halo, so white text stays readable when a bright app shows
  through the glass.
- The edge panel is only on the screen when it is the chosen place for the
  result. A card the user did not ask for does not sit at the edge of their
  screen.
- The edge panel opens with its empty input box tall enough to hold the more
  menu above the footer, so no row is cut at the card's top.
- The edge panel's more menu can pin the card: an outside click no longer folds
  it, and the pin clears when the card closes or the user unpins it. The card
  keeps the clear, focused face for as long as it is open — in front, in the
  background, or the moment it is unpinned — instead of taking the system's
  frosted inactive one, and a click brings Droppy forward.
- A trash beside the more disc clears the text and the result on every surface.
  The shelf folds back to its opening card, and the panels give the input its
  room back.
- Paste and copy are footer controls too, in one pill that swaps its word with
  the boxes: Paste while there is no translation, Copy once one lands. The
  pill keeps the trash's place from the empty card to the result, so the row
  reads more, trash, paste or copy, then the engine.
- The edge panel wears the app's theme, like the rest: its glass follows the
  theme Droppy is set to — Black, Liquid Glass, or Dynamic Glass — so the card
  changes with the notch and the shelf.
- The floating panel is the edge panel's card in the panel's own rounded
  outline: the same language row, the same boxes and the same footer, so a card
  behaves identically wherever it is asked to appear. It opens empty from the
  droplet's shortcut — set in Droppy's Shortcuts page, next to the two capture
  shortcuts — when the Display page chooses it, and takes the keyboard in the
  text field, or opens beside a capture with the result in it. The card ends
  at its face, with no handle under it.
- The result box beside the input is never shorter than the input: a short
  answer draws two boxes of one size, a longer one leaves the input at its own
  height and fits the words up to 400pt before they scroll.
- The floating panel wears the same themed surface and the same footer as the
  other surfaces: the more disc on the leading edge, the trash and the paste or
  copy pill beside it, and the translate mark with its engine on the trailing
  edge. The footer keeps the same 6pt rim above
  the disc as the shelf and the edge panel, so the more menu sits as close to
  the result box as it does on the other cards. Its more menu opens upward from
  the disc in one column, on the same spring as the shelf and the edge panel,
  and its glass starts as the disc's circle and slides up into the menu's
  rounded rectangle, so the background comes out of the button before the rows
  arrive.
- With an original, the two languages sit in one glass row at the card's top,
  as on the shelf: the pair ends on the edge of the swap disc that the row
  cuts its pocket for, so the disc's lower half sits in the input box's top
  edge. The row and its box travel together, and swapping turns the disc half
  a circle as the languages change places.
- The target language sits in the result's header as a menu with a chevron
  when the card shows the result alone; choosing another language translates
  the source again. Pin stays in the more menu, so the header keeps only the
  picker and the close disc; the panel keeps the clear glass while it is open,
  like the edge card.
- The floating panel blooms out of the point the result came from: the card and
  everything on it grow on a radius from a dot at the captured region, run a
  little past their size and settle, and the words come in as the card is
  nearly out. It closes by shrinking back into the same dot on a shorter curve
  that never grows on the way in. The edge panel folds on that same curve, but
  its tab runs a little past its own size and settles back, so the close ends
  with one give instead of a stop.
- The panel's controls wear the edge panel's sliding mark: on macOS 26 a
  capsule of Liquid Glass in the control's own frame, washed with the theme's
  highlight, travels to the control under the pointer, and the control's glyph
  and words are drawn again above it so they stay crisp; on older systems the
  same mark is a faint light in the control's outline. Every control keeps its
  glass and its words, so nothing is drawn twice on a button.
- The panel says nothing while the screen is being read; it waits for the
  result.

### The widget

- The shelf wears the edge panel's card: the language row with the swap disc,
  the input box, the result box and the footer with the tools and the engine.
  The boxes are the edge panel's frosted panes, so they stay visible on the
  card instead of reading as text on black.
- The shelf opens with the input alone, as the edge panel does; its card is as
  tall as the input needs, and grows to the fitted result when one arrives.
  The input spans 110–150pt. The result beside it is never shorter than the
  input, so a short answer leaves two level boxes; a longer one keeps the input
  small and fits the words up to 380pt minus the input (270pt at the shortest
  input, 230pt at the tallest). The translation alone fits 101–380pt, and the
  card never passes 480pt. The language row stays above the boxes; the full
  result face folds it away and puts the target picker in the result's top
  corner, at the copy pill's size.
- Translation only in the settings folds the input away once a translation
  arrives; Original & Translation keeps it above the result.
- A capture or a selection opens the shelf on the step its content needs:
  Translation only on the full face, Original & Translation with both boxes.
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
- A status or error keeps the input above it and grows the card, so the words
  being translated stay in view.
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
