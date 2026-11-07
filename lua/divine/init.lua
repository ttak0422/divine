local M = {}

-- Internal prototype only; generated names and the consumer API remain proposed.
function M.load_one(name, hooks)
  assert(type(name) == "string" and name ~= "", "a package directory name is required")
  hooks = hooks or {}
  if hooks.before then hooks.before() end
  (hooks.load or vim.cmd.packadd)(name)
  if hooks.after then hooks.after() end
end

local function validate(plan)
  assert(type(plan) == "table" and type(plan.nodes) == "table", "divine: nodes are required")
  assert(type(plan.units) == "table" and vim.islist(plan.units), "divine: units must be a list")
  assert(
    plan.startup_units == nil
      or (type(plan.startup_units) == "table" and vim.islist(plan.startup_units)),
    "divine: startup_units must be a list"
  )
  assert(plan.startup == nil or type(plan.startup) == "function", "divine: invalid startup hook")
  local units, node_units, names = {}, {}, {}
  for id, node in pairs(plan.nodes) do
    assert(type(id) == "string" and type(node) == "table", "divine: invalid node")
    assert(
      type(node.name) == "string" and node.name:match("^[%w_.-]+$"),
      "divine: invalid package name"
    )
    assert(not names[node.name], "divine: duplicate package name: " .. node.name)
    names[node.name] = true
    for _, hook in ipairs({ "before", "load", "after" }) do
      assert(
        node[hook] == nil or type(node[hook]) == "function",
        "divine: invalid " .. hook .. " hook"
      )
    end
  end
  for _, unit in ipairs(plan.units) do
    assert(type(unit) == "table", "divine: invalid unit")
    assert(type(unit.id) == "string" and not units[unit.id], "divine: invalid or duplicate unit")
    assert(
      type(unit.members) == "table" and vim.islist(unit.members) and #unit.members > 0,
      "divine: empty unit"
    )
    assert(
      type(unit.dependencies) == "table" and vim.islist(unit.dependencies),
      "divine: unit dependencies must be a list"
    )
    units[unit.id] = unit
    for _, id in ipairs(unit.members) do
      assert(plan.nodes[id] and not node_units[id], "divine: unknown or repeated unit member")
      node_units[id] = unit.id
    end
  end
  for id in pairs(plan.nodes) do
    assert(node_units[id], "divine: node has no unit: " .. id)
  end
  local visited, visiting = {}, {}
  local function visit(id)
    assert(units[id], "divine: unknown unit: " .. tostring(id))
    assert(not visiting[id], "divine: dependency cycle between units: " .. id)
    if visited[id] then return end
    visiting[id] = true
    for _, dependency in ipairs(units[id].dependencies) do
      visit(dependency)
    end
    visiting[id], visited[id] = nil, true
  end
  for id in pairs(units) do
    visit(id)
  end
  for _, id in ipairs(plan.startup_units or {}) do
    assert(units[id], "divine: unknown startup unit: " .. tostring(id))
  end
  return units, node_units
end

function M.setup(plan)
  -- Validate the complete DAG before registration or user callbacks have effects.
  local units, node_units = validate(plan)
  local controller = { states = {}, errors = {}, node_units = node_units }
  local cleanup
  for id in pairs(units) do
    controller.states[id] = "unloaded"
  end

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
        vim.cmd.packadd({ plan.nodes[member].name, bang = true })
      end
      if cleanup then
        for _, member in ipairs(unit.members) do
          cleanup(member)
        end
      end
      controller.states[id] = "configuring"
      for _, member in ipairs(unit.members) do
        local hook = plan.nodes[member].before
        if hook then hook() end
      end
      controller.states[id] = "loading"
      for _, member in ipairs(unit.members) do
        local node = plan.nodes[member]
        local load = node.load or vim.cmd.packadd
        load(node.name)
      end
      for _, member in ipairs(unit.members) do
        local hook = plan.nodes[member].after
        if hook then hook() end
      end
      controller.states[id] = "loaded"
    end, debug.traceback)
    if not ok then
      controller.states[id] = "failed"
      controller.errors[id] = "divine: unit "
        .. id
        .. " failed; partial effects cannot be retried:\n"
        .. tostring(err)
      error(controller.errors[id], 0)
    end
  end

  function controller.load(id)
    controller.load_unit(assert(node_units[id], "divine: unknown node: " .. tostring(id)))
  end

  local activate
  cleanup, activate = require("divine.triggers").register(controller, plan.nodes)
  if plan.startup then plan.startup() end
  for _, id in ipairs(plan.startup_units or {}) do
    controller.load_unit(id)
  end
  if activate then activate() end
  return controller
end

-- after/plugin is intentionally not sourced here; it is not the after action.
return M
