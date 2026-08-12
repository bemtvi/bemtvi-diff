-- Live :DiffGit test (Phase 5): exercises the git source end to end — a real init'd
-- repo (HEAD read), plus the not-a-repo / nameless / not-in-HEAD error paths — and
-- asserts the notifications read cleanly (one "bemtvi-diff: " prefix, no Lua position
-- noise). The not-a-repo case doubles as the regression test for the fix that runs git
-- in the FILE's directory, not the editor cwd. Run with `bemtvi --test-plugin`.

local diff = require("bemtvi-diff")
local gitmod = require("bemtvi-diff.git")

-- Run a git command in `dir`, awaiting it; fail the test loud on a non-zero exit.
local function git(dir, ...)
  local r = btv.await(btv.run({ cmd = "git", args = { ... }, cwd = dir }))
  if r.code ~= 0 then
    error(("git %s failed: %s"):format(table.concat({ ... }, " "), r.stderr), 0)
  end
  return r
end

-- A fresh repo with one committed file (`a.txt` = "one\ntwo\n").
local function repo_with_commit(dir)
  git(dir, "init", "-q")
  git(dir, "config", "user.email", "t@example.com")
  git(dir, "config", "user.name", "Test")
  btv.await(btv.fs.write(dir .. "/a.txt", "one\ntwo\n"))
  git(dir, "add", "a.txt")
  git(dir, "commit", "-q", "-m", "init")
end

-- `:edit` a path and settle. (The buffer name reaches Lua's current-buffer snapshot
-- right after `:edit` now — `expand("%:p")` reads it.)
local function edit(t, path)
  t:cmd("edit " .. path)
end

-- Run `fn` (kicking off the async git path) and return the plugin's own notification —
-- matched by its "bemtvi-diff:" prefix so a stale `:edit` echo isn't mistaken for it.
local function notify_after(t, fn)
  fn()
  return t:wait_for(function()
    local m = t:message()
    return (m:match("^bemtvi%-diff:") and m) or nil
  end, { tries = 300, interval = 10, message = "bemtvi-diff git: no notification appeared" })
end

btv.test.describe("bemtvi-diff git", function()
  btv.test.before_each(function()
    require("bemtvi-diff").setup({})
  end)
  btv.test.after_each(function()
    diff.close()
  end)

  btv.test.it("head_spec reads HEAD from the file's own repo dir", function(t)
    local dir = btv.test.tempdir()
    repo_with_commit(dir)
    -- head_spec runs git in ctx.cwd; pointing it at the repo dir, its `git show HEAD:a.txt`
    -- must yield the committed content. (If git ran anywhere else, show would fail.)
    local spec = btv.await(gitmod.head_spec({
      file = dir .. "/a.txt",
      bufnr = t:buf(),
      cwd = dir,
    }))
    btv.test.expect(#spec.panes).to_be(2)
    btv.test.expect(spec.panes[1].label).to_be("HEAD")
    btv.test.expect(table.concat(spec.panes[1].lines, "|")).to_be("one|two")
    btv.test.expect(spec.panes[2].buf).to_be(t:buf()) -- the live working-tree buffer
    -- The spec carries its own re-run hook, so `refresh` (`R`) re-reads the blob at HEAD
    -- instead of re-rendering the snapshot the diff was opened with.
    btv.test.expect(type(spec.reload)).to_be("function")
  end)

  btv.test.it("the reload hook re-reads HEAD after a new commit", function(t)
    local dir = btv.test.tempdir()
    repo_with_commit(dir)
    local ctx = { file = dir .. "/a.txt", bufnr = t:buf(), cwd = dir }
    local spec = btv.await(gitmod.head_spec(ctx))
    btv.test.expect(table.concat(spec.panes[1].lines, "|")).to_be("one|two")

    -- Move HEAD on. Re-running the hook must show the NEW blob — the whole point of
    -- refresh being a re-run of the source rather than a re-render of the same lines.
    btv.await(btv.fs.write(dir .. "/a.txt", "one\ntwo\nthree\n"))
    git(dir, "commit", "-q", "-am", "second")
    local again = btv.await(spec.reload())
    btv.test.expect(table.concat(again.panes[1].lines, "|")).to_be("one|two|three")
  end)

  btv.test.it("a file outside any git repo reports 'not a git repository'", function(t)
    -- The editor cwd is this plugin's repo; the file is in /tmp. The OLD code ran git in
    -- the editor cwd and found THIS repo (then failed on `git show`); running it in the
    -- file's dir correctly reports no repo.
    local dir = btv.test.tempdir()
    edit(t, dir .. "/foo.txt")
    btv.test
      .expect(notify_after(t, function()
        diff.git_head()
      end))
      .to_be("bemtvi-diff: not a git repository")
  end)

  btv.test.it("a nameless buffer reports it has no file to diff", function(t)
    t:cmd("enew")
    btv.test
      .expect(notify_after(t, function()
        diff.git_head()
      end))
      .to_be("bemtvi-diff: this buffer has no file to diff")
  end)

  btv.test.it("a file not in HEAD reports no HEAD version", function(t)
    local dir = btv.test.tempdir()
    repo_with_commit(dir)
    edit(t, dir .. "/new.txt") -- in the repo, but never committed
    btv.test
      .expect(notify_after(t, function()
        diff.git_head()
      end))
      .to_be("bemtvi-diff: no HEAD version of new.txt")
  end)
end)
