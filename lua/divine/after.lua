local M = {}

---@param path string
---@return string
local function canonical(path) return vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p") end

-- Retain failures per physical script, not per unit: overlap must rethrow a
-- failed source without preventing unrelated successful scripts from being used.
---@type table<string, { active: boolean, error?: string }>
local attempted = {}

---@param paths string[] Package after directories, in unit member order.
---@param pattern string Relative glob without the extension.
---@return nil
local function source(paths, pattern)
  local seen = {}
  for _, script in ipairs(vim.fn.getscriptinfo()) do
    seen[canonical(script.name)] = true
  end
  for _, path in ipairs(paths) do
    -- Match native runtime ordering: all Vimscript, then all Lua, per directory.
    for _, extension in ipairs({ "vim", "lua" }) do
      for _, file in
        ipairs(vim.fn.globpath(vim.fn.escape(path, ","), pattern .. "." .. extension, true, true))
      do
        local key = canonical(file)
        local attempt = attempted[key]
        -- Failed sources also appear in native script history. Check the retained
        -- failure before treating that history as evidence of a completed source.
        if attempt and attempt.error then error(attempt.error, 0) end
        if attempt and attempt.active then
          error("divine: reentry while after script is still loading: " .. key, 0)
        end
        if not seen[key] and not attempted[key] and vim.fn.filereadable(file) == 1 then
          attempt = { active = true }
          attempted[key] = attempt
          local ok, err = xpcall(function()
            vim.cmd.source(vim.fn.fnameescape(file))
          end, debug.traceback)
          attempt.active = false
          if not ok then
            attempt.error = err
            error(err, 0)
          end
          -- A script may source a later sibling itself. Refresh before walking
          -- onward so custom :source work is not repeated by this pass.
          for _, script in ipairs(vim.fn.getscriptinfo()) do
            seen[canonical(script.name)] = true
          end
        end
      end
    end
  end
end

---@param paths string[]
---@return nil
function M.plugins(paths) source(paths, "plugin/**/*") end

---@param paths string[]
---@return nil
function M.ftdetect(paths)
  -- If detection is not initialized, filetype.lua will find these through rtp.
  if (vim.g.did_load_filetypes or 0) == 0 then return end
  vim.cmd.augroup("filetypedetect")
  local ok, err = pcall(source, paths, "ftdetect/*")
  vim.cmd.augroup("END")
  if not ok then error(err, 0) end
end

---@param paths string[] Additional runtime trees, not after directories.
---@return nil
function M.add_runtime_paths(paths)
  if #paths == 0 then return end
  local current, normal, after, seen = vim.opt.runtimepath:get(), {}, {}, {}
  local insertion
  for index, path in ipairs(current) do
    seen[path] = true
    if not insertion and vim.fn.fnamemodify(path, ":t") == "after" then insertion = index end
  end
  for _, path in ipairs(paths) do
    if not seen[path] then
      local target = vim.fn.fnamemodify(path, ":t") == "after" and after or normal
      target[#target + 1] = path
      seen[path] = true
    end
    local tail = path .. "/after"
    if not seen[tail] and vim.fn.isdirectory(tail) == 1 then
      after[#after + 1] = tail
      seen[tail] = true
    end
  end
  insertion = insertion or (#current + 1)
  for index, path in ipairs(normal) do
    table.insert(current, insertion + index - 1, path)
  end
  vim.list_extend(current, after)
  vim.opt.runtimepath = current
end

return M
