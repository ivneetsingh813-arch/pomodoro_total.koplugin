--[[--
Pomodoro timer for KOReader that also tracks TOTAL time studied
(today / week / month / all-time). Starts straight into a
full-screen countdown: a big mm:ss and a fixed-size ring with one
bead per minute of the session, counting down as each minute
elapses. Tap the screen to pause; Continue/Stop appear while
paused. Session length is configurable (25/5, 45/15, 60/30).
Study stats live in a separate menu entry, kept off the start
screen.

Install: copy this whole folder into koreader/plugins/ as
"pomodoro_total.koplugin" (folder name must end in .koplugin).

Usage: main menu -> More tools -> Pomodoro timer -> Start timer.
--]]--

local Device = require("device")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local TextViewer = require("ui/widget/textviewer")
local Widget = require("ui/widget/widget")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Size = require("ui/size")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local _ = require("gettext")
local T = require("ffi/util").template

local DEFAULT_FOCUS_MINUTES = 25
local DEFAULT_BREAK_MINUTES = 5
local RING_RADIUS = Screen:scaleBySize(220) -- fixed, regardless of session length

--[[-- Ring of beads, one per minute of the session, at a FIXED
radius and FIXED angular positions (set once from the session's
total minutes). Beads are consumed CLOCKWISE starting at 12: the
first minute to pass erases the 12 o'clock bead, the next erases
the one after it going clockwise, and so on -- so the "eaten"
gap grows clockwise over time, and what's left is always the
remaining, not-yet-reached arc. --]]
local MinuteBeadRing = Widget:extend{
    plugin = nil,
}

function MinuteBeadRing:getSize()
    local size = RING_RADIUS * 2 + Screen:scaleBySize(24)
    return Geom:new{ w = size, h = size }
end

