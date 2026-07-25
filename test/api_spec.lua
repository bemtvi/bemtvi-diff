-- The public Lua API surface: spec validation (how a plugin "sends a diff") plus the
-- git module's pure helpers. Run with `nxvim --test-plugin`. No live session opened.

local diff = require("nxvim-diff")
local git = require("nxvim-diff.git")

nx.test.describe("nxvim-diff.validate_spec", function()
  nx.test.it("accepts a 2-pane and a 3-pane spec", function()
    nx.test
      .expect(diff.validate_spec({
        panes = { { lines = { "a" } }, { lines = { "b" } } },
      })).never
      .to_be_nil()
    nx.test
      .expect(diff.validate_spec({
        panes = { { lines = { "a" } }, { lines = { "b" } }, { lines = { "c" } } },
      })).never
      .to_be_nil()
  end)

  nx.test.it("rejects the wrong pane count", function()
    nx.test
      .expect(function()
        diff.validate_spec({ panes = { { lines = { "a" } } } })
      end)
      .to_error("2 or 3 panes")
  end)

  nx.test.it("rejects a pane without exactly one content source", function()
    nx.test
      .expect(function()
        diff.validate_spec({ panes = { { label = "x" }, { lines = { "b" } } } })
      end)
      .to_error("exactly one")
    nx.test
      .expect(function()
        diff.validate_spec({ panes = { { lines = { "a" }, path = "/tmp/x" }, { lines = { "b" } } } })
      end)
      .to_error("exactly one")
  end)
end)

nx.test.describe("nxvim-diff.git helpers", function()
  nx.test.it("to_lines splits and drops the trailing newline's empty", function()
    nx.test.expect(table.concat(git.to_lines("a\nb\n"), "|")).to_be("a|b")
    nx.test.expect(#git.to_lines("")).to_be(0)
    -- Without a trailing newline the last line is content, not an artifact…
    nx.test.expect(table.concat(git.to_lines("a\nb"), "|")).to_be("a|b")
    -- …and a file that genuinely ENDS in a blank line keeps it (only the final newline's
    -- own empty is dropped).
    nx.test.expect(table.concat(git.to_lines("a\n\n"), "|")).to_be("a|")
    -- One splitter serves every content source (a git blob, a `path` pane's file read),
    -- so a trailing newline can't mean "an extra blank line" on one side of a diff only.
    nx.test.expect(git.to_lines).to_be(require("nxvim-diff.diff").to_lines)
  end)

  nx.test.it("repo_relative strips the toplevel prefix (with or without slash)", function()
    nx.test.expect(git.repo_relative("/repo/src/a.rs", "/repo")).to_be("src/a.rs")
    nx.test.expect(git.repo_relative("/repo/src/a.rs", "/repo/")).to_be("src/a.rs")
  end)
end)
