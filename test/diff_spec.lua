-- The pure line-diff engine: alignment, hunks, and per-pane projection. Run with
-- `bemtvi --test-plugin`. No editor state — just arrays in, alignment out.

local diff = require("bemtvi-diff.diff")

local function kinds(rows)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = r.kind
  end
  return table.concat(out, ",")
end

btv.test.describe("bemtvi-diff.diff", function()
  btv.test.it("identical inputs are all `same` with no hunks", function()
    local r = diff.compute({ "a", "b" }, { "a", "b" })
    btv.test.expect(kinds(r.rows)).to_be("same,same")
    btv.test.expect(#r.hunks).to_be(0)
  end)

  btv.test.it("a pure insertion is an `add` row in one hunk", function()
    local r = diff.compute({ "a" }, { "a", "b" })
    btv.test.expect(kinds(r.rows)).to_be("same,add")
    btv.test.expect(#r.hunks).to_be(1)
    btv.test.expect(r.hunks[1].first).to_be(2)
    btv.test.expect(r.hunks[1].last).to_be(2)
  end)

  btv.test.it("a pure deletion is a `del` row", function()
    local r = diff.compute({ "a", "b" }, { "a" })
    btv.test.expect(kinds(r.rows)).to_be("same,del")
  end)

  btv.test.it("a replaced line pairs into a `change` row", function()
    local r = diff.compute({ "a", "b", "c" }, { "a", "x", "c" })
    btv.test.expect(kinds(r.rows)).to_be("same,change,same")
    btv.test.expect(#r.hunks).to_be(1)
    btv.test.expect(r.hunks[1].first).to_be(2)
  end)

  btv.test.it("projects each side to equal height with fillers", function()
    -- a → a,b : the `a` pane needs a filler opposite the inserted `b`.
    local r = diff.compute({ "a" }, { "a", "b" })
    local pa = diff.project(r.rows, "a")
    local pb = diff.project(r.rows, "b")
    btv.test.expect(#pa).to_be(#pb) -- equal height ⇒ rows line up on screen
    btv.test.expect(pa[1].line).to_be(1)
    btv.test.expect(pa[2].filler).to_be(true)
    btv.test.expect(pb[2].line).to_be(2)
  end)

  btv.test.it("inline char-diff marks only the changed spans", function()
    -- "foo()" → "bar()": the first three chars differ, "()" is the common tail.
    local sp = diff.inline("foo()", "bar()")
    btv.test.expect(sp.a).to_equal({ { 0, 3 } })
    btv.test.expect(sp.b).to_equal({ { 0, 3 } })
  end)

  btv.test.it("inline reports a mid-line insertion as a b-only span", function()
    -- "ac" → "abc": 'b' inserted at byte 1 on the b side; the a side is unchanged.
    local sp = diff.inline("ac", "abc")
    btv.test.expect(sp.a).to_equal({})
    btv.test.expect(sp.b).to_equal({ { 1, 2 } })
  end)

  btv.test.it("inline ranges are byte offsets over whole UTF-8 characters", function()
    -- "café" → "cafe": only the last char differs. 'é' is 2 bytes (3..5), 'e' is 1 (3..4)
    -- — the span must not split the multibyte character.
    local sp = diff.inline("café", "cafe")
    btv.test.expect(sp.a).to_equal({ { 3, 5 } })
    btv.test.expect(sp.b).to_equal({ { 3, 4 } })
  end)

  btv.test.it("inline coalesces adjacent changed characters into one span", function()
    -- "abcd" → "axyd": 'bc' → 'xy' is one contiguous edit, not two single-char spans.
    local sp = diff.inline("abcd", "axyd")
    btv.test.expect(sp.a).to_equal({ { 1, 3 } })
    btv.test.expect(sp.b).to_equal({ { 1, 3 } })
  end)
end)

-- Perf guards: prefix/suffix trim + the cell-cap coarse fallback (Phase 7). The trim
-- must not change the alignment for ordinary edits; the cap must still produce a correct
-- (if coarse) result past the limit instead of building the big LCS table.
btv.test.describe("bemtvi-diff.diff perf guards", function()
  local function kinds_of(a, b)
    local out = {}
    for _, r in ipairs(diff.compute(a, b).rows) do
      out[#out + 1] = r.kind
    end
    return table.concat(out, ",")
  end

  btv.test.it("trimming a shared prefix/suffix gives the same alignment as a full LCS", function()
    -- A change buried inside identical context — the common case the trim optimizes.
    local a = { "h1", "h2", "h3", "old", "f1", "f2" }
    local b = { "h1", "h2", "h3", "new", "f1", "f2" }
    btv.test.expect(kinds_of(a, b)).to_be("same,same,same,change,same,same")
  end)

  btv.test.it("an internal match inside the middle is still found under the cap", function()
    -- middle a=[X,c,Y] vs b=[c] (between shared p…s): the exact LCS keeps `c` as `same`.
    local a = { "p", "X", "c", "Y", "s" }
    local b = { "p", "c", "s" }
    btv.test.expect(kinds_of(a, b)).to_be("same,del,same,del,same")
  end)

  btv.test.it("past the cell cap the middle falls back to a coarse block-replace", function()
    local saved = diff.LCS_CELL_LIMIT
    diff.LCS_CELL_LIMIT = 2 -- middle is 3×1 = 3 cells > 2 ⇒ coarse path
    local a = { "p", "X", "c", "Y", "s" }
    local b = { "p", "c", "s" }
    -- Coarse del-run+add-run: X→c pairs into a change, then c/Y drop as dels (no LCS, so
    -- the internal `c` match is NOT recovered — the trade for staying bounded).
    btv.test.expect(kinds_of(a, b)).to_be("same,change,del,del,same")
    diff.LCS_CELL_LIMIT = saved
  end)

  btv.test.it("inline trims the shared head/tail before the char LCS", function()
    -- A one-character edit buried in a long line: the trim leaves a 1×1 middle, so the
    -- span stays exact even with the cap down at a single cell (an untrimmed LCS over the
    -- whole line would be 2001² cells).
    local saved = diff.INLINE_CELL_LIMIT
    diff.INLINE_CELL_LIMIT = 1
    local head, tail = ("x"):rep(1000), ("y"):rep(1000)
    local sp = diff.inline(head .. "a" .. tail, head .. "b" .. tail)
    btv.test.expect(sp.a).to_equal({ { 1000, 1001 } })
    btv.test.expect(sp.b).to_equal({ { 1000, 1001 } })
    diff.INLINE_CELL_LIMIT = saved
  end)

  btv.test.it("past the inline cap the differing middle becomes one coarse span", function()
    local saved = diff.INLINE_CELL_LIMIT
    diff.INLINE_CELL_LIMIT = 1 -- the middle is 2×3 = 6 cells > 1 ⇒ coarse path
    -- "S|ab|_E" vs "S|xyz|_E": the shared `S` head and `_E` tail are trimmed, then the
    -- middle degrades to one span per side rather than a per-character alignment.
    local sp = diff.inline("Sab_E", "Sxyz_E")
    btv.test.expect(sp.a).to_equal({ { 1, 3 } })
    btv.test.expect(sp.b).to_equal({ { 1, 4 } })
    diff.INLINE_CELL_LIMIT = saved
  end)

  btv.test.it("inline on two huge lines stays fast (the no-freeze guard)", function()
    -- The regression guard for the once-uncapped character LCS: two 40k-character lines
    -- sharing no head or tail are 1.6 BILLION cells — a hang, on a diff that should render
    -- instantly. Bounded, it must return promptly and still mark the whole line changed.
    local a, b = ("ab"):rep(20000), ("cd"):rep(20000)
    local started = os.clock()
    local sp = diff.inline(a, b)
    btv.test.expect(os.clock() - started < 2.0).to_be(true)
    btv.test.expect(sp.a).to_equal({ { 0, 40000 } })
    btv.test.expect(sp.b).to_equal({ { 0, 40000 } })
  end)
end)

-- 3-way (diff3) alignment: a center-anchored merge of two 2-way diffs against `base`.
btv.test.describe("bemtvi-diff.diff 3-way", function()
  -- The text each pane shows for an alignment, via its projection (filler → "·").
  local function shown(rows, role, lines)
    local out = {}
    for _, e in ipairs(diff.project3(rows, role)) do
      out[#out + 1] = e.filler and "·" or lines[e.line]
    end
    return table.concat(out, "|")
  end

  btv.test.it("identical sides are all `same` with no hunks", function()
    local r = diff.compute3({ "a", "b" }, { "a", "b" }, { "a", "b" })
    btv.test.expect(kinds(r.rows)).to_be("same,same")
    btv.test.expect(#r.hunks).to_be(0)
  end)

  btv.test.it("each side modifying a different line aligns both on the base row", function()
    -- base a,b,c ; ours changes b→B ; theirs changes c→C.
    local base, ours, theirs = { "a", "b", "c" }, { "a", "B", "c" }, { "a", "b", "C" }
    local r = diff.compute3(base, ours, theirs)
    btv.test.expect(kinds(r.rows)).to_be("same,change,change")
    -- one contiguous hunk over the two changed rows
    btv.test.expect(#r.hunks).to_be(1)
    btv.test.expect(r.hunks[1].first).to_be(2)
    btv.test.expect(r.hunks[1].last).to_be(3)
    -- every pane is the same height, lines aligned by base row
    btv.test.expect(shown(r.rows, "ours", ours)).to_be("a|B|c")
    btv.test.expect(shown(r.rows, "base", base)).to_be("a|b|c")
    btv.test.expect(shown(r.rows, "theirs", theirs)).to_be("a|b|C")
    -- the changed cells carry the `change` kind; unchanged cells carry none
    local po = diff.project3(r.rows, "ours")
    btv.test.expect(po[2].kind).to_be("change")
    btv.test.expect(po[3].kind).to_be_nil()
  end)

  btv.test.it("a side insertion is an `add` row with fillers on the other panes", function()
    -- ours appends z ; theirs deletes the leading x.
    local base, ours, theirs = { "x", "y" }, { "x", "y", "z" }, { "y" }
    local r = diff.compute3(base, ours, theirs)
    -- x: theirs deleted it (change row) ; y: untouched ; z: ours inserted it (change row)
    btv.test.expect(kinds(r.rows)).to_be("change,same,change")
    btv.test.expect(#r.hunks).to_be(2)
    -- center-anchored: each pane fills opposite the others' edits
    btv.test.expect(shown(r.rows, "ours", ours)).to_be("x|y|z")
    btv.test.expect(shown(r.rows, "base", base)).to_be("x|y|·")
    btv.test.expect(shown(r.rows, "theirs", theirs)).to_be("·|y|·")
    -- the insertion cell is tagged `add`; the deletion shows as a base-side `change` tint
    local po, pb = diff.project3(r.rows, "ours"), diff.project3(r.rows, "base")
    btv.test.expect(po[3].kind).to_be("add")
    btv.test.expect(pb[1].kind).to_be("change")
  end)
end)
