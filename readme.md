Init() builds the GUI. Call it once, after all tabs/sections/elements are declared. Elements added after Init() still work.

Window
Method	Description
library:Init()	Builds and parents the GUI
library:Close()	Toggles visibility, returns the new state
library:Unload()	Destroys everything, restores metamethod hooks, disconnects all connections
library:AddWarning({text, type})	Creates a modal warning. type = "confirm" gives Yes/No
library:AddWatermark(text)	Floating label. Returns object with :SetText(str). Call after Init()
library:SendNotification(duration, message)	Bottom-right notification, min 2s
library:Notify(message, duration)	Same, message-first argument order
library:SetRainbow(bool)	Animated rainbow accent
library:ApplyAccent(color)	Re-applies an accent color to every themed element
Properties: library.title, library.draggable, library.Version, library.flagprefix, library.keyBlacklist, library.borderColor.

Structure
library:AddTab(title, position?)
  tab:AddColumn()
    column:AddSection(title)
      section:AddElement(...)
A tab renders 1–4 columns side by side and resizes itself. position on AddTab controls tab order.

Elements
All elements accept text, flag, tip, callback, and return an object.

section:AddToggle({text, state, style, callback})
style = 2 uses a rounded tickbox. Methods: :SetState(bool, nocallback), :SetEnabled(bool), :AddBind({}), :AddColor({}), :AddList({}), :AddSlider({}).

section:AddButton({text, callback})
Methods: :SetEnabled(bool), :AddBind({}), :AddColor({}). nomouse = true blocks mouse binds.

section:AddBind({text, key, mode, nomouse, callback})
mode = "toggle" (default) or "hold". Callback is (state, step); hold mode fires (nil, step) every frame while held. :SetKey(keycode).

section:AddSlider({text, min, max, value, float, suffix, textpos, callback})
float is the rounding step (e.g. 0.1). textpos = 2 puts the label over the bar. Ctrl+click to type a value. :SetValue(number, nocallback).

section:AddList({text, values, multiselect, value, max, callback})
max caps visible rows before scrolling. :AddValue(value, state), :RemoveValue(value), :SetValue(value, nocallback), :Close().

section:AddBox({text, value, callback})
Callback is (value, enter). :SetValue(value, enter).

section:AddColor({text, color, trans, calltrans, callback})
Full HSV picker with hex/RGB fields and optional alpha strip. :SetColor(color, nocallback), :SetTrans(value).

section:AddLabel(text) / section:AddDivider(text)
label.Text = "new" and divider.Text = "new" update them live. Labels support RichText.

Every element also gets :SetEnabled(false) / :IsEnabled().

Flags
flag is the key in library.flags. Defaults to text, auto-suffixed on collision.

lua
library.flags.AutoParry
library:SetFlag("AutoParry", true)
library:OnFlagChanged("AutoParry", function(value, flag) print(flag, value) end)
library.flagprefix prefixes every flag. skipflag = true excludes an element from config save/load.

Keybinds
Bindable by clicking a [KEY] box then pressing a key. Backspace clears. Right-clicking a bind box is captured unless nomouse = true.

library.keyBlacklist ships with Unknown and Escape. Add WASD if you don't want them stolen:

lua
table.insert(library.keyBlacklist, Enum.KeyCode.W)
Themes
lua
library:ApplyAccent(Color3.fromRGB(120, 80, 255))
library:SetRainbow(true)
library.borderColor = Color3.fromRGB(80, 80, 80)
Built-in Settings tab exposes accent, rainbow, 12 background patterns, background tint, and tile size.

Configs
Auto-created at uw_configs/*.uw (JSON). Toggles serialize to 1/0, colors to {r,g,b} plus transparency, binds to key names. Settings tab has Create/Save/Load/Delete with a confirm modal. library.canSave is false when the executor has no filesystem, and the Configs section is replaced with a notice.

Mobile
Touch is fully wired: tapping toggles/buttons, touch-dragging the title bar, touch-scrubbing sliders and the color picker. A UIScale auto-fits the window to the viewport.

Compatibility
gethui() → get_hidden_gui() → CoreGui → PlayerGui fallback chain, so the GUI appears on any executor. Metamethod hooks use getrawmetatable/setreadonly with a hookmetamethod fallback, and are restored on unload — no stacking after reloads.

What changed in 2.0
Fixed: __newindex swallowing custom fields · ConfigWarning nil global in Delete · getgenv().uwuware never set · slider float inverted check · slider Ctrl+click parse ("Speed: 16") · dead notification throttle · flag collisions overwriting library.options · hardcoded \ config paths · library.theme leaking destroyed instances · AddWarning answer race · unparented GUI when syn is absent · stacked metamethod hooks · box SetValue on empty input · list/color Close() clobbering other popups · cloned hex box not registered for cleanup.

Added: Version · SetFlag/OnFlagChanged · SetEnabled/IsEnabled · SetRainbow · ApplyAccent · AddWatermark · Notify · roundRGB · touch support · UIScale · drag clamping · tooltip edge flipping · hover tweens · UICorner/UIStroke replacing stacked border images · task.* scheduling · parent-last property assignment · pcall'd unload and config I/O · canSave guard · mutable keyBlacklist · AddLabel/AddDivider RichText and live updates · slider division-by-zero guard.

Removed: ~40 redundant ImageLabel borders per full UI, dead chromaColor loop, dead inContact, duplicate AddValue in AddList.
