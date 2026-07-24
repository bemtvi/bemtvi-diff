<!-- DO NOT EDIT doc/nxvim-diff.txt BY HAND. It is generated from this file by
panvimdoc — run `scripts/gen-vimdoc.sh` after editing. -->

A Meld-style side-by-side (and 3-way) diff viewer for nxvim. It is a diff VIEWER you feed a diff to
— not a git tool. The core renders and navigates a diff; where the two (or three) sides come from
is the caller's business. It is built entirely on the native `nx.*` plugin API (ADR 0002): the
sides are read-only `nx.view` surfaces, the line tints / intra-line spans / alignment are extmarks,
and the panes stay locked together over the editor's scrollbind seam (`WinScrolled` +
`nx.win.set_topline` / `set_leftcol` / `set_cursor`).

```
 HEAD — src/app.rs                │ working tree
 1  fn main() {                   │ 1  fn main() {
 2      let x = compute();        │ 2      let x = compute();
~3      println!("{}", x);        │~3      eprintln!("{}", x);
                                  │+4      log::info!("done");
 4  }                             │ 5  }
```

(`~` a changed line — its edited chars are tinted `DiffText`; `+` an added line; the blank left row
is the alignment filler opposite it.)

Only two commands are exposed; everything else is the Lua API, because a diff source is better
expressed in Lua than as a pile of command flags.

<!-- Passed through verbatim so `:help nxvim-diff` lands on this page (panvimdoc
     derives per-section tags but no bare project tag). -->
```vimdoc
                                                *nxvim-diff* *nxvim-diff-intro*
```

# Commands

```
:NxDiffGit       Diff the current file's working tree vs git HEAD.
:NxDiffConflict  Open this file's git conflict markers as a diff.
```

`:NxDiffGit` diffs the current file against its git HEAD. Git runs in the FILE's own directory (not
the editor cwd), so a file edited from outside `:pwd` diffs against its own repo. It fails loud with
a clean message — "not a git repository", "this buffer has no file to diff", or "no HEAD version of
<file>" (a new / untracked file). Richer comparisons (an arbitrary rev, the index, `rev..rev`) are
intentionally Lua, not flags: build a spec with `require("nxvim-diff.git").to_lines(...)` and call
`open()` (see The Lua API).

`:NxDiffConflict` — if the current buffer has git conflict markers, open them as a diff. A
diff3-style conflict (with a `|||||||` base section, from `merge.conflictStyle=diff3`/`zdiff3`)
opens as a 3-way ours | base | theirs; a plain-merge conflict opens 2-way ours/theirs. Each side is
the FULL file with its section substituted, so the conflict shows in its surrounding context. A
clean file just notifies.

# Usage

The panes scroll and move their cursor in lockstep (Meld-style scrollbind), and a changed line shows
its edited characters tinted (`DiffText`). The default buffer-local maps on every pane (all
rebindable, see Configuration):

```
]c   Jump to the next changed hunk.
[c   Jump to the previous changed hunk.
]C   Jump to the last hunk.
[C   Jump to the first hunk.
co   Resolve the conflict to OURS (conflict diffs only).
ct   Resolve the conflict to THEIRS (conflict diffs only).
cb   Resolve the conflict to BOTH (ours then theirs).
cp   Stage the selected line(s) from this pane (normal or visual mode).
ca   Apply the staged lines as the resolution.
cx   Clear the staged lines.
R    Refresh — re-run the source and re-render.
q    Close the diff, restoring the prior layout.
```

Hunk motions wrap around (past the last hunk → the first, and vice versa). The conflict maps
(`co` / `ct` / `cb` / `cp` / `ca` / `cx`) only do something on a `:NxDiffConflict` diff — see
Conflict resolution.

# Three-way layout

A 3-pane diff is center-anchored: the MIDDLE pane is the common base, and the two outer panes are
aligned against it. A base line and each side's version of it sit on the same screen row; a line a
side inserted shows as an added row with the other panes filled (blank) opposite it; a line a side
deleted shows as a blank opposite the base. The outer panes carry intra-line `DiffText` spans
(computed against the base line); the base pane keeps a whole-line tint.

Any 3-pane spec passed to `open()` is treated this way — the middle pane is the base.
`:NxDiffConflict` builds exactly such a spec from a diff3 conflict.

# The Lua API

- `require("nxvim-diff").open({spec})` — THE generic entry point ("send a diff for preview"). Any
  plugin (git, LSP rename, formatter, …) builds a `{spec}` and calls this. Validates the spec (fails
  loud), closes any live session, and renders.
- `require("nxvim-diff").git_head()` — open the current file vs git HEAD (what `:NxDiffGit` calls).
- `require("nxvim-diff").conflict()` — parse this buffer's conflict markers and open them (what
  `:NxDiffConflict` calls).
- `require("nxvim-diff").close()` — tear down the active diff, restoring the prior layout.
- `require("nxvim-diff").refresh()` — re-run the active session's source and re-render.
- `require("nxvim-diff").session()` — the live session handle (or `nil`), for add-ons and tests.

A `{spec}` is:

```lua
{
  title = <string?>,
  panes = { <pane>, <pane> [, <pane>] },  -- 2 or 3
}
```

Each `<pane>` carries EXACTLY ONE content source — `lines` (an array of strings), `buf` (a bufnr),
or `path` (an absolute path) — plus optional `label`, `filetype`, and `readonly` (default `true`):

