# FrostADR

## Run the macOS App

For the easiest local preview, double-click `FrostADR.command` in Finder.
It builds a debug app bundle at `dist/FrostADR.app` and opens it.

From Terminal, run:

```bash
./FrostADR.command
```

To build a release app bundle for local use, double-click `PackageFrostADR.command` or run:

```bash
./PackageFrostADR.command
```

The reusable build script is:

```bash
Scripts/build_app.sh --debug --open
Scripts/build_app.sh --release
```

Generated build output lives under `dist/` and is intentionally not committed.
