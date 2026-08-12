-- The public Lua API surface: spec validation (how a plugin "sends a diff") plus the
-- git module's pure helpers. Run with `bemtvi --test-plugin`. No live session opened.

local diff = require("bemtvi-diff")
local git = require("bemtvi-diff.git")

btv.test.describe("bemtvi-diff.validate_spec", function()
  btv.test.it("accepts a 2-pane and a 3-pane spec", function()
    btv.test
      .expect(diff.validate_spec({
        panes = { { lines = { "a" } }, { lines = { "b" } } },
      })).never
      .to_be_nil()
    btv.test
      .expect(diff.validate_spec({
        panes = { { lines = { "a" } }, { lines = { "b" } }, { lines = { "c" } } },
      })).never
      .to_be_nil()
  end)

  btv.test.it("rejects the wrong pane count", function()
    btv.test
      .expect(function()
        diff.validate_spec({ panes = { { lines = { "a" } } } })
      end)
      .to_error("2 or 3 panes")
  end)

  btv.test.it("rejects a pane without exactly one content source", function()
    btv.test
      .expect(function()
        diff.validate_spec({ panes = { { label = "x" }, { lines = { "b" } } } })
      end)
      .to_error("exactly one")
    btv.test
      .expect(function()
        diff.validate_spec({ panes = { { lines = { "a" }, path = "/tmp/x" }, { lines = { "b" } } } })
      end)
      .to_error("exactly one")
  end)
end)

btv.test.describe("bemtvi-diff.git helpers", function()
  btv.test.it("to_lines splits and drops the trailing newline's empty", function()
    btv.test.expect(table.concat(git.to_lines("a\nb\n"), "|")).to_be("a|b")
    btv.test.expect(#git.to_lines("")).to_be(0)
    -- Without a trailing newline the last line is content, not an artifact…
    btv.test.expect(table.concat(git.to_lines("a\nb"), "|")).to_be("a|b")
    -- …and a file that genuinely ENDS in a blank line keeps it (only the final newline's
    -- own empty is dropped).
    btv.test.expect(table.concat(git.to_lines("a\n\n"), "|")).to_be("a|")
    -- One splitter serves every content source (a git blob, a `path` pane's file read),
    -- so a trailing newline can't mean "an extra blank line" on one side of a diff only.
    btv.test.expect(git.to_lines).to_be(require("bemtvi-diff.diff").to_lines)
  end)

  btv.test.it("repo_relative strips the toplevel prefix (with or without slash)", function()
    btv.test.expect(git.repo_relative("/repo/src/a.rs", "/repo")).to_be("src/a.rs")
    btv.test.expect(git.repo_relative("/repo/src/a.rs", "/repo/")).to_be("src/a.rs")
  end)
end)
