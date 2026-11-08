-- These describe the runtime plan, not the Nix configuration shorthand.
---@alias divine.NodeId string
---@alias divine.UnitId string
---@alias divine.Hook fun()
---@alias divine.LoadHook fun(name: string)
---@alias divine.UnitState 'unloaded'|'preparing'|'configuring'|'loading'|'loaded'|'failed'

---@class divine.Hooks
---@field before? divine.Hook
---@field load? divine.LoadHook Replaces ordinary packadd, not SCC preparation.
---@field after? divine.Hook Runs after managed opt-in after/plugin.

---@class divine.Node: divine.Hooks, divine.TriggerNode
---@field name string Package directory name, not a Lua module name.
---@field after_path? string Package after directory; explicit loadAfter opt-in.
---@field triggers? divine.Triggers Normalized lists; omission means no triggers.

---@class divine.Unit
---@field id divine.UnitId
---@field members divine.NodeId[] Nonempty; members share one SCC load lifecycle.
---@field dependencies divine.UnitId[] Prerequisite units in the acyclic unit graph.
---@field configurations? string[] Ordered singleton/group configuration identities.

---@class divine.Plan
---@field nodes table<divine.NodeId, divine.Node>
---@field units divine.Unit[]
---@field startup_units? divine.UnitId[]
---@field startup? divine.Hook Runs after non-key registration, before startup units.
---@field configurations? table<string, divine.Configuration>

---@class divine.Configuration: divine.Hooks, divine.TriggerNode
---@field members divine.NodeId[] Ordered packages sharing these hooks.

local M = {}

-- Internal prototype only; generated names and the consumer API remain proposed.
---@param name string Nonempty package directory name.
---@param hooks? divine.Hooks
---@return nil
function M.load_one(name, hooks)
  assert(type(name) == "string" and name ~= "", "a package directory name is required")
  hooks = hooks or {}
  if hooks.before then hooks.before() end
  (hooks.load or vim.cmd.packadd)(name)
  if hooks.after then hooks.after() end
end

---@param plan divine.Plan
---@return table<divine.UnitId, divine.Unit> units
---@return table<divine.NodeId, divine.UnitId> node_units
local function index_plan(plan)
  -- The compiler owns plan shape, package names, callbacks and SCC DAG validity.
  ---@type table<divine.UnitId, divine.Unit>, table<divine.NodeId, divine.UnitId>
  local units, node_units = {}, {}
  for _, unit in ipairs(plan.units) do
    units[unit.id] = unit
    for _, id in ipairs(unit.configurations or unit.members) do
      node_units[id] = unit.id
    end
  end
  return units, node_units
end

---@param plan divine.Plan Compiler-produced plan; not a user configuration interface.
---@return divine.Controller controller
function M.setup(plan)
  local units, node_units = index_plan(plan)
  local definitions = vim.tbl_extend("error", {}, plan.nodes, plan.configurations or {})
  ---@type table<divine.NodeId, boolean>, table<divine.NodeId, boolean>, table<divine.NodeId, string>
  local prepared, loaded, package_errors = {}, {}, {}
  ---@type table<divine.NodeId, boolean>
  local loading = {}
  ---@class divine.Controller: divine.TriggerController
  ---@field states table<divine.UnitId, divine.UnitState>
  ---@field errors table<divine.UnitId, string> Failure messages exist only for failed units.
  ---@field node_units table<divine.NodeId, divine.UnitId>
  ---@field load_unit fun(id: divine.UnitId) Loads or rethrows a retained failure.
  local controller = { states = {}, errors = {}, node_units = node_units }
  ---@type divine.Cleanup?
  local cleanup
  for id in pairs(units) do
    controller.states[id] = "unloaded"
  end

  ---@param id divine.UnitId
  ---@param err any
  ---@return nil
  local function retain_failure(id, err)
    controller.states[id] = "failed"
    controller.errors[id] = "divine: unit "
      .. id
      .. " failed; partial effects cannot be retried:\n"
      .. tostring(err)
  end

  ---@param id divine.UnitId
  ---@return nil
  function controller.load_unit(id)
    local unit = assert(units[id], "divine: unknown unit: " .. tostring(id))
    local state = controller.states[id]
    if state == "failed" then error(controller.errors[id], 0) end
    if state == "loaded" then return end
    -- Prepared SCC members can require one another without recursively loading.
    if state == "configuring" or state == "loading" then return end
    assert(state == "unloaded", "divine: reentry before runtime preparation: " .. id)
    controller.states[id] = "preparing"
    local ok, err = xpcall(function()
      for _, dependency in ipairs(unit.dependencies) do
        controller.load_unit(dependency)
      end
      for _, member in ipairs(unit.members) do
        if package_errors[member] then error(package_errors[member], 0) end
        assert(not loading[member], "divine: reentry while shared package is loading: " .. member)
        if not prepared[member] then
          vim.cmd.packadd({ plan.nodes[member].name, bang = true })
          prepared[member] = true
        end
      end
      local configuration_ids = unit.configurations or unit.members
      if cleanup then
        for _, member in ipairs(configuration_ids) do
          cleanup(member)
        end
      end
      controller.states[id] = "configuring"
      for _, member in ipairs(configuration_ids) do
        local hook = definitions[member].before
        if hook then hook() end
      end
      controller.states[id] = "loading"
      for _, configuration_id in ipairs(configuration_ids) do
        local definition = definitions[configuration_id]
        for _, member in ipairs(definition.members or { configuration_id }) do
          if package_errors[member] then error(package_errors[member], 0) end
          if not loaded[member] then
            -- A different configuration cannot finish while this physical
            -- load is still executing. Same-unit prepared reentry returns above.
            loading[member] = true
            local success, message = xpcall(function()
              (definition.load or vim.cmd.packadd)(plan.nodes[member].name)
            end, debug.traceback)
            loading[member] = nil
            if not success then
              package_errors[member] = message
              error(message, 0)
            end
            loaded[member] = true
          end
        end
      end
      local paths = {}
      for _, member in ipairs(unit.members) do
        local path = plan.nodes[member].after_path
        if path then paths[#paths + 1] = path end
      end
      if #paths > 0 then
        local after = require("divine.after")
        after.ftdetect(paths)
        after.plugins(paths)
      end
      for _, member in ipairs(configuration_ids) do
        local hook = definitions[member].after
        if hook then hook() end
      end
      controller.states[id] = "loaded"
    end, debug.traceback)
    if not ok then
      retain_failure(id, err)
      error(controller.errors[id], 0)
    end
  end

  ---@param id divine.NodeId
  ---@return nil
  function controller.load(id)
    controller.load_unit(assert(node_units[id], "divine: unknown node: " .. tostring(id)))
  end

  ---@type divine.Activate?
  local activate
  cleanup, activate = require("divine.triggers").register(controller, definitions)
  if plan.startup then plan.startup() end
  for _, id in ipairs(plan.startup_units or {}) do
    controller.load_unit(id)
  end
  if activate then activate() end
  return controller
end

-- The after callback is configuration, distinct from opt-in after/ scripts.
return M
