-- The pure conflict-marker parser. Run with `bemtvi --test-plugin`. No editor state.

local conflict = require("bemtvi-diff.conflict")

local DIFF3 = {
  "common top",
  "<<<<<<< HEAD",
  "ours line",
  "||||||| merged common ancestor",
  "base line",
  "=======",
  "theirs line",
  ">>>>>>> feature-branch",
  "common bottom",
}

local MERGE = {
  "top",
  "<<<<<<< HEAD",
  "ours",
  "=======",
  "theirs",
  ">>>>>>> branch",
  "bot",
}

btv.test.describe("bemtvi-diff.conflict", function()
  btv.test.it("reports no conflict on a clean file", function()
    local p = conflict.parse({ "a", "b", "======= not a marker outside a conflict" })
    btv.test.expect(p.has_conflict).to_be(false)
    btv.test.expect(p.count).to_be(0)
  end)

  btv.test.it("parses diff3 style into three full sides with context", function()
    local p = conflict.parse(DIFF3)
    btv.test.expect(p.has_conflict).to_be(true)
    btv.test.expect(p.diff3).to_be(true)
    btv.test.expect(p.count).to_be(1)
    btv.test.expect(p.ours_label).to_be("HEAD")
    btv.test.expect(p.theirs_label).to_be("feature-branch")
    -- each side is the whole file with its section substituted (context preserved)
    btv.test.expect(table.concat(p.ours, "|")).to_be("common top|ours line|common bottom")
    btv.test.expect(table.concat(p.base, "|")).to_be("common top|base line|common bottom")
    btv.test.expect(table.concat(p.theirs, "|")).to_be("common top|theirs line|common bottom")
  end)

  btv.test.it("parses plain merge style with no base (2-way)", function()
    local p = conflict.parse(MERGE)
    btv.test.expect(p.diff3).to_be(false)
    btv.test.expect(p.base).to_be_nil()
    btv.test.expect(table.concat(p.ours, "|")).to_be("top|ours|bot")
    btv.test.expect(table.concat(p.theirs, "|")).to_be("top|theirs|bot")
  end)

  btv.test.it("spec() builds 3 panes for diff3, 2 for plain merge", function()
    btv.test.expect(#conflict.spec(DIFF3, "f").panes).to_be(3)
    btv.test.expect(#conflict.spec(MERGE, "f").panes).to_be(2)
  end)

  btv.test.it("spec() stamps the file's filetype on every pane", function()
    for _, pane in ipairs(conflict.spec(DIFF3, "f", "lua").panes) do
      btv.test.expect(pane.filetype).to_be("lua")
    end
    for _, pane in ipairs(conflict.spec(MERGE, "f", "rust").panes) do
      btv.test.expect(pane.filetype).to_be("rust")
    end
  end)

  btv.test.it("spec() returns nil + a reason for a clean file", function()
    local spec, reason = conflict.spec({ "a", "b" }, "f")
    btv.test.expect(spec).to_be_nil()
    btv.test.expect(reason).to_be("no conflict markers found")
  end)

  btv.test.it("records each region's marker line range and section contents", function()
    -- The diff3 block sits at lines 2 (<<<) .. 8 (>>>) of DIFF3, with one-line sections.
    local p = conflict.parse(DIFF3)
    btv.test.expect(#p.regions).to_be(1)
    local r = p.regions[1]
    btv.test.expect(r.first).to_be(2)
    btv.test.expect(r.last).to_be(8)
    btv.test.expect(table.concat(r.ours, "|")).to_be("ours line")
    btv.test.expect(table.concat(r.base, "|")).to_be("base line")
    btv.test.expect(table.concat(r.theirs, "|")).to_be("theirs line")
    -- The reconstructed sides are "common top | <section> | common bottom", so each
    -- one-line section sits at reconstructed line 2 of its side.
    btv.test.expect(r.recon.ours.from).to_be(2)
    btv.test.expect(r.recon.ours.to).to_be(2)
    btv.test.expect(r.recon.base.from).to_be(2)
    btv.test.expect(r.recon.theirs.to).to_be(2)
  end)

  btv.test.it("an empty section's reconstructed span is from > to", function()
    -- theirs deletes the line: its section is empty, so recon.theirs is an empty span.
    local p = conflict.parse({
      "top",
      "<<<<<<< HEAD",
      "kept",
      "=======",
      ">>>>>>> b",
      "bot",
    })
    local r = p.regions[1]
    btv.test.expect(r.recon.ours.from).to_be(2)
    btv.test.expect(r.recon.ours.to).to_be(2)
    -- theirs has no line between ======= and >>>>>>>: from (2) > to (1).
    btv.test.expect(r.recon.theirs.from > r.recon.theirs.to).to_be(true)
  end)

  btv.test.it("a plain merge region carries no base", function()
    local r = conflict.parse(MERGE).regions[1]
    btv.test.expect(r.first).to_be(2) -- <<<<<<< HEAD
    btv.test.expect(r.last).to_be(6) -- >>>>>>> branch
    btv.test.expect(r.base).to_be_nil()
    btv.test.expect(table.concat(r.ours, "|")).to_be("ours")
    btv.test.expect(table.concat(r.theirs, "|")).to_be("theirs")
  end)

  btv.test.it("tracks two conflict regions with their own line ranges", function()
    local two = {
      "top",
      "<<<<<<< HEAD",
      "ours1",
      "=======",
      "theirs1",
      ">>>>>>> b",
      "mid",
      "<<<<<<< HEAD",
      "ours2",
      "=======",
      "theirs2",
      ">>>>>>> b",
      "bot",
    }
    local p = conflict.parse(two)
    btv.test.expect(p.count).to_be(2)
    btv.test.expect(#p.regions).to_be(2)
    btv.test.expect(p.regions[1].first).to_be(2)
    btv.test.expect(p.regions[1].last).to_be(6)
    btv.test.expect(p.regions[2].first).to_be(8)
    btv.test.expect(p.regions[2].last).to_be(12)
    btv.test.expect(table.concat(p.regions[2].theirs, "|")).to_be("theirs2")
  end)

  btv.test.it("spec() carries the resolve map (regions + diff3 flag)", function()
    local spec = conflict.spec(DIFF3, "f")
    btv.test.expect(spec.resolve ~= nil).to_be(true)
    btv.test.expect(spec.resolve.diff3).to_be(true)
    btv.test.expect(#spec.resolve.regions).to_be(1)
    btv.test.expect(conflict.spec(MERGE, "f").resolve.diff3).to_be(false)
  end)

  btv.test.it("fails loud on an unterminated conflict", function()
    btv.test
      .expect(function()
        conflict.parse({ "<<<<<<< HEAD", "ours" })
      end)
      .to_error("unterminated")
  end)

  btv.test.it("fails loud on a nested <<<<<<< inside an open conflict", function()
    -- git never writes nested conflicts, so this is a hand-mangled / half-resolved file.
    -- Swallowing the marker as ordinary content would build sides that don't match the
    -- markers — and `choose_*` would then write those wrong lines back over the file.
    btv.test
      .expect(function()
        conflict.parse({
          "<<<<<<< HEAD",
          "ours",
          "<<<<<<< HEAD",
          "=======",
          "theirs",
          ">>>>>>> b",
        })
      end)
      .to_error("nested")
  end)
end)
