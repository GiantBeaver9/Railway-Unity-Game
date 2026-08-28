# THIS!: The Game — WebGL build (Railway)

A WebGL-deployable copy of the Unity 6 game. The original desktop project loads
all art/audio at runtime with synchronous `System.IO.File`/`Directory` calls off
`ThisL.SpriteLibrary.AssetsRoot` (the repo-root `assets/` folder). WebGL has no
synchronous filesystem, so this copy routes every one of those ~66 call sites
through a new in-memory asset cache (`AssetSource`) that is HTTP-preloaded from
`StreamingAssets/` at boot behind a loading bar.

**Do not edit `unity/` or `assets/` at the repo root — this is a self-contained copy.**

## What changed vs. the original

- `unity/Assets/Scripts/Assets/AssetSource.cs` (**new**) — async-preloads every file
  listed in `StreamingAssets/assets_manifest.txt` into a `Dictionary<string,byte[]>`
  keyed by the assets-relative path, and exposes synchronous `Exists` / `Bytes` /
  `Text` / `Files` / `DirExists` helpers. Absolute paths built from `AssetsRoot` are
  normalized to the cache key by stripping everything up to and including `assets/`.
- `SpriteLibrary.AssetsRoot` now returns `Application.streamingAssetsPath + "/assets"`.
- ~66 call sites across 21 files switched `File.Exists`→`AssetSource.Exists`,
  `File.ReadAllBytes`→`AssetSource.Bytes`, `File.ReadAllText`→`AssetSource.Text`,
  `Directory.Exists`→`AssetSource.DirExists`, `Directory.GetFiles`→`AssetSource.Files`.
  Graceful fallbacks (procedural SFX, placeholder sprites) are all preserved.
- `Core/WebGlPreloader.cs` (**new**) — a MonoBehaviour with an IMGUI loading bar that
  runs `AssetSource.Preload()` and only starts `GameFlow` (which builds the world)
  once `AssetSource.Ready`. `GameBootstrap` now spawns this instead of `GameFlow`.
- `Editor/BuildScript.cs` (**new**) — headless WebGL builder; synthesizes an empty
  boot scene (the game is code-first) and outputs to `webgl/Build`.
- `StreamingAssets/assets/` — a copy of the repo-root `assets/` folder (web-accessible).
- `StreamingAssets/assets_manifest.txt` — newline-separated list of every asset path
  (WebGL can't enumerate StreamingAssets at runtime, so the list is generated at copy time).

## Build the WebGL player

Requires the **WebGL Build Support** module. On this machine it is **not installed**
(the editor only has WindowsStandaloneSupport), so the headless build currently fails
with `BuildResult: Unknown` / no output. Install it once via **Unity Hub → Installs →
6000.5.9f1 → Add Modules → WebGL Build Support**, then:

```bash
# Editor MUST be closed (no webgl/unity/Temp/UnityLockfile).
"C:/Program Files/Unity/Hub/Editor/6000.5.9f1/Editor/Unity.exe" \
  -batchmode -quit -nographics \
  -projectPath "<repo>/webgl/unity" \
  -buildTarget WebGL \
  -executeMethod ThisL.EditorTools.BuildScript.BuildWebGL \
  -logFile "<repo>/webgl/build_webgl.log"
```

On success this writes `webgl/Build/` containing `index.html`, `Build/` (engine
`.wasm`/`.data`/`.framework.js`), and `StreamingAssets/assets/…` (the runtime asset
tree the cache fetches).

If the manifest ever drifts from the asset tree, regenerate it:

```bash
cd webgl/unity/Assets/StreamingAssets
find assets -type f \( -name '*.png' -o -name '*.wav' -o -name '*.json' \
  -o -name '*.txt' -o -name '*.webp' \) | sed 's|^assets/||' | sort > assets_manifest.txt
```

## Deploy to Railway

The `Dockerfile` serves the pre-built `webgl/Build/` with nginx, substituting
Railway's `$PORT`.

1. Build the WebGL player (above) so `webgl/Build/` exists.
2. In the Railway service settings, set **Root Directory** to `webgl` (so the Docker
   build context is this folder and `COPY Build/` resolves).
3. Railway auto-detects `railway.json` → Dockerfile builder. Deploy.

Local smoke test of the container:

```bash
cd webgl
docker build -t thisl-webgl .
docker run --rm -e PORT=8080 -p 8080:8080 thisl-webgl
# open http://localhost:8080
```

### Notes

- The build uses **uncompressed** WebGL output (`WebGLCompressionFormat.Disabled`) so
  nginx needs no `Content-Encoding` handling. To shrink payloads, set Gzip or Brotli
  in `BuildScript.cs` and uncomment the matching header blocks (see `default.conf.template`).
- The `assets/` tree is ~136 MB; it is fetched file-by-file at boot (8 concurrent
  requests) and cached hard by the browser. First load shows the loading bar.
