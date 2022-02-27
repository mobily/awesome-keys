local module = {}

local drawing = hs.drawing
local timer = hs.timer
local screen = hs.screen
local uuid = hs.host.uuid
local stext = hs.styledtext.new

local stextMT = hs.getObjectMetatable("hs.styledtext")

module._visibleAlerts = {}

local purgeAlert = function(UUID)
  local indexToRemove
  for i, v in ipairs(module._visibleAlerts) do
    if v.UUID == UUID then
      for i2, v2 in ipairs(v.drawings) do
        v2:hide()
        v.drawings[i2] = nil
      end
      indexToRemove = i
      break
    end
  end
  if indexToRemove then
    table.remove(module._visibleAlerts, indexToRemove)
  end
end

local showAlert = function(message, style, screenObj)
  local screenFrame = screenObj:fullFrame()
  local absoluteTop = screenFrame.y + (screenFrame.h * (1 - 1 / 1.55) + 55) -- mimic module behavior for inverted rect

  if style.position.y == "top" or style.position.y == "bottom" then
    absoluteTop = screenFrame.y
  else
    if #module._visibleAlerts > 0 then
      module.closeAll()
    end
  end

  if absoluteTop > (screenFrame.y + screenFrame.h) then
    absoluteTop = screenFrame.y
  end

  local alertEntry = {
    drawings = {},
    screen = screenObj,
    atScreenEdge = style.atScreenEdge
  }
  local UUID = uuid()
  alertEntry.UUID = UUID

  local padding = style.padding or fontSize / 2
  local strokeWidth = style.strokeWidth -- strokeWidth should be used to adjust position and padding.

  -- If no message is specified, don't reserve space for it
  local textFrame
  if message == "" then
    textFrame = {h = 0, w = 0}
  else
    textFrame = drawing.getTextDrawingSize(message, {font = style.fontFamily, size = style.fontSize})
    textFrame.w = math.ceil(textFrame.w) -- drawing.getTextDrawingSize may return a float value, and use it directly could cause some display problem, the last character of a line may disappear.
  end

  -- Define the size of the drawing frame
  local drawingFrame = {
    h = textFrame.h + padding * 2 + strokeWidth,
    w = textFrame.w + padding * 2 + strokeWidth
  }

  -- Use the size to set the position
  if style.position.x == "left" then
    drawingFrame.x = style.position.offsetX
  elseif style.position.x == "right" then
    drawingFrame.x = screenFrame.x + screenFrame.w - drawingFrame.w - style.position.offsetX
  else
    drawingFrame.x = screenFrame.x + (screenFrame.w - drawingFrame.w) / 2
  end

  if style.position.y == "bottom" then
    drawingFrame.y = screenFrame.y + screenFrame.h - drawingFrame.h - style.position.offsetY
  elseif style.position.y == "top" then
    drawingFrame.y = absoluteTop + style.position.offsetY
  else
    drawingFrame.y = absoluteTop
  end

  table.insert(
    alertEntry.drawings,
    drawing.rectangle(drawingFrame):setStroke(true):setStrokeWidth(style.strokeWidth):setStrokeColor(style.strokeColor):setFill(
      true
    ):setFillColor(style.backgroundColor):setRoundedRectRadii(style.radius, style.radius):show()
  )

  -- Constraints for placing the text
  local textMinX = drawingFrame.x
  local textMaxWidth = drawingFrame.w

  -- Draw the text in the center of the remaining space
  textFrame.x = textMinX + (textMaxWidth - textFrame.w) / 2
  textFrame.y = drawingFrame.y + (drawingFrame.h - textFrame.h) / 2

  table.insert(
    alertEntry.drawings,
    drawing.text(textFrame, message):setTextFont(fontFamily):setTextSize(fontSize):setTextColor(textColor):orderAbove(
      alertEntry.drawings[1]
    ):show()
  )
  alertEntry.frame = drawingFrame

  table.insert(module._visibleAlerts, alertEntry)

  return UUID
end

module.show = function(message, ...)
  local style, screenObj, duration
  for i, v in ipairs(table.pack(...)) do
    if type(v) == "table" and not style then
      style = v
    elseif type(v) == "userdata" and not screenObj then
      screenObj = v
    else
      error("unexpected type " .. type(v) .. " found for argument " .. tostring(i + 1), 2)
    end
  end
  if getmetatable(message) ~= stextMT then
    message = tostring(message)
  end
  duration = duration or 2.0
  screenObj = screenObj or screen.mainScreen()
  return showAlert(message, style, screenObj, duration)
end

module.closeAll = function()
  while (#module._visibleAlerts > 0) do
    purgeAlert(module._visibleAlerts[#module._visibleAlerts].UUID)
  end
end

module.closeSpecific = function(UUID)
  purgeAlert(UUID)
end

return module
