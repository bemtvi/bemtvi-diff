# nxvim-diff

A Meld-style **side-by-side diff viewer** for
[nxvim](https://github.com/davidrios/nxvim) — two (or three) panes locked together,
changed/added/removed lines tinted, aligned with filler rows, navigable hunk-by-hunk.

It is built entirely on the native `nx.*` plugin API (ADR 0002): the read-only sides
are `nx.view` surfaces, every line tint and intra-line span is an extmark, and the panes
stay in lockstep through the editor's `WinScrolled` event plus `nx.win.set_topline` /
`set_leftcol` / `set_cursor`.

It's a **renderer you feed a diff to**, not a git tool. The core knows how to render and
navigate a diff; *where the sides come from* is the caller's business. So there are only
two commands — the long tail lives in the Lua API, where it belongs.

```
 HEAD — src/app.rs                │ working tree
 1  fn main() {                   │ 1  fn main() {
 2      let x = compute();        │ 2      let x = compute();
~3      println!("{}", x);        │~3      eprintln!("{}", x);
                                  │+4      log::info!("done");
 4  }                             │ 5  }
```

(`~` a changed line — its edited chars are tinted `DiffText`; `+` an added line; the
blank left row is the alignment filler opposite it.)

## Install

Declare it with the built-in `:Plugins` manager, then `:PluginSync`:

```lua
nx.plugins({
  {
    "davidrios/nxvim-diff",
    config = function()
      require("nxvim-diff").setup({})
    end,
  },
})
```

Two commands, by design:

```
:NxDiffGit        diff the current file's working tree against git HEAD
:NxDiffConflict   if the current file has conflict markers, open them as a 3-way diff
```

Everything else is the Lua API — `require("nxvim-diff").open({ panes = {...} })` renders
any 2- or 3-pane spec you build (git, LSP rename, formatter preview, …).

## Documentation

Full docs — the commands, in-diff navigation and conflict-resolution keys, the 3-way
layout, the `open()` spec and the rest of the Lua API, `setup()` options, and the perf
guards — live in the help file. The same source renders both on GitHub and in the editor:

- In editor: `:help nxvim-diff`
- On GitHub: [doc/nxvim-diff.md](./doc/nxvim-diff.md) (the help source)

## Development

A Lua test suite (`test/*_spec.lua`) runs on nxvim's native `nx.test` framework — pure
specs for the LCS diff engine, the conflict-marker parser, config/spec validation, and
hunk navigation; live specs driving real 2- and 3-pane diffs, scroll/cursor sync, the
line tints + `DiffText` spans, and `:NxDiffGit`:

```sh
nxvim --test-plugin .
```

The vimdoc `doc/nxvim-diff.txt` is **generated** from `doc/nxvim-diff.md` via
[panvimdoc](https://github.com/kdheepak/panvimdoc): edit the `.md`, then run
`bash scripts/gen-vimdoc.sh` (needs `pandoc` + `git`). Never edit the `.txt` by hand.

## License

MIT — see [LICENSE](LICENSE).
