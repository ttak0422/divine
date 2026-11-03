local M = {}

-- Internal prototype only; generated names and the consumer API are TODO(API).
function M.load_one(name, hooks)
  assert(type(name) == "string" and name ~= "", "a package directory name is required")
  hooks = hooks or {}
  if hooks.before then hooks.before() end
  (hooks.load or vim.cmd.packadd)(name)
  if hooks.after then hooks.after() end
end

-- TODO(PACKAGING): all managed packages and dependencies belong in opt.
-- TODO(STARTUP): explicitly load non-delayed entries during init, without moving them to start.
-- TODO(GENERATION): connect Lua source/config files to the actions above.
-- after/plugin is intentionally not sourced here; it is not the after action.
return M
