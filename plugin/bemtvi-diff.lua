-- Auto-loaded when the plugin is on the runtimepath (sourced from `plugin/` like a
-- neovim plugin). Registers the :DiffGit / :DiffConflict commands with defaults so
-- it works out of the box; setup() is idempotent, so a user calling
-- require("bemtvi-diff").setup({...}) from their init.lua just re-applies options.
require("bemtvi-diff").setup({})
