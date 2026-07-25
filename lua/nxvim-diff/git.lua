-- nxvim-diff.git — build a spec comparing the current file's working tree against its
-- git HEAD (the `:NxDiffGit` backing). Deliberately minimal: HEAD only. Anything
-- fancier (an arbitrary revision, the index, rev..rev) is left to a caller building
-- its own spec and calling `require("nxvim-diff").open(spec)` directly — the Lua API
-- is the extension point, not a pile of command flags.
--
-- This is itself an ordinary client of the public API: it gathers content with the
-- async, promise-returning `nx.git.*` and returns a spec; init.lua awaits it and calls
-- open(). The spec carries a `reload` hook, so `refresh` (`R`) re-reads HEAD.

local diff = require("nxvim-diff.diff")

local M = {}

-- to_lines(s) — split a git blob / subprocess stdout into a line array. The canonical
-- splitter lives in the pure engine (`diff.to_lines`) so every content source — a git
-- blob here, a `path` pane's file read in view.lua — agrees on what a trailing newline
-- means; this stays as the name a caller building its own git-backed spec reaches for.
M.to_lines = diff.to_lines

-- repo_relative(file, toplevel) — `file` expressed relative to the repo root, by simple
-- prefix strip. A standalone helper for a caller building its own spec; `head_spec` no
-- longer uses it (it asks git for the path via `--show-prefix`, which is symlink-safe —
-- a plain string strip breaks when `toplevel` is a resolved path and `file` is not).
function M.repo_relative(file, toplevel)
  local base = toplevel
  if base:sub(-1) ~= "/" then
    base = base .. "/"
  end
  if file:sub(1, #base) == base then
    return file:sub(#base + 1)
  end
  return file -- best effort; git resolves it against cwd anyway
end

-- head_spec(ctx) — a PROMISE of a spec: the current file at HEAD on the left
-- (read-only), the live working-tree buffer on the right (editable). `ctx` =
-- { file = <abs path>, bufnr = <n>, cwd = <file's dir> } (the shape init.lua builds).
--
-- Failures reject with a bare, position-free message (`error(msg, 0)`): the `:NxDiffGit`
-- path's `run` wrapper adds the single "nxvim-diff: " prefix and notifies, so prefixing
-- here too (or letting Lua tack on a "git.lua:NN:" prefix) would double up.
function M.head_spec(ctx)
  return nx.async(function()
    if ctx.file == nil or ctx.file == "" then
      error("this buffer has no file to diff", 0)
    end

    -- The file's HEAD blob via the native `nx.git.show` (replaces `git rev-parse
    -- --show-prefix` + `git show HEAD:<rel>`). It discovers the repo from the file and
    -- computes the repo-relative path ITSELF — symlink-safe (the reason the old code did
    -- the `--show-prefix` dance), so the plugin no longer touches path math. A path
    -- outside any repo rejects `ENOREPO`; a file with no HEAD version (new / untracked,
    -- empty repo) rejects `ENOENT`. Both map to the same bare, position-free messages the
    -- `:NxDiffGit` wrapper adds its single "nxvim-diff: " prefix to.
    local rel = ctx.file:match("[^/]+$") or ctx.file
    local ok, content = pcall(nx.await, nx.git.show(ctx.file, "HEAD"))
    if not ok then
      local code = type(content) == "table" and content.code or nil
      if code == "ENOREPO" then
        error("not a git repository", 0)
      elseif code and code ~= "ENOENT" then
        -- Anything that ISN'T "the file has no HEAD version" must say what actually went
        -- wrong (a broken index, an unreadable object): reporting every failure as
        -- "no HEAD version" would make a real git error look like an untracked file.
        error(("git failed reading %s at HEAD: %s"):format(rel, content.message or code), 0)
      end
      error(("no HEAD version of %s"):format(rel), 0)
    end

    local ft = vim.bo[ctx.bufnr] and vim.bo[ctx.bufnr].filetype or nil
    return {
      title = ("git HEAD — %s"):format(rel),
      -- `refresh` (`R`) re-runs THIS, so it re-reads the blob at HEAD rather than
      -- re-rendering the snapshot the diff was opened with.
      reload = function()
        return M.head_spec(ctx)
      end,
      panes = {
        { label = "HEAD", lines = M.to_lines(content), filetype = ft },
        { label = "working tree", buf = ctx.bufnr, filetype = ft },
      },
    }
  end)()
end

return M