```lua
{ label = "HEAD", lines = {...}, filetype = "rust" }
{ label = "working", buf = 0, readonly = false }
{ label = "disk", path = "/abs/file" }
```

In a 3-pane spec the middle pane is the base (see Three-way layout).

# Extending

Because `open()` takes any spec, a one-screen plugin can preview a diff. A formatter preview — this
buffer vs its formatted output:

```lua
vim.keymap.set("n", "<leader>fp", function()
  local src = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local out = vim.fn.systemlist("prettier --stdin-filepath " .. vim.fn.expand("%"), src)
  require("nxvim-diff").open({
    title = "format preview",
    panes = {
      { label = "buffer",    lines = src, filetype = vim.bo.filetype },
      { label = "formatted", lines = out, filetype = vim.bo.filetype },
    },
  })
end, { desc = "preview formatting as a diff" })
```

The bundled git and conflict support are themselves just clients of `open()` — see `git.lua` /
`conflict.lua` for fuller examples.

# Configuration

`require("nxvim-diff").setup({opts})` merges `{opts}` over the defaults (shown):

```lua
require("nxvim-diff").setup({
  sync_scroll = true,   -- lock the panes' viewports together (uses WinScrolled)
  sync_cursor = true,   -- keep the panes' cursor row aligned
  wrap = false,         -- soft-wrap in panes (off → columns align, leftcol syncs)
  inline = true,        -- tint changed spans within a line (DiffText)
  signs = false,        -- per-hunk gutter signs +/~/- (opt-in)
  fillchar = "-",       -- glyph painted across a blank filler row ("" leaves it blank)
  layout = "auto",      -- "auto" | "vertical" | "horizontal"
  keymaps = { ... },    -- key -> action; false disables a key
  highlights = { ... }, -- Diff* / NxDiff* group overrides
  on_attach = nil,      -- fn(session, api, bufnr) per pane buffer
})
```

`keymaps` is a `key -> action` table merged key-by-key (so you override one binding without
redeclaring all). An action is a built-in name (`next_hunk`, `prev_hunk`, `first_hunk`, `last_hunk`,
`choose_ours`, `choose_theirs`, `choose_both`, `pick_lines`, `apply_picked`, `clear_picked`,
`refresh`, `close`), a function `fn(session, api)`, or `false` to drop a key. An unknown name fails
loud. `pick_lines` also binds in visual mode (the selection is its input); the other built-ins are
normal-mode.

Highlights use the canonical `DiffAdd` / `DiffDelete` / `DiffChange` / `DiffText` groups, so a
ported colorscheme themes the viewer unmodified; only a fallback is installed when a group is
undefined. Plugin-private extras (filler, sign, label colours) live under the `NxDiff*` namespace.

`signs` puts a `+` / `~` / `-` gutter sign on each added / changed / deleted line (opt-in; off by
default since the tint + `DiffText` already convey a change). When on, every pane reserves the sign
column (`signcolumn=yes`) so the panes stay the same width and keep lining up. `fillchar` paints its
glyph across each blank filler (alignment) row — vim's diff-`fillchars` style — or `""` leaves the
row blank. Both ride core extmark decorations (`sign_text` / `line_fill`).

# Conflict resolution

`:NxDiffConflict` opens the WHOLE file as a 3-way (or 2-way) diff with every conflict shown in
context — the reconstructed ours/base/theirs sides differ only where the conflicts are, so
`]c` / `[c` step from one to the next.

Every resolve map acts on the conflict UNDER THE CURSOR: its marker block (`<<<<<<<` … `>>>>>>>`) is
replaced in the live buffer via the editor's `nx.buf.set_lines`, as one undoable edit, and the diff
closes so you land back on the file (`:w` to save). Each conflict knows the alignment rows it
occupies, so the cursor picks which one is resolved; when the cursor sits on shared context between
conflicts, the nearest is chosen. Every write is guarded — if the markers are no longer where the
diff found them (the file changed underneath), it aborts loud and writes nothing. On a plain
(non-conflict) diff the maps just say there's nothing to resolve.

```
co  (choose_ours)    Replace the block with OURS.
ct  (choose_theirs)  Replace the block with THEIRS.
cb  (choose_both)    Replace the block with BOTH sides — ours then theirs
                     (left-to-right reading order), markers dropped.
```

When neither whole side is right, build the resolution by hand:

```
cp  (pick_lines)     Stage the selected line(s) FROM THE FOCUSED PANE. In normal
                     mode it stages the current line; in visual mode the whole
                     selection. Run it on ours, then on theirs, then move on —
                     picks accumulate in selection order. Only the conflict's OWN
                     lines qualify: shared context outside the conflict and blank
                     alignment-gap rows are refused. Each staged line gets a `▶`
                     gutter sign and a background tint on the pane it came from.
ca  (apply_picked)   Replace the block with everything staged so far.
cx  (clear_picked)   Discard the staged lines (and their signs).
```

Picks are per-conflict and last only for the current diff session.

# Performance

The line diff is an LCS with two guards so it never freezes the editor: shared leading/trailing
lines are trimmed before the O(n·m) table runs (so a few edits in a big file stay cheap and get the
exact alignment), and a still-huge, highly-divergent middle falls back to a coarse block-replace
(`diff.LCS_CELL_LIMIT`) rather than allocating an enormous table — correct (every line is shown),
just not the minimal-edit alignment.