function MinuteBeadRing:paintTo(bb, x, y)
    local plugin = self.plugin
    local total_seconds = plugin:currentSessionLength()
    local remaining_seconds = plugin.remaining

    local total_dots = math.floor(total_seconds / 60)
    if total_dots < 1 then total_dots = 1 end

    -- Remaining whole/partial minutes = number of beads still shown.
    local active_dots = math.ceil(remaining_seconds / 60)
    if active_dots < 0 then active_dots = 0 end
    if active_dots > total_dots then active_dots = total_dots end
    local consumed = total_dots - active_dots

    local size = self:getSize().w
    local cx = x + size / 2
    local cy = y + size / 2
    local radius = RING_RADIUS
    local angle_step = (2 * math.pi) / total_dots
    local dot_r = Screen:scaleBySize(6)

    -- Skip the first `consumed` positions (the ones the clockwise
    -- sweep has already passed, starting at 12 o'clock) and draw
    -- only what's left of the ring.
    for i = consumed, total_dots - 1 do
        local angle = (-math.pi / 2) + (i * angle_step)
        local dx = cx + radius * math.cos(angle)
        local dy = cy + radius * math.sin(angle)
        bb:paintRect(dx - dot_r, dy - dot_r, dot_r * 2, dot_r * 2, Blitbuffer.COLOR_BLACK)
    end
end

--[[-- Full-screen timer: the whole "start screen". No stats here
on purpose -- just the shrinking ring, a big countdown, and (only
while paused) Continue/Stop. --]]
local FullScreenTimer = InputContainer:extend{
    plugin = nil,
}

function FullScreenTimer:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
    self:rebuild()
end

function FullScreenTimer:rebuild()
    local plugin = self.plugin

    local ring = MinuteBeadRing:new{ plugin = plugin }

    local mode_text = TextWidget:new{
        text = plugin.mode == "break" and _("Break") or _("Focus"),
        face = Font:getFace("cfont", 28),
    }
    -- Big countdown, fitted inside the ring.
    local time_text = TextWidget:new{
        text = plugin:formatMS(plugin.remaining),
        face = Font:getFace("cfont", 90),
    }

    local timer_stack = OverlapGroup:new{
        dimen = ring:getSize(),
        ring,
        CenterContainer:new{
            dimen = ring:getSize(),
            VerticalGroup:new{
                align = "center",
                mode_text,
                VerticalSpan:new{ width = Screen:scaleBySize(6) },
                time_text,
            },
        },
    }

    local content
    if plugin.paused_screen then
        content = VerticalGroup:new{
            align = "center",
            timer_stack,
            VerticalSpan:new{ width = Size.padding.large * 2 },
            HorizontalGroup:new{
                Button:new{
                    text = _("Continue"),
                    width = Screen:scaleBySize(140),
                    callback = function() plugin:resumeFromFullScreen() end,
                },
                HorizontalSpan:new{ width = Size.padding.large },
                Button:new{
                    text = _("Stop"),
                    width = Screen:scaleBySize(140),
                    callback = function() plugin:stopFromFullScreen() end,
                },
            },
        }
    else
        content = timer_stack
    end

    self[1] = CenterContainer:new{
        dimen = self.dimen,
        FrameContainer:new{
            width = self.dimen.w,
            height = self.dimen.h,
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            CenterContainer:new{
                dimen = self.dimen,
                content,
            },
        },
    }
end

function FullScreenTimer:onTap(_, ges)
    if not self.plugin.paused_screen then
        self.plugin:pauseFromFullScreen()
    end
    return true
end

function FullScreenTimer:onCloseWidget()
    if self.plugin.fs_widget == self then
        self.plugin.fs_widget = nil
    end
end

--[[-- Main plugin object. --]]
local Pomodoro = WidgetContainer:extend{
    name = "pomodoro_total",
    is_doc_only = false,
}

function Pomodoro:init()
    self.settings = LuaSettings:open(
        DataStorage:getSettingsDir() .. "/pomodoro_total.lua"
    )

    self.total_seconds = self.settings:readSetting("total_seconds", 0)
    self.history = self.settings:readSetting("history", {})

    self.today_date = os.date("%Y-%m-%d")
    local saved_date = self.settings:readSetting("today_date")
    if saved_date == self.today_date then
        self.today_seconds = self.settings:readSetting("today_seconds", 0)
    else
        self.today_seconds = 0
    end

    local focus_minutes = self.settings:readSetting("focus_minutes", DEFAULT_FOCUS_MINUTES)
    local break_minutes = self.settings:readSetting("break_minutes", DEFAULT_BREAK_MINUTES)
    self.focus_seconds = focus_minutes * 60
    self.break_seconds = break_minutes * 60

    self.mode = "idle" -- "idle" | "focus" | "break"
    self.remaining = self.focus_seconds
    self.running = false
    self.paused_screen = false
    self.fs_widget = nil
    self.cycles_completed = self.settings:readSetting("cycles_completed", 0)

    self._tick_fn = function() self:tick() end

    self.ui.menu:registerToMainMenu(self)
end

function Pomodoro:addToMainMenu(menu_items)
    menu_items.pomodoro_total = {
        text = _("Pomodoro timer"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Start timer"),
                callback = function() self:launchFullScreen() end,
            },
            {
                text = _("Session length"),
                sub_item_table = {
                    {
                        text = _("25 min focus / 5 min break"),
                        checked_func = function() return self.focus_seconds == 25 * 60 end,
                        callback = function() self:setPreset(25, 5) end,
                    },
                    {
                        text = _("45 min focus / 15 min break"),
                        checked_func = function() return self.focus_seconds == 45 * 60 end,
                        callback = function() self:setPreset(45, 15) end,
                    },
                    {
                        text = _("60 min focus / 30 min break"),
                        checked_func = function() return self.focus_seconds == 60 * 60 end,
                        callback = function() self:setPreset(60, 30) end,
                    },
                },
            },
            {
                text = _("Study stats"),
                callback = function() self:showStatsMenu() end,
            },
        },
    }
