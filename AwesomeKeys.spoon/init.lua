local obj = {}

local function loadModule(module)
  local dirname = debug.getinfo(2, "S").source:sub(2):match("(.*/)")
  local f = dofile(dirname .. module .. ".lua")
  return f
end

local view = loadModule("view")
local styledtext = hs.styledtext.new
local styledtextMeta = hs.getObjectMetatable("hs.styledtext")

obj.__index = obj

-- Metadata
obj.name = "AwesomeKeys"
obj.version = "1.0"
obj.author = "Marcin Dziewulski <hello@mobily.pl>"
obj.homepage = "https://github.com/mobily/awesome-keys"
obj.license = "MIT"

local logger = hs.logger.new("AwesomeKeys", "debug")
obj.logger = logger

obj.fnutils = {}

function obj.fnutils.keyStroke(modifiers, key)
  return function()
    hs.eventtap.keyStroke(modifiers, key)
  end
end

function obj.fnutils.openURL(url)
  return function()
    hs.urlevent.openURL(url)
  end
end

function obj.fnutils.focusApp(name)
  return function()
    local isRunning =
      hs.fnutils.some(
      hs.application.runningApplications(),
      function(app)
        return app:name() == name
      end
    )
    local app = hs.application.find(name)

    if app then
      hs.application.launchOrFocusByBundleID(app:bundleID())
    end
  end
end

function obj.fnutils.paste(str)
  return function()
    tempClipboard = hs.pasteboard.uniquePasteboard()
    hs.pasteboard.writeAllData(tempClipboard, hs.pasteboard.readAllData(nil))
    hs.pasteboard.writeObjects(str)
    hs.eventtap.keyStroke({"cmd"}, "v")
    hs.pasteboard.writeAllData(nil, hs.pasteboard.readAllData(tempClipboard))
    hs.pasteboard.deletePasteboard(tempClipboard)
  end
end

function obj.fnutils.pasteWith(str, fn)
  return function()
    local paste = obj.fnutils.paste(str)
    fn(paste)
  end
end

local function identity(value)
  return value
end

local function switch(t)
  t.case = function(self, x)
    local f = self[x] or self.default
    if f then
      if type(f) == "function" then
        return f(x, self)
      else
        error("case " .. tostring(x) .. " not a function")
      end
    end
  end

  return t
end

local function equals(a, b)
  return table.concat(a) == table.concat(b)
end

local function copy(t)
  local u = {}
  for k, v in pairs(t) do
    u[k] = v
  end
  return setmetatable(u, getmetatable(t))
end

