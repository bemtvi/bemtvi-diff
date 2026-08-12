-- Live decoration test (Phase 4): opens a diff with a changed line and asserts the
-- extmarks the view paints — the whole-line tint and the intra-line `DiffText` spans —
-- land on the right rows with the right byte ranges. Run with `bemtvi --test-plugin`.

local diff = require("bemtvi-diff")

local function await_ready()
  btv.await(btv.wait_for(function()
    local s = diff.session()
    return s and s._ready
  end, { tries = 200, interval = 5, message = "diff never became ready" }))
  return diff.session()
end

-- The session-namespace extmarks on a pane buffer, as { id, row, col, details } entries.
local function marks(pane, s)
  return btv.buf.extmarks(pane.view:bufnr(), s.ns, 0, -1, { details = true })
end

-- The marks on `row` (0-based) whose details satisfy `pred`.
local function marks_where(pane, s, row, pred)
  local out = {}
  for _, m in ipairs(marks(pane, s)) do
    if m[2] == row and pred(m[4] or {}) then
      out[#out + 1] = m
    end
  end
  return out
end

-- A "same" line then a "foo()" → "bar()" change: row 2 (0-based row 1) is the change.
local function open_change()
  diff.open({
    panes = {
      { label = "old", lines = { "same", "foo()" } },
      { label = "new", lines = { "same", "bar()" } },
    },
  })
  return await_ready()
end

btv.test.describe("bemtvi-diff decorations", function()
  btv.test.before_each(function()
    require("bemtvi-diff").setup({})
  end)
  btv.test.after_each(function()
    diff.close()
  end)

  btv.test.it("tints the whole changed line with DiffChange", function()
    local s = open_change()
    -- The tint is a full-width `line_hl_group` line background (vim's diff look), not a
    -- col..end_col span over the text.
    local tint = marks_where(s.panes[1], s, 1, function(d)
      return d.line_hl_group == "DiffChange"
    end)
    btv.test.expect(#tint).to_be(1)
    btv.test.expect(tint[1][3]).to_be(0) -- anchored at col 0
  end)

  btv.test.it("tints a changed line that is EMPTY (a range mark could not)", function()
    -- The regression guard for the old col..end_col tint: an added blank line has no text
    -- to span, so `end_col` was 0 — a zero-width mark that painted nothing, leaving a real
    -- insertion invisible. A line background has no such hole.
    diff.open({
      panes = {
        { label = "old", lines = { "a", "b" } },
        { label = "new", lines = { "a", "", "b" } },
      },
    })
    local s = await_ready()
    btv.test.expect(btv.buf.lines(s.panes[2].view:bufnr(), 1, 2)[1]).to_be("") -- row 1 is blank
    local tint = marks_where(s.panes[2], s, 1, function(d)
      return d.line_hl_group == "DiffAdd"
    end)
    btv.test.expect(#tint).to_be(1)
  end)

  btv.test.it("paints DiffText over only the changed characters", function()
    local s = open_change()
    -- "foo()" → "bar()": the first three bytes differ on both panes.
    for _, pane in ipairs(s.panes) do
      local text = marks_where(pane, s, 1, function(d)
        return d.hl_group == "DiffText"
      end)
      btv.test.expect(#text).to_be(1)
      btv.test.expect(text[1][3]).to_be(0) -- col 0
      btv.test.expect(text[1][4].end_col).to_be(3) -- through byte 3 ("foo"/"bar")
      btv.test.expect(text[1][4].priority > 100).to_be(true) -- above the line tint
    end
  end)

  btv.test.it("inline = false suppresses the DiffText spans (line tint stays)", function()
    require("bemtvi-diff").setup({ inline = false })
    local s = open_change()
    local text = marks_where(s.panes[1], s, 1, function(d)
      return d.hl_group == "DiffText"
    end)
    btv.test.expect(#text).to_be(0)
    -- The whole-line tint is unaffected.
    local tint = marks_where(s.panes[1], s, 1, function(d)
      return d.line_hl_group == "DiffChange"
    end)
    btv.test.expect(#tint).to_be(1)
  end)

  -- A change with an inserted line on the new side, so the old pane gets a filler row.
  local function open_with_filler()
    diff.open({
      panes = {
        { label = "old", lines = { "same", "tail" } },
        { label = "new", lines = { "same", "extra", "tail" } },
      },
    })
    return await_ready()
  end

  btv.test.it("places a per-hunk gutter sign on changed rows when signs = true", function()
    require("bemtvi-diff").setup({ signs = true })
    local s = open_change() -- row 1 (0-based) is the foo()→bar() change on both panes
    for _, pane in ipairs(s.panes) do
      local sign = marks_where(pane, s, 1, function(d)
        return d.sign_text ~= nil
      end)
      btv.test.expect(#sign).to_be(1)
      btv.test.expect(sign[1][4].sign_text).to_be("~") -- `~` marks a changed line
      btv.test.expect(sign[1][4].sign_hl_group).to_be("BtvDiffSignChange")
    end
  end)

  btv.test.it("signs default off — no sign_text marks", function()
    local s = open_change() -- before_each setup({}) ⇒ signs = false
    local sign = marks_where(s.panes[1], s, 1, function(d)
      return d.sign_text ~= nil
    end)
    btv.test.expect(#sign).to_be(0)
  end)

  btv.test.it("paints the fillchar across a filler (alignment) row", function()
    require("bemtvi-diff").setup({ fillchar = "-" })
    local s = open_with_filler()
    -- The old pane's row 1 (0-based) is the filler opposite the inserted `extra`.
    local fill = marks_where(s.panes[1], s, 1, function(d)
      return d.line_fill ~= nil
    end)
    btv.test.expect(#fill).to_be(1)
    btv.test.expect(fill[1][4].line_fill.text).to_be("-")
    btv.test.expect(fill[1][4].line_fill.hl_group).to_be("BtvDiffFiller")
    -- A real (non-filler) row carries no fill.
    btv.test
      .expect(#marks_where(s.panes[1], s, 0, function(d)
        return d.line_fill ~= nil
      end))
      .to_be(0)
  end)

  btv.test.it("fillchar = '' leaves filler rows blank (no line_fill mark)", function()
    require("bemtvi-diff").setup({ fillchar = "" })
    local s = open_with_filler()
    local fill = marks_where(s.panes[1], s, 1, function(d)
      return d.line_fill ~= nil
    end)
    btv.test.expect(#fill).to_be(0)
  end)
end)