end

function Pomodoro:setPreset(focus_minutes, break_minutes)
    self.focus_seconds = focus_minutes * 60
    self.break_seconds = break_minutes * 60
    self.settings:saveSetting("focus_minutes", focus_minutes)
    self.settings:saveSetting("break_minutes", break_minutes)
    self.settings:flush()
    -- Only snap the live countdown to the new length if nothing
    -- is running yet -- an in-progress session keeps its length.
    if self.mode == "idle" then
        self.remaining = self.focus_seconds
    end
end

function Pomodoro:currentSessionLength()
    if self.mode == "break" then
        return self.break_seconds
    end
    return self.focus_seconds
end

-- ===== time helpers =====

function Pomodoro:rolloverDayIfNeeded()
    local today = os.date("%Y-%m-%d")
    if today ~= self.today_date then
        self.history[self.today_date] = self.today_seconds
        self.today_date = today
        self.today_seconds = 0
    end
end

function Pomodoro:formatHM(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then
        return T(_("%1h %2m"), h, m)
    else
        return T(_("%1m"), m)
    end
end

function Pomodoro:formatMS(seconds)
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

function Pomodoro:secondsOn(date_str)
    if date_str == self.today_date then
        return self.today_seconds
    end
    return self.history[date_str] or 0
end

function Pomodoro:weeklyTotal()
    local total = 0
    for i = 0, 6 do
        total = total + self:secondsOn(os.date("%Y-%m-%d", os.time() - i * 86400))
    end
    return total
end

function Pomodoro:monthlyTotal()
    local total = 0
    local year_month = os.date("%Y-%m")
    local day_of_month = tonumber(os.date("%d"))
    for d = 1, day_of_month do
        total = total + self:secondsOn(string.format("%s-%02d", year_month, d))
    end
    return total
end

function Pomodoro:weeklyBreakdownText()
    local lines, total = {}, 0
    for i = 6, 0, -1 do
        local ts = os.time() - i * 86400
        local date_str = os.date("%Y-%m-%d", ts)
        local seconds = self:secondsOn(date_str)
        total = total + seconds
        local label = os.date("%a %d %b", ts)
        if date_str == self.today_date then
            label = label .. " " .. _("(today)")
        end
        table.insert(lines, string.format("%s: %s", label, self:formatHM(seconds)))
    end
    table.insert(lines, 1, T(_("Total this week: %1"), self:formatHM(total)))
    table.insert(lines, 2, "")
    return table.concat(lines, "\n")
end

function Pomodoro:monthlyBreakdownText()
    local lines, total = {}, 0
    local year_month = os.date("%Y-%m")
    local day_of_month = tonumber(os.date("%d"))
    for d = 1, day_of_month do
        local date_str = string.format("%s-%02d", year_month, d)
        local seconds = self:secondsOn(date_str)
        total = total + seconds
        if seconds > 0 then
            local label = date_str
            if date_str == self.today_date then
                label = label .. " " .. _("(today)")
            end
            table.insert(lines, string.format("%s: %s", label, self:formatHM(seconds)))
        end
    end
    if #lines == 0 then
        table.insert(lines, _("No sessions logged yet this month."))
    end
    table.insert(lines, 1, T(_("Total this month: %1"), self:formatHM(total)))
    table.insert(lines, 2, "")
    return table.concat(lines, "\n")
end

-- ===== stats menu (separate from the start screen) =====

function Pomodoro:showStatsMenu()
    local text = T(
        _("Studied today: %1\nStudied this week: %2\nStudied this month: %3\nStudied all-time: %4\nFull sessions completed: %5"),
        self:formatHM(self.today_seconds),
        self:formatHM(self:weeklyTotal()),
        self:formatHM(self:monthlyTotal()),
        self:formatHM(self.total_seconds),
        self.cycles_completed
    )
    local dialog
    dialog = ButtonDialogTitle:new{
        title = text,
        buttons = {
            {
                {
                    text = _("Weekly breakdown"),
                    callback = function()
                        UIManager:show(TextViewer:new{
                            title = _("This week"),
                            text = self:weeklyBreakdownText(),
                        })
                    end,
                },
                {
                    text = _("Monthly breakdown"),
                    callback = function()
                        UIManager:show(TextViewer:new{
                            title = _("This month"),
                            text = self:monthlyBreakdownText(),
                        })
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function() UIManager:close(dialog) end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

-- ===== full-screen timer flow =====

function Pomodoro:launchFullScreen()
    self.paused_screen = false
    if self.mode == "idle" then
        self.mode = "focus"
        self.remaining = self.focus_seconds
    end
    self.fs_widget = FullScreenTimer:new{ plugin = self }
    UIManager:show(self.fs_widget, "full")
    self:startTicking()
end

function Pomodoro:refreshFullScreen()
    if self.fs_widget then
        self.fs_widget:rebuild()
        UIManager:setDirty(self.fs_widget, "fast")
    end
end

function Pomodoro:pauseFromFullScreen()
    self:stopTicking()
    self:saveSettings()
    self.paused_screen = true
    self:refreshFullScreen()
end

function Pomodoro:resumeFromFullScreen()
    self.paused_screen = false
    self:startTicking()
    self:refreshFullScreen()
end

function Pomodoro:stopFromFullScreen()
    self:stopTicking()
    self:saveSettings()
    self.mode = "idle"
    self.remaining = self.focus_seconds
    self.paused_screen = false
    if self.fs_widget then
        UIManager:close(self.fs_widget)
        self.fs_widget = nil
    end
end

-- ===== ticking =====

function Pomodoro:startTicking()
    if not self.running then
        self.running = true
        UIManager:scheduleIn(1, self._tick_fn)
    end
end

function Pomodoro:stopTicking()
    if self.running then
        self.running = false
        UIManager:unschedule(self._tick_fn)
    end
end

function Pomodoro:tick()
    if not self.running then
        return
    end

    self:rolloverDayIfNeeded()
    self.remaining = self.remaining - 1

    if self.mode == "focus" then
        self.today_seconds = self.today_seconds + 1
        self.total_seconds = self.total_seconds + 1
    end

    if self.remaining <= 0 then
        self:onSessionComplete()
    else
        UIManager:scheduleIn(1, self._tick_fn)
    end

    self:refreshFullScreen()

    if self.remaining % 30 == 0 then
        self:saveSettings()
    end
end

function Pomodoro:onSessionComplete()
    if self.mode == "focus" then
        self.cycles_completed = self.cycles_completed + 1
        self.mode = "break"
        self.remaining = self.break_seconds
        UIManager:show(InfoMessage:new{
            text = T(_("Focus session done. Studied today: %1."), self:formatHM(self.today_seconds)),
            timeout = 4,
        })
    else
        self.mode = "focus"
        self.remaining = self.focus_seconds
        UIManager:show(InfoMessage:new{
            text = _("Break's over. Next focus session starting."),
            timeout = 4,
        })
    end
    self:saveSettings()
    UIManager:scheduleIn(1, self._tick_fn)
end

-- ===== persistence =====

function Pomodoro:saveSettings()
    self.history[self.today_date] = self.today_seconds
    self.settings:saveSetting("total_seconds", self.total_seconds)
    self.settings:saveSetting("today_seconds", self.today_seconds)
    self.settings:saveSetting("today_date", self.today_date)
    self.settings:saveSetting("cycles_completed", self.cycles_completed)
    self.settings:saveSetting("history", self.history)
    self.settings:flush()
end

function Pomodoro:onCloseWidget()
    self:saveSettings()
end

function Pomodoro:onSuspend()
    self:saveSettings()
end

return Pomodoro