local function refmerge(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, v in pairs(b) do
      if type(v) == "table" and type(a[k] or false) == "table" then
        refmerge(a[k], v)
      else
        a[k] = v
      end
    end
  end
  return a
end

local function merge(a, b)
  local a = copy(a)
  return refmerge(a, b)
end

local function size(table)
  local count = 0
  for _ in pairs(table) do
    count = count + 1
  end
  return count
end

local function splitEvery(xs, size)
  local i = 1
  local count = 0

  return function()
    if i > #xs then
      return
    end

    local chunk = table.move(xs, i, i + size - 1, 1, {})

    i = i + size
    count = count + 1

    return count, chunk
  end
end

local function keepMap(table, fn)
  local t = hs.fnutils.map(table, fn)
  return hs.fnutils.ifilter(
    t,
    function(element)
      return element ~= nil
    end
  )
end

local function eachWithIndex(table, fn)
  for i, v in ipairs(table) do
    fn(i, v)
  end
end

local function ignore()
end

local function findAppName(name)
  local app = hs.application.find(name)

  if app then
    return app:name()
  end

  return nil
end

local function mapKeysWith(data, fn)
  local data =
    keepMap(
    data,
    function(element)
      local app = findAppName(element.app)

      if app then
        local keys = hs.fnutils.imap(element.keys, fn)

        return refmerge(
          element,
          {
            app = app,
            keys = keys
          }
        )
      end

      return nil
    end
  )
  local apps =
    hs.fnutils.map(
    data,
    function(element)
      return element.app
    end
  )

  return {
    data = data,
    apps = apps
  }
end

function obj:setGlobalBindings(...)
  hs.fnutils.ieach(
    {...},
    function(binding)
      local key, fn = binding.key, binding.fn
      local mods = binding.mods or {}
      hs.hotkey.bind(mods, key, fn)
    end
  )
end

function obj:remapAppKeys(...)
  local result =
    mapKeysWith(
    {...},
    function(key)
      local from, to = key.from, key.to
      local fn = obj.fnutils.keyStroke(to.mods or {}, to.key)
      return hs.hotkey.new(from.mods or {}, from.key, fn, nil, fn)
    end
  )
  local data, apps = result.data, result.apps

  local function enableKeys(window)
    local current =
      hs.fnutils.find(
      data,
      function(element)
        return element.app == window:application():name()
      end
    )

    if current then
      hs.fnutils.each(
        current.keys,
        function(key)
          key:enable()
        end
      )
    end
  end

  local function disableKeys(window)
    local current =
      hs.fnutils.find(
      data,
      function(element)
        return element.app == window:application():name()
      end
    )

    if current then
      hs.fnutils.ieach(
        current.keys,
        function(key)
          key:disable()
        end
      )
    end
  end

  hs.window.filter.new(apps):subscribe(hs.window.filter.windowFocused, enableKeys):subscribe(
    hs.window.filter.windowUnfocused,
    disableKeys
  )
end

local HyperBindings = {}
HyperBindings.__index = HyperBindings

function HyperBindings:showAlert()
  local text = hs.styledtext.new("", {})
  local textStyle = {
    font = {name = self.alertConfig.fontFamily, size = self.alertConfig.fontSize}
  }
  local spacerStyle =
    merge(
    textStyle,
    {
      color = merge(self.alertConfig.textColor, {alpha = 0.4})
    }
  )

  local frontmostApplication = hs.application.frontmostApplication()
  local currentApp =
    hs.fnutils.find(
    self.appBindingsData,
    function(element)
      return element.app == frontmostApplication:name()
    end
  )
  local appLabels = {}
  local hasGlobals = size(self.globals) > 0
  local split = currentApp ~= nil and currentApp.splitEvery or self.splitEvery

  local function addElements(table)
    eachWithIndex(
      table,
      function(index, element)
        if index == 1 then
          text = text .. element
          return nil
        end

        text = text .. styledtext(self.spacer, spacerStyle) .. element
      end
    )
  end

  if currentApp then
    appLabels =
      keepMap(
      currentApp.keys,
      function(element)
        local pattern = element.pattern or ".*"
        local windowTitle = frontmostApplication:focusedWindow():title()
        local match = string.match(windowTitle, pattern)

        if match ~= nil then
          return self:makePrettyKeyLabel(element)
        end

        return nil
      end
    )
  end

  if hasGlobals then
    addElements(self.globals)
  end

  if size(appLabels) > 0 then
    if hasGlobals then
      text = text .. styledtext("\n" .. self.separator .. " " .. frontmostApplication:name(), spacerStyle)
    end

    for i, chunk in splitEvery(appLabels, split) do
      text = text .. styledtext("\n")
      addElements(chunk)
    end
  end

  self:closeAlert()
  view.show(text, self.alertConfig, hs.screen.mainScreen())
end

function HyperBindings:makePrettyKeyLabel(element)
  local icons =
    hs.fnutils.map(
    element.mods or {},
    function(m)
      local switch =
        switch {
        ["cmd"] = function()
          return "⌘"
        end,
        ["command"] = function()
          return "⌘"
        end,
        ["alt"] = function()
          return "⌥"
        end,
        ["option"] = function()
          return "⌥"
        end,
        ["ctrl"] = function()
          return "⌃"
        end,
        ["control"] = function()
          return "⌃"
        end,
        ["shift"] = function()
          return "⇧"
        end,
        default = function()
          return ""
        end
      }

      return switch:case(m)
    end
  )
  local textStyle = {
    font = {name = self.alertConfig.fontFamily, size = self.alertConfig.fontSize}
  }

  return styledtext(
    table.concat(icons, ""),
    merge(
      textStyle,
      {
        color = self.alertConfig.modsColor
      }
    )
  ) ..
    styledtext(
      element.key .. " ",
      merge(
        textStyle,
        {
          color = self.alertConfig.keyColor
        }
      )
    ) ..
      styledtext(
        element.label,
        merge(
          textStyle,
          {
            color = self.alertConfig.textColor
          }
        )
      )
end

function HyperBindings:closeAlert()
  view.closeAll()
end

local defaultAlertConfig = {
  strokeWidth = 2,
  strokeColor = {white = 1, alpha = 0.1},
  backgroundColor = {hex = "#000", alpha = 0.9},
  textColor = {hex = "#fff", alpha = 0.8},
  modsColor = {hex = "#FA58B6"},
  keyColor = {hex = "#f5d76b"},
  fontFamily = ".AppleSystemUIFont",
  fontSize = 15,
  radius = 0,
  padding = 24,
  position = {x = "center", y = "bottom", offsetY = 8, offsetX = 8}
}
local hyperBindings = {}

function HyperBindings:new(options)
  local class = {}
  local options = options or {}
  local mods = options.mods or {}
  local hyperKey = options.hyperKey

  setmetatable(class, HyperBindings)

  class.hyper = hs.hotkey.modal.new(mods, hyperKey)
  class.spacer = options.spacer or " · "
  class.separator = options.separator or "———"
  class.alertConfig =
    merge(
    defaultAlertConfig,
    {
      strokeWidth = options.strokeWidth,
      strokeColor = options.strokeColor,
      backgroundColor = options.backgroundColor,
      textColor = options.textColor,
      modsColor = options.modsColor,
      keyColor = options.keyColor,
      fontFamily = options.fontFamily,
      fontSize = options.fontSize,
      radius = options.radius,
      padding = options.padding,
      position = merge(defaultAlertConfig.position, options.position)
    }
  )
  class.splitEvery = options.splitEvery or 6
  class.onExit = options.onExit or ignore
  class.onEnter = options.onEnter or ignore

  class.appBindingsData = {}
  class.globals = {}
  class.isEnabled = false

  table.insert(hyperBindings, {key = hyperKey, hyper = class.hyper})

  function class.hyper:entered()
    class.isEnabled = true

    class.onEnter()

    hs.fnutils.ieach(
      hyperBindings,
      function(o)
        if hyperKey ~= o.key then
          o.hyper:exit()
        end
      end
    )

    class:showAlert()
  end

  function class.hyper:exited()
    class.isEnabled = false
    class.onExit()
    class:closeAlert()
  end

  class.hyper:bind(
    mods,
    hyperKey,
    function()
      class.hyper:exit()
    end
  )

  return class
end

function HyperBindings:setGlobalBindings(...)
  hs.fnutils.ieach(
    {...},
    function(element)
      local mods = element.mods or {}
      table.insert(self.globals, self:makePrettyKeyLabel(element))
      self.hyper:bind(mods, element.key, element.fn)
    end
  )
end

function HyperBindings:setAppBindings(...)
  local result = mapKeysWith({...}, identity)
  local currentApp = hs.application.frontmostApplication()

  self.appBindingsData = result.data

  hs.window.filter.new():subscribe(
    {hs.window.filter.windowFocused, hs.window.filter.windowTitleChanged},
    function(window)
      currentApp = window:application()

      if self.isEnabled then
        self:showAlert()
      end
    end
  )

  local bindings = {}

  hs.fnutils.each(
    result.data,
    function(element)
      hs.fnutils.ieach(
        element.keys,
        function(el)
          local current =
            hs.fnutils.find(
            bindings,
            function(b)
              return b.key == el.key and equals(b.mods, el.mods)
            end
          )
          local config = {
            app = element.app,
            pattern = el.pattern,
            fn = el.fn
          }

          if current then
            table.insert(current.xs, config)
            return nil
          end

          table.insert(bindings, {key = el.key, mods = el.mods, xs = {config}})
        end
      )
    end
  )

  hs.fnutils.ieach(
    bindings,
    function(binding)
      local mods, key = binding.mods or {}, binding.key

      self.hyper:bind(
        mods,
        key,
        function()
          local apps =
            hs.fnutils.ifilter(
            binding.xs,
            function(b)
              return b.app == currentApp:name()
            end
          )
          local pressOriginal = false

          hs.fnutils.ieach(
            apps,
            function(app)
              local pattern = app.pattern or ".*"
              local match = string.match(currentApp:focusedWindow():title(), pattern)
              if match ~= nil then
                pressOriginal = false
                return app.fn()
              end

              pressOriginal = true
            end
          )

          if size(apps) == 0 or pressOriginal then
            self.hyper:exit()
            hs.eventtap.keyStroke(mods, key, 1000)
            self.hyper:enter()
          end
        end
      )
    end
  )
end

function obj:createHyperBindings(config)
  return HyperBindings:new(config)
end

function obj:init()
  self._init_done = true
  return self
end

return obj
