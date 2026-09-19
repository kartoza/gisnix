# References

Generated pages — read from the actual registries, not hand-written, so
they can't drift from what the flake actually does:

- **[Operator commands](commands.md)** — every `gisnix` command, generated from
  `utils/commands.json`.
- **[Software bundles](bundles.md)** — every bundle, generated from
  `software/**/bundle.json`.

Regenerate either with `gisnix docs-generate-bundles` / `gisnix docs-generate-commands`
(or run the scripts under `docs/scripts/` directly — they're plain
`python3`, no flake needed).
