-- The default colours come from the active theme (btv.hl.palette, blended into its
-- background for the line tints) and follow a theme switch; a theme's own Diff*
-- groups and the user's overrides win.
local diff = require("bemtvi-diff")

local function hex(group, attr)
  local d = btv.hl.get(0, { name = group, link = false })
  return d[attr] and string.format("#%06x", d[attr]) or nil
end

-- A minimal theme: the groups the palette reads, and nothing of the diff's own.
local function theme(t, colors)
  t:cmd("hi clear")
  btv.hl.define(0, "Normal", { fg = colors.fg, bg = colors.bg })
  btv.hl.define(0, "Added", { fg = colors.green })
  btv.hl.define(0, "DiagnosticError", { fg = colors.red })
  btv.hl.define(0, "Type", { fg = colors.yellow })
  btv.hl.define(0, "Function", { fg = colors.blue })
  btv.hl.define(0, "Comment", { fg = colors.muted })
  t:cmd("doautocmd ColorScheme")
end

local DARK = {
  fg = "#dddddd",
  bg = "#101010",
  green = "#00c000",
  red = "#c00000",
  yellow = "#c0c000",
  blue = "#0000c0",
  muted = "#808080",
}
local LIGHT = {
  fg = "#202020",
  bg = "#f0f0f0",
  green = "#008000",
  red = "#800000",
  yellow = "#808000",
  blue = "#000080",
  muted = "#606060",
}

btv.test.describe("bemtvi-diff highlights", function()
  btv.test.it("derives its defaults from the active theme", function(t)
    theme(t, DARK)
    diff.setup()
    local p = btv.hl.palette()
    btv.test.expect(hex("BtvDiffSignAdd", "fg")).to_be(p.green)
    btv.test.expect(hex("BtvDiffSignDelete", "fg")).to_be(p.red)
    btv.test.expect(hex("BtvDiffSignChange", "fg")).to_be(p.yellow)
    btv.test.expect(hex("BtvDiffSignPick", "fg")).to_be(p.blue)
    -- The line tints are the accents faded into the theme's background.
    btv.test.expect(hex("DiffAdd", "bg")).to_be(btv.hl.blend(p.green, p.bg, 0.2))
    btv.test.expect(hex("DiffDelete", "bg")).to_be(btv.hl.blend(p.red, p.bg, 0.2))
    btv.test.expect(hex("BtvDiffPick", "bg")).to_be(btv.hl.blend(p.blue, p.bg, 0.25))
  end)

  btv.test.it("follows a theme switch, light flavour included", function(t)
    theme(t, DARK)
    diff.setup()
    local dark_add = hex("DiffAdd", "bg")
    theme(t, LIGHT)
    local p = btv.hl.palette()
    btv.test.expect(hex("BtvDiffSignAdd", "fg")).to_be(LIGHT.green)
    btv.test.expect(hex("DiffAdd", "bg")).to_be(btv.hl.blend(p.green, p.bg, 0.2))
    btv.test.expect(hex("DiffAdd", "bg")).never.to_be(dark_add)
  end)

  btv.test.it("leaves a theme's own Diff* groups alone", function(t)
    theme(t, DARK)
    btv.hl.define(0, "DiffAdd", { bg = "#123456" })
    diff.setup()
    btv.test.expect(hex("DiffAdd", "bg")).to_be("#123456")
  end)

  btv.test.it("lets the user's override win, across a theme switch", function(t)
    theme(t, DARK)
    diff.setup({ highlights = { BtvDiffSignAdd = { fg = "#abcdef" } } })
    btv.test.expect(hex("BtvDiffSignAdd", "fg")).to_be("#abcdef")
    theme(t, LIGHT)
    btv.test.expect(hex("BtvDiffSignAdd", "fg")).to_be("#abcdef")
  end)
end)
