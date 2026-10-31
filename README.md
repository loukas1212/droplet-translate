# Translate

A shelf widget for [Droppy](https://getdroppy.app) that translates text between
two languages you choose, on your Mac.

## What it does

- Type or paste text on the shelf, press Return, read the translation.
- Pick the source language, or let it detect the language.
- Swap the two languages in one click. The translation becomes the new text.
- Paste and copy the translation.
- Capture a region of the screen and read it, or pull the text another app has
  selected.
- Choose where the result lands: in the widget, in the droplet's own side
  panel on the screen's edge, or in a floating panel next to the captured
  region. The edge panel is only on screen when it is the chosen place.
- Every surface wears the app's own glass over its black, so the droplet
  looks like Droppy rather than like a second app.
- Escape calls off a capture or a selection that is still being translated.
- Every part of the settings has a page of its own, the way System Settings
  keeps its panes apart: General, Preview, Permissions and Guide.
- The settings draw what they describe: where the translation will appear,
  at the size it really is.
- The settings say which system permissions the droplet needs, and whether
  they are allowed.
- The two languages sit side by side in one row, with the disc that trades
  them around between them, and every row says what it does under its name.
- The interface speaks Thai, English and French.

## Built on the system

| Need | What it uses |
| --- | --- |
| Translation | Apple's Translation framework, on-device models |
| Language detection | NaturalLanguage |
| Copy and paste | NSPasteboard |
| Language names | Foundation locale APIs |
| Reading a screen region | ScreenCaptureKit and Vision |
| Reading a selection | the Accessibility API |
| An optional AI engine | `URLSession` |

Apple's models do the work on the Mac, and nothing leaves it. You can point
the droplet at your own AI provider instead — OpenAI, Anthropic, Gemini, a
local Ollama or an endpoint of your own. The General page says plainly where
the text goes: the note under the card says that your text stays on this Mac,
unless you choose an external AI provider. The AI engine has a provider of its
own, and only a custom endpoint can be changed: the others know where they
live. The API key is kept in the keychain, never in the preferences and never
in the log.

The droplet asks for screen recording, accessibility, clipboard, shelf and
network access only for the actions that need them.

## Requirements

- Droppy 16.0.1 or later
- macOS 15 or later for translation (the droplet loads on macOS 14 and says so)
- The language pair downloaded once, for Apple's own models. Open the droplet's
  page in Droppy's Settings, then **General**, and choose **Download
  languages**.

## Tests

`swift test` runs the droplet's own tests: the three languages answer the same
keys, the engine's endpoints and model choice are pinned, the chunker loses
nothing, the pin's rules hold, and the names the stored values keep cannot
change by accident.

## Credits

Translation and language detection are Apple system frameworks.
Everything else is original.
