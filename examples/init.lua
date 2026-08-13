-- ~~~ Runnable demo for bemtvi-diff ~~~
--
-- Point bemtvi at this folder as its config and open the sample file:
--
--     BEMTVI_CONFIG=examples bemtvi examples/sample/new.txt
--
-- TRY IT:
--   :DiffGit        diff the current file's working tree against git HEAD
--   :DiffConflict   if the file has conflict markers, open them as a 3-way diff
--                     (open examples/sample/conflict.txt and run it for the diff3 layout)
--
-- Inside a diff:
--   ]c / [c      next / previous changed hunk     [C / ]C   first / last hunk
--   co / ct      resolve a conflict to ours / theirs (:DiffConflict diffs only)
--   cb / cp      keep both sides / stage the selected line(s) from this pane
--   ca / cx      apply what's staged / discard it
--   R            refresh (re-runs the source)     q   close
-- The panes scroll and move their cursor in lockstep, and a changed line shows the
-- edited characters highlighted (DiffText).
--
-- Anything BEYOND those two commands is the Lua API — build a spec and call open().
-- The custom `<leader>du` mapping below diffs the current buffer against an
-- UPPERCASED copy of itself: that's the whole extension surface a git/LSP/formatter
-- plugin would use to "send a diff for preview".

vim.g.mapleader = " "

-- Load the plugin straight from this repo (a local-dev spec: `dir` is never cloned).
-- A real config would instead use `{ "bemtvi/bemtvi-diff", config = ... }`.
btv.plugins({
  {
    name = "bemtvi-diff",
    dir = vim.fn.expand("<sfile>:p:h:h"), -- the repo root (this file's grandparent dir)
    config = function()
      require("bemtvi-diff").setup({
        sync_scroll = true,
        inline = true,
        signs = true, -- +/~/- gutter signs on changed lines (try it; default off)
        fillchar = "-", -- a rule across the blank alignment rows
      })
    end,
  },
})

-- Extensibility demo (Lua API only — no command needed): feed the viewer any diff.
vim.keymap.set("n", "<leader>du", function()
  local diff = require("bemtvi-diff")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local upper = {}
  for i, l in ipairs(lines) do
    upper[i] = l:upper()
  end
  diff.open({
    title = "caps demo",
    panes = {
      { label = "original", lines = lines },
      { label = "UPPER", lines = upper },
    },
  })
end, { desc = "bemtvi-diff: diff this buffer against an uppercased copy" })

-- 3-way demo (Lua API only): three synthetic sides. In a 3-pane spec the MIDDLE pane is
-- the common base; the outer two are center-anchored against it — exactly what
-- `:DiffConflict` builds from a diff3 conflict.
vim.keymap.set("n", "<leader>d3", function()
  require("bemtvi-diff").open({
    title = "3-way demo",
    panes = {
      { label = "ours", lines = { "alpha", "BRAVO", "charlie", "delta" } },
      { label = "base", lines = { "alpha", "bravo", "charlie" } },
      { label = "theirs", lines = { "alpha", "bravo", "CHARLIE", "echo" } },
    },
  })
end, { desc = "bemtvi-diff: open a synthetic 3-way (diff3) diff" })
