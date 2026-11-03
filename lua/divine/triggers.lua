local M = {}

function M.register(_)
  -- TODO(EVENT): load on events and hand off the initial event.
  -- TODO(COMMAND): load before running the requested command, preserving its invocation.
  -- TODO(FILETYPE): attach to matching buffers, including the initial buffer.
  -- TODO(KEY): load and hand off the original key operation, separately from command mappings.
  -- TODO(MODULE): load before resolving the requested Lua module; match rules are undecided.
  error("divine prototype: lazy-trigger registration is not implemented", 0)
end

return M
