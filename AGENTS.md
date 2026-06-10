# AnyUpright Agent Instructions

## Scope

- This repository contains a Final Cut Pro FxPlug 4 plug-in suite.
- Keep this file focused on instructions agents need while working in the repo.
- Put product goals, architecture notes, plugin behavior, and human-readable context in `docs/README.md`.
- Do not create `.agents/skills/`. If repo-specific skills become useful, ask the user to run `$init-codex-project` again or explicitly approve that structure.

## Repository Shape

- Current project: Xcode-created FxPlug 4 template project.
- Main project file: `AnyUpright.xcodeproj`.
- Wrapper app target: `Wrapper Application`.
- FxPlug code lives under `AnyUpright/Plugin/`.
- Wrapper app code lives under `AnyUpright/Wrapper Application/`.
- Planned product shape: one suite with four separate Final Cut effects, sharing common geometry, detection, and Metal rendering code.

## Development Rules

- Prefer Swift for plugin/control logic and Metal for realtime image transforms.
- Keep playback rendering lightweight. Detection and analysis should run on explicit user action or cached frame analysis, not on every rendered frame.
- Persist user-facing state through FxPlug parameters so renders remain reproducible after Final Cut Pro, Motion, or the plug-in XPC process restarts.
- Before adding behavior that crosses plugin boundaries, check `docs/README.md` for the intended shared architecture.
- Before changing any behavior that touches Y-axis handling, coordinate conversion, hit testing, OSC drawing, Metal overlay/render coordinates, or parameter writeback involving positions, read `docs/engineering-notes/y-axis-coordinate-conventions.md` and follow its project conventions.
- Keep the Final Cut effects separate in user-facing workflow; do not collapse Source Quad and Outer Corners into one effect with a mode selector unless the user explicitly changes that direction.

## Documentation

- Update `docs/README.md` when product behavior, plugin boundaries, architecture decisions, setup steps, or validation workflows change.
- Do not duplicate long product explanations in this file.

## Localization And Text

- Existing template resources use `en.lproj`; treat English as the current source locale.
- If plugin display names, inspector labels, custom UI text, or localized strings change, update the relevant `.strings` files in the same change.
- There is no multi-locale support policy yet; record one in `docs/README.md` before adding additional locales.

## Validation

- For code changes, run the most relevant Xcode build or explain why it cannot run.
- Prefer validating the `Wrapper Application` scheme first because the wrapper registers the FxPlug plug-in with macOS.
- For rendering changes, verify behavior in Motion or Final Cut Pro when possible, especially proxy resolution, non-square pixels, trimming/retiming, and keyframed parameters.
- For Metal transform changes, include targeted tests or deterministic sample calculations for geometry math when practical.

## Safety

- Preserve user work. Do not reset, clean, or remove Xcode-generated files unless the user explicitly asks.
- Do not commit, push, notarize, or package releases unless explicitly requested.
- This repo is local-first; do not introduce Docker or external service dependencies without user approval.
