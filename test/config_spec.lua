-- Config merge + validation. Pure (no editor state), run with `bemtvi --test-plugin`.

local config = require("bemtvi-diff.config")

btv.test.describe("bemtvi-diff.config", function()
  btv.test.it("defaults() hands out an independent copy each call", function()
    local a = config.defaults()
    local b = config.defaults()
    a.sync_scroll = false
    a.keymaps["zz"] = "close"
    btv.test.expect(b.sync_scroll).to_be(true)
    btv.test.expect(b.keymaps["zz"]).to_be_nil()
  end)

  btv.test.it("merges scalars and merges keymaps key-by-key", function()
    local cfg = config.merge(config.defaults(), {
      wrap = true,
      keymaps = { ["gn"] = "next_hunk", ["]c"] = false },
    })
    btv.test.expect(cfg.wrap).to_be(true)
    -- the user's new key is present…
    btv.test.expect(cfg.keymaps["gn"]).to_be("next_hunk")
    -- …their disabled default survives as `false`…
    btv.test.expect(cfg.keymaps["]c"]).to_be(false)
    -- …and untouched defaults remain.
    btv.test.expect(cfg.keymaps["q"]).to_be("close")
  end)

  btv.test.it("ships the resolve maps and validates their action names", function()
    -- merge() runs validate(); it would raise if any default keymap named an unknown
    -- action, so reaching the asserts proves the new actions are registered.
    local cfg = config.merge(config.defaults(), {})
    btv.test.expect(cfg.keymaps["cb"]).to_be("choose_both")
    btv.test.expect(cfg.keymaps["cp"]).to_be("pick_lines")
    btv.test.expect(cfg.keymaps["ca"]).to_be("apply_picked")
    btv.test.expect(cfg.keymaps["cx"]).to_be("clear_picked")
  end)

  btv.test.it("accepts a function as a custom keymap action", function()
    local cfg = config.merge(config.defaults(), { keymaps = { ["g?"] = function() end } })
    btv.test.expect(type(cfg.keymaps["g?"])).to_be("function")
  end)

  btv.test.it("rejects an unknown action name (fails loud)", function()
    btv.test
      .expect(function()
        config.merge(config.defaults(), { keymaps = { ["z"] = "does_not_exist" } })
      end)
      .to_error("unknown action")
  end)

  btv.test.it("rejects an invalid layout", function()
    btv.test
      .expect(function()
        config.merge(config.defaults(), { layout = "diagonal" })
      end)
      .to_error("layout")
  end)

  btv.test.it("rejects a non-boolean flag", function()
    btv.test
      .expect(function()
        config.merge(config.defaults(), { sync_scroll = "yes" })
      end)
      .to_error("sync_scroll")
  end)

  btv.test.it("rejects a non-function on_attach (it would silently never run)", function()
    -- The view layer only calls on_attach when it IS a function, so a wrong-typed value
    -- used to be dropped without a word — the hook never fires and you hunt a ghost.
    btv.test
      .expect(function()
        config.merge(config.defaults(), { on_attach = "nope" })
      end)
      .to_error("on_attach")
    -- nil (the default) and a real function are both fine.
    btv.test.expect(config.merge(config.defaults(), {}).on_attach).to_be_nil()
    btv.test
      .expect(type(config.merge(config.defaults(), { on_attach = function() end }).on_attach))
      .to_be("function")
  end)
end)
