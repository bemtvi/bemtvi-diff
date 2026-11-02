-- bemtvi-diff.highlights — the diff palette and a fallback-only applier.
--
-- The line groups use the canonical **Diff\*** names vim/neovim diff mode uses
-- (`DiffAdd` / `DiffDelete` / `DiffChange` / `DiffText`), on purpose: a ported
-- colorscheme that styles those names themes the viewer UNMODIFIED. We only install
-- a default when the group isn't already defined (and an explicit user override always
-- wins), so a colorscheme that styles `Diff*` keeps its colors regardless of load
-- order. The plugin-private extras (the sign glyphs' colors, the filler tint) live
-- under the `BtvDiff*` namespace.
--
-- Fallback colors are DERIVED from the active theme via `btv.hl.palette()`, so the
-- viewer reads as part of whatever colorscheme is loaded (bemtvi's own by default, a
-- light flavour as well as a dark one), and `defaults()` is a function re-evaluated on
-- every apply: bemtvi-diff re-applies on `ColorScheme`. The signs take the palette's
-- accents. The line groups DO carry `bg`, since a diff wants the whole changed line
-- tinted: each is its accent faded into the theme's background with `btv.hl.blend`,
-- kept dim so text stays legible. `bg` is the attribute that matters for the three
-- line groups in particular: they are painted as the core's full-width line-background
-- layer (see view.lua's `pane_marks`), so a theme that gives `DiffAdd` only a
-- foreground tints nothing. `DiffText` is an ordinary text span over the changed
-- characters, so its `fg` / `bold` apply as usual.

local M = {}

-- defaults() -> `name -> spec` (the `btv.hl.define` opts table) for the active theme.
function M.defaults()
  local p = btv.hl.palette()
  local function tint(accent, ratio)
    return btv.hl.blend(accent, p.bg, ratio)
  end
  return {
    -- canonical Diff* (themed by a ported colorscheme)
    DiffAdd = { bg = tint(p.green, 0.2) }, -- an added line (the b-only / insertion rows)
    DiffDelete = { bg = tint(p.red, 0.2) }, -- a deleted line (the a-only / deletion rows)
    DiffChange = { bg = tint(p.blue, 0.15) }, -- a changed line's unchanged background
    DiffText = { bg = tint(p.blue, 0.35), bold = true }, -- the changed spans in a DiffChange line
    -- plugin-private extras
    BtvDiffFiller = { fg = tint(p.muted, 0.5) }, -- the alignment filler rows (fillchar gutter)
    BtvDiffSignAdd = { fg = p.green }, -- the "+" hunk sign
    BtvDiffSignChange = { fg = p.yellow }, -- the "~" hunk sign
    BtvDiffSignDelete = { fg = p.red }, -- the "-" hunk sign
    BtvDiffSignPick = { fg = p.blue, bold = true }, -- the picked-line gutter sign
    BtvDiffPick = { bg = tint(p.blue, 0.25) }, -- a staged (picked) line's background tint
  }
end

-- apply(overrides) — define each group as a fallback (see the module header). An
-- entry in `overrides` is applied unconditionally; an unrecognized override name is
-- still honored (a caller may color an extra group). Idempotent, and safe to re-run on
-- `ColorScheme`: `btv.hl.fallback` re-derives a group nothing else owns while leaving a
-- theme's (or the user's) own definition alone.
function M.apply(overrides)
  overrides = overrides or {}
  local defaults = M.defaults()
  for name, spec in pairs(defaults) do
    if overrides[name] then
      btv.hl.define(0, name, overrides[name])
    else
      btv.hl.fallback(name, spec)
    end
  end
  for name, spec in pairs(overrides) do
    if not defaults[name] then
      btv.hl.define(0, name, spec)
    end
  end
end

-- hl_for(kind) — the line highlight group for an alignment row kind, or nil for an
-- unchanged / filler row that needs none.
function M.hl_for(kind)
  if kind == "add" then
    return "DiffAdd"
  elseif kind == "del" then
    return "DiffDelete"
  elseif kind == "change" then
    return "DiffChange"
  end
  return nil
end

return M
