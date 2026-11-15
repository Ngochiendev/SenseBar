# Third-party artwork: CrossPet

CrossPet: https://github.com/lokicorvus/crosspet  
Upstream revision: `8954eb8f7f69fcfb8d35e9deceeb78e10c804402`  
Artwork: CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/).

The GPT, Claude, DeepSeek, Gemini, GLM, Qwen and Grok artwork bundled under
`Sources/SenseBar/Resources/CrossPet/` comes from CrossPet. Original artwork
files are retained. SenseBar changes display size, crops selected poses for
compact presentation, trims transparent margins and registers poses onto a shared
bottom-aligned canvas at runtime, and maps SenseBar companion events to these poses.
Any adapted artwork remains under CC BY-NC-SA 4.0, separately from SenseBar's
GPL-3.0 source code. These assets may not be used for commercial purposes.

Credit CrossPet / lokicorvus and the original design authors identified in
`CrossPet/ARTWORK-LICENSE.md`:

- GPT: the white-dragon character design by ZipZipPipe (Bilibili).
- DeepSeek: Mingyue by 上善无形 and the whale-maid design by ZipZipPipe (Bilibili).
- Claude: the community Claude character design (orange hair, flower and book),
  as credited by CrossPet.
- Gemini: the community Gemini character design (cat ears and star accessory).
- GLM, Qwen and Grok: character designs by ZipZipPipe (Bilibili), as credited upstream.

The upstream `app/web/effects.js` and `app/web/index.html` were inspected as
behavior references. SenseBar does not bundle that JavaScript/SVG animation
engine. It preserves the artwork proportions and displays static WebP poses anchored
to the bottom edge, replacing the image when the companion state changes.

This is an unofficial fan integration and is not endorsed by OpenAI,
Anthropic, DeepSeek or the original character artists.

The upstream license and attribution are included in the resource bundle as
`CrossPet/ARTWORK-LICENSE.md`. `CrossPet/CODE-LICENSE.txt` preserves upstream's
MIT source-code notice and artwork-license distinction; no CrossPet app,
AI integration, account access, WebView, or updater code is imported.

This notice covers the newly added CrossPet artwork; it is not a complete
license audit of the existing SenseBar codebase.
