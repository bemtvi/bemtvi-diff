-- Live rendering test (Phase 2): drives the real editor — opens a 2-pane diff via the
-- public open() API and asserts the panes are laid out and projected. Run with
-- `bemtvi --test-plugin`. The `it` body is async (it may btv.await), so it waits on the
-- session's readiness signal before asserting.

local diff = require("bemtvi-diff")

-- Wait until the open()'d session has finished rendering.
local function await_ready()
  btv.await(btv.wait_for(function()
    local s = diff.session()
    return s and s._ready
  end, { tries = 200, interval = 5, message = "diff never became ready" }))
  return diff.session()
end

btv.test.describe("bemtvi-diff render", function()
  btv.test.after_each(function()
    diff.close()
  end)

  btv.test.it("lays out two panes, projected to equal height with fillers", function()
    diff.open({
      panes = {
        { label = "old", lines = { "same", "old", "tail" } },
        { label = "new", lines = { "same", "new", "extra", "tail" } },
      },
    })
    local s = await_ready()

    btv.test.expect(#s.panes).to_be(2)
    -- Both views exist and are shown in a window.
    btv.test.expect(s.panes[1].view:bufnr() ~= nil).to_be(true)
    btv.test.expect(s.panes[2].view:winid() ~= nil).to_be(true)

    -- The alignment: same / change(old→new) / add(extra) / same → 4 rows. Each pane
    -- is projected to that height (the `a` side gets a filler opposite the insertion).
    local a = btv.buf.lines(s.panes[1].view:bufnr(), 0, -1)
    local b = btv.buf.lines(s.panes[2].view:bufnr(), 0, -1)
    btv.test.expect(#a).to_be(4)
    btv.test.expect(#b).to_be(4)
    btv.test.expect(table.concat(a, "|")).to_be("same|old||tail") -- filler is the blank
    btv.test.expect(table.concat(b, "|")).to_be("same|new|extra|tail")
  end)

  btv.test.it("opens in a dedicated tab so the panes are side by side", function()
    diff.open({
      panes = {
        { label = "l", lines = { "x" } },
        { label = "r", lines = { "y" } },
      },
    })
    local s = await_ready()
    -- The two panes occupy two distinct windows.
    btv.test.expect(s.panes[1].view:winid() ~= s.panes[2].view:winid()).to_be(true)
    -- …and ONLY those two in the diff's own tab — the new tab's initial empty window
    -- was dropped, so the diff tab is a clean 2-up split. Count the CURRENT tab's
    -- windows (btv.tabpage.wins); btv.win.list spans every tab and would also count the
    -- original tab's window we opened the diff from.
    btv.test.expect(#btv.tabpage.wins()).to_be(2)
  end)

  btv.test.it("resolves `path` panes by reading the files (the files source path)", function()
    local dir = btv.test.tempdir()
    btv.await(btv.fs.write(dir .. "/a.txt", "one\ntwo\n"))
    btv.await(btv.fs.write(dir .. "/b.txt", "one\nTWO\n"))
    diff.open({
      panes = {
        { label = "a", path = dir .. "/a.txt" },
        { label = "b", path = dir .. "/b.txt" },
      },
    })
    local s = await_ready()
    local a = btv.buf.lines(s.panes[1].view:bufnr(), 0, -1)
    -- "two" → "TWO" is a change row; both sides stay 2 lines (no filler needed).
    btv.test.expect(table.concat(a, "|")).to_be("one|two")
  end)

  btv.test.it("names each pane (so a pane is not [No Name])", function()
    diff.open({
      panes = {
        { label = "ours", lines = { "x" } },
        { label = "base", lines = { "x" } },
        { label = "theirs", lines = { "x" } },
      },
    })
    local s = await_ready()
    -- The pane label IS the view's name — what the statusline / tab label show.
    btv.test.expect(s.panes[1].view.name).to_be("ours")
    btv.test.expect(s.panes[2].view.name).to_be("base")
    btv.test.expect(s.panes[3].view.name).to_be("theirs")
  end)

  btv.test.it("a hunk jump keeps focus on the pane you jumped from", function()
    diff.open({
      panes = {
        { label = "old", lines = { "a", "b", "c" } },
        { label = "new", lines = { "a", "B", "c" } },
      },
    })
    local s = await_ready()
    -- Read the diff from the RIGHT pane, then jump a hunk. `view:set_cursor` focuses the
    -- view it moves, so goto_row must put focus back where it found it — otherwise every
    -- `]c` teleports you into the left pane and you cannot step through a diff from the
    -- side you are actually reading.
    s.panes[2].view:focus()
    btv.await(btv.wait_for(function()
      return btv.win.current() == s.panes[2].view:winid()
    end, { tries = 100, interval = 5, message = "the right pane never took focus" }))

    require("bemtvi-diff.nav").next_hunk(s)
    btv.await(btv.wait_for(function()
      return s:cursor_row() == 2
    end, { tries = 100, interval = 5, message = "the hunk jump never landed" }))
    btv.test.expect(btv.win.current()).to_be(s.panes[2].view:winid())
  end)

  btv.test.it("layout = 'horizontal' stacks the panes instead of splitting sideways", function()
    -- `layout` was validated and then silently ignored — every diff came out vertical.
    -- Measure the first pane both ways: stacked it spans the FULL width and shares the
    -- height; side by side it is the other way round.
    local function first_pane_size(layout)
      require("bemtvi-diff").setup({ layout = layout })
      diff.open({
        panes = {
          { label = "l", lines = { "x", "y" } },
          { label = "r", lines = { "x", "Y" } },
        },
      })
      local win = await_ready().panes[1].view:winid()
      local w, h = btv.win.width(win), btv.win.height(win)
      diff.close()
      return w, h
    end
    local vw, vh = first_pane_size("vertical")
    local hw, hh = first_pane_size("horizontal")
    btv.test.expect(hw > vw).to_be(true) -- stacked ⇒ full width, not half
    btv.test.expect(hh < vh).to_be(true) -- …and half the height, not full
    require("bemtvi-diff").setup({}) -- back to the defaults for the rest of the suite
  end)

  btv.test.it("`:q` on one pane tears down the whole diff", function()
    diff.open({
      panes = {
        { label = "ours", lines = { "x" } },
        { label = "base", lines = { "x" } },
        { label = "theirs", lines = { "x" } },
      },
    })
    local s = await_ready()
    btv.test.expect(#s.panes).to_be(3)

    -- Quit one pane the way the user does. on_close fires → the session closes ALL
    -- three panes, leaving its dedicated tab and returning to the original.
    s.panes[2].view:focus()
    vim.cmd("q")
    btv.await(btv.wait_for(function()
      return diff.session() == nil
    end, { tries = 200, interval = 5, message = "closing a pane did not tear the diff down" }))
    btv.test.expect(diff.session()).to_be(nil)
  end)
end)
