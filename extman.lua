-- Extman is a Lua script manager for SciTE. It enables multiple scripts to capture standard events
-- without interfering with each other. For instance, extman.OnDoubleClick() will register handlers
-- for scripts that need to know when a double-click event has happened. (To know whether it
-- was in the output or editor pane, just test editor.Focus).  It provides a useful function extman.Command
-- which allows you to define new commands without messing around with property files (see the
-- examples in the scite_lua directory.)
-- extman defines three new convenience handlers as well:
--extman.OnWord (called when user has entered a word)
--extman.OnEditorLine (called when a line is entered into the editor)
--extman.OnOutputLine (called when a line is entered into the output pane)

local unpack = unpack or table.unpack

-- This library.
-- On 2021-11-06 I replaced all the occurrences of "scite_(\w+)" with "extman.$1".
extman = {}

-- useful function for getting a property, or a default if not present.
function extman.GetProp(key,default)
  local val = props[key]
  return val ~= '' and val or default
end

function extman.GetPropBool(key,default)
  local res = extman.GetProp(key,default)
  return res and res ~= '0' and res ~= 'false'
end

local GTK = extman.GetProp('PLAT_GTK')

local IDM_TOOLS = 1100 -- see SciTE documentation
local _MarginClick,_DoubleClick,_SavePointLeft = {},{},{}
local _SavePointReached,_Open,_SwitchFile = {},{},{}
local _BeforeSave,_Save,_Char = {},{},{}
local _Word,_LineEd,_LineOut = {},{},{}
local _OpenSwitch = {}
local _UpdateUI = {}
local _UserListSelection
local _Strips

local _Key = {}
local _DwellStart = {}
local _Close = {}

local find, match, sub, gsub = string.find, string.match, string.sub, string.gsub

-- file must be quoted if it contains spaces!
function extman.quote_if_needed(target)
  local quote = '"'
  if find(target,'%s') and sub(target,1,1) ~= quote then
    target = quote..target..quote
  end
  return target
end

function OnUserListSelection(tp,str)
  if _UserListSelection then
    local callback = _UserListSelection
    _UserListSelection = nil
    return callback(str)
  end
  return false
end

function OnStrip(control, change)
  local events = { 'clicked', 'change', 'focusIn', 'focusOut' }
  if _Strips then
    _Strips.action(control, events[change] or 'unknown', _Strips)
  end
end

local function Dispatch(handlers, ...)
  local ret = false
  local idx
  for i,fn in ipairs(handlers) do
    ret = fn(...)
    if ret then idx=i; break end
  end
  for i=(idx or #handlers),1,-1 do
    local fn = handlers[i]
    if handlers[fn] then
      handlers[fn] = nil
      table.remove(handlers,i)
    end
  end
  return ret
end

-- these are the standard SciTE Lua callbacks - we use them to call installed extman handlers!
function OnMarginClick()
  return Dispatch(_MarginClick)
end

function OnDoubleClick()
  return Dispatch(_DoubleClick)
end

function OnSavePointLeft()
  return Dispatch(_SavePointLeft)
end

function OnSavePointReached()
  return Dispatch(_SavePointReached)
end

function OnChar(ch)
  return Dispatch(_Char,ch)
end

function OnSave(file)
  return Dispatch(_Save,file)
end

function OnBeforeSave(file)
  return Dispatch(_BeforeSave,file)
end

function OnSwitchFile(file)
  return Dispatch(_SwitchFile,file)
end

function OnOpen(file)
  return Dispatch(_Open,file)
end

function OnUpdateUI()
  if editor.Focus then
    return Dispatch(_UpdateUI)
  else
    return false
  end
end

-- new with 1.74
function OnKey(key,shift,ctrl,alt)
  return Dispatch(_Key,key,shift,ctrl,alt)
end

function OnDwellStart(pos,s)
  return Dispatch(_DwellStart,pos,s)
end

function OnClose()
  return Dispatch(_Close)
end

-- may optionally ask that this handler be immediately
-- removed after it's called
---- add a handler:                            param=nil
---- add a handler for once-only execution:    param='once'
---- remove a handler:                         param='remove'
local function append_unique(handlers,fn,param)
  local idx
  for i,handler in ipairs(handlers) do
    if handler == fn then idx = i; break end
  end
  if idx and (param == "remove") then
    table.remove(handlers, idx)
  elseif not idx and (param ~= "remove") then
    table.insert(handlers, fn)
  end
  handlers[fn] = (param=="once") or nil
end

-- this is how you register your own handlers with extman
function extman.OnMarginClick(fn,param)
  append_unique(_MarginClick,fn,param)
end

function extman.OnDoubleClick(fn,param)
  append_unique(_DoubleClick,fn,param)
end

function extman.OnSavePointLeft(fn,param)
  append_unique(_SavePointLeft,fn,param)
end

function extman.OnSavePointReached(fn,param)
  append_unique(_SavePointReached,fn,param)
end

function extman.OnOpen(fn,param)
  append_unique(_Open,fn,param)
end

function extman.OnSwitchFile(fn,param)
  append_unique(_SwitchFile,fn,param)
end

function extman.OnBeforeSave(fn,param)
  append_unique(_BeforeSave,fn,param)
end

function extman.OnSave(fn,param)
  append_unique(_Save,fn,param)
end

function extman.OnUpdateUI(fn,param)
  append_unique(_UpdateUI,fn,param)
end

function extman.OnChar(fn,param)
  append_unique(_Char,fn,param)
end

function extman.OnOpenSwitch(fn,param)
  append_unique(_OpenSwitch,fn,param)
end

--new 1.74
function extman.OnKey(fn,param)
  append_unique(_Key,fn,param)
end

function extman.OnDwellStart(fn,param)
  append_unique(_DwellStart,fn,param)
end

function extman.OnClose(fn,param)
  append_unique(_Close,fn,param)
end

local function buffer_switch(filename)
--- OnOpen() is also called if we move to a new folder
  if not find(filename,'[\\/]$') then
    Dispatch(_OpenSwitch,filename)
  end
end

extman.OnOpen(buffer_switch)
extman.OnSwitchFile(buffer_switch)

-- the handler is always reset!
function extman.UserListShow(list,start,fn)
  local next_user_id = 13 -- arbitrary
  local separators = {'\1', '\2', '\3', '\4', ' ', ';', '@', '?', '~', ':'}
  local s = table.concat(list)
  for _, sep in ipairs(separators) do
    if not string.find(s, sep, 1, true) then
      s = table.concat(list, sep, start)
      _UserListSelection = fn
      local pane = editor.Focus and editor or output
      local saved_sep = pane.AutoCSeparator
      pane.AutoCSeparator = string.byte(sep)
      pane:UserListShow(next_user_id,s)
      pane.AutoCSeparator = saved_sep
      return true
    end
  end
end

function extman.SetStripHandler(data)
  if type(data)=="table" and type(data.action)=="function" then
    _Strips = data
  end
end

local word_start, in_word, current_word
-- (Nicolas) this is in Ascii as SciTE always passes chars in this "encoding" to OnChar
local wordchars = '[A-Za-z\192-\221\224-\255]'  -- wuz %w

local function on_word_char(s)
  if not in_word then
     if find(s,wordchars) then
       -- we have hit a word!
       word_start = editor.CurrentPos
       in_word = true
       current_word = s
     end
   else -- we're in a word
     -- and it's another word character, so collect
     if find(s,wordchars) then
       current_word = current_word..s
     else
       -- leaving a word; call the handler
       Dispatch(_Word, { word=current_word, startp=word_start, endp=editor.CurrentPos, ch=s })
       in_word = false
     end
   end
   -- don't interfere with usual processing!
   return false
end

function extman.OnWord(fn,param)
  append_unique(_Word,fn,param)
  if not param then
    extman.OnChar(on_word_char)
  else
    extman.OnChar(on_word_char,'remove')
  end
end

local function get_line(pane,lineno)
  pane = pane or editor
  if not lineno then
    local line_pos = pane.CurrentPos
    lineno = pane:LineFromPosition(line_pos)-1
  end
  -- strip linefeeds (Windows is a special case as usual!)
  local endl = 2
  if pane.EOLMode == 0 then endl = 3 end
  local line = pane:GetLine(lineno)
  if not line then return nil end
  return string.sub(line,1,-endl)
end

-- export this useful function...
extman.Line = get_line

local function on_line_char(ch,was_output)
  if ch == '\n' then
    local in_editor = editor.Focus
    if in_editor and not was_output then
      Dispatch(_LineEd,get_line(editor))
      return false -- DO NOT interfere with any editor processing!
    elseif not in_editor and was_output then
      Dispatch(_LineOut,get_line(output))
      return true -- prevent SciTE from trying to evaluate the line
    end
  end
  return false
end

local function on_line_editor_char(ch)
  return on_line_char(ch,false)
end

local function on_line_output_char(ch)
  return on_line_char(ch,true)
end

local function set_line_handler(fn,rem,handler,on_char)
  append_unique(handler,fn,rem)
  if not rem then
    extman.OnChar(on_char)
  else
    extman.OnChar(on_char,'remove')
  end
end

function extman.OnEditorLine(fn,rem)
  set_line_handler(fn,rem,_LineEd,on_line_editor_char)
end

function extman.OnOutputLine(fn,rem)
  set_line_handler(fn,rem,_LineOut,on_line_output_char)
end


local path_pattern
local tempfile
local dirsep

if GTK then
  tempfile = '/tmp/.scite-temp-files'
  path_pattern = '(.*)/[^%./]+%.%w+$'
  dirsep = '/'
else
  tempfile = '\\scite_temp1'
  path_pattern = '(.*)\\[^%.\\]+%.%w+$'
  dirsep = '\\'
end

local function path_of(s)
  return match(s,path_pattern) or s
end

local extman_path = path_of(props['ext.lua.startup.script'])
local lua_path = extman.GetProp('ext.lua.directory',extman_path..dirsep..'scite_lua')

function extman.Path()
  return extman_path
end

-- this version of scite-gdb uses the new spawner extension library.
if false then -- do
  local fn,err
  -- by default, the spawner lib sits next to extman.lua
  local spawner_path = extman.GetProp('spawner.extension.path',extman_path)
  if GTK then
    fn,err = package.loadlib(spawner_path..'/unix-spawner-ex.so','luaopen_spawner')
  else
    fn,err = package.loadlib(spawner_path..'\\spawner-ex.dll','luaopen_spawner')
  end
  if fn then
    if GTK then fn() -- register spawner
    else spawner = fn()
    end
  else
    print('cannot load spawner '..err)
  end
end

-- a general popen function that uses the spawner library if found; otherwise falls back
-- on os.execute
function extman.Popen(cmd)
  if spawner then
    return spawner.popen(cmd)
  else
    cmd = cmd..' > '..tempfile
    if GTK then -- io.popen is dodgy; don't use it!
      os.execute(cmd)
    else
      if Execute then -- scite_other was found!
        Execute(cmd)
      else
        os.execute(cmd)
      end
    end
    return io.open(tempfile)
  end
end

local function dirmask(mask,isdir)
  if not GTK then
    local attrib = isdir and ' /A:D ' or ''
    mask = gsub(mask,'/','\\')
    return 'dir /b '..attrib..extman.quote_if_needed(mask)
  else
    local attrib = isdir and ' -F ' or ''
    return 'ls -1 '..attrib..extman.quote_if_needed(mask)
  end
end

-- grab all files matching @mask, which is assumed to be a path with a wildcard.
function extman.Files(mask)
  local path,cmd
  if not GTK then
    cmd = dirmask(mask)
    path = mask:match('(.*\\)')  or '.\\'
  else
    cmd = 'ls -1 '..mask
    path = ''
  end
  local files = {}
  local f = extman.Popen(cmd)
  if f then
    for line in f:lines() do
      -- print(path..line)
      table.insert(files,path..line)
    end
    f:close()
  end
  return files
end

-- grab all directories in @path, excluding anything that matches @exclude_pat
-- As a special exception, will also any directory called 'examples' ;)
function extman.Directories(path,exclude_pat)
  local cmd
  --print(path)
  if not GTK then
    cmd = dirmask(path..'\\*.',true)
  else
    cmd = dirmask(path,true)
  end
  path = path..dirsep
  local f = extman.Popen(cmd)
  local files = {}
  if not f then return files end
  for line in f:lines() do
--  print(line)
    if GTK then
      if line:sub(-1,-1) == dirsep then
        line = line:sub(1,-2)
      else
        line = nil
      end
    end
    if line and not line:find(exclude_pat) and line:lower() ~= 'examples' then
      table.insert(files,path..line)
    end
  end
  f:close()
  return files
end

function extman.FileExists(f)
  f = io.open(f)
  if f then
    f:close()
    return true
  end
  return false
end

function extman.CurrentFile()
  return props['FilePath']
end

function extman.DirectoryExists(path)
  if GTK then
    return os.execute('test -d "'..path..'"') == true
  else
    -- os.execute('if not exist "'..path..'"\\ exit 1') == 0 --> bad: SciTE window loses focus on launching
    local lfs = require "lfs"
    return lfs.attributes(path,"mode") == "directory"
  end
end

function extman.split(s,delim)
  local res = {}
  for w in (s..delim):gmatch("(.-)%"..delim) do table.insert(res,w) end
  return res
end

function extman.splitv(s,delim)
  return unpack(extman.split(s,delim))
end

local command_number = 20
local shortcuts_used = {}
local alt_letter_map = {}
local alt_letter_map_init = false
local name_id_map = {}

-- @name : 'Smart Paste' : 'Run'                : 'Exec Lua'
-- @cmd  : 'smart_paste' : 'do_run'             : '*dofile $(FilePath)'
-- @mode : '.*'          : '.*{savebefore:yes}' : '.*'
local function set_command(name,cmd,mode)
  --print(name,cmd,mode)
  local pattern,md = match(mode,'(.+){(.+)}')
  if not pattern then
    pattern = mode
    md = 'savebefore:no'
  end
  local which = '.'..command_number..pattern
  props['command.name'..which] = name
  props['command'..which] = cmd
  props['command.subsystem'..which] = '3'
  props['command.mode'..which] = md
  name_id_map[name] = IDM_TOOLS + command_number
  return which
end

local function check_gtk_alt_shortcut(shortcut,name)
  -- Alt+<letter> shortcuts don't work for GTK, so handle them directly...
  local letter = shortcut:match('^Alt%+([A-Z])$')
  if letter then
    alt_letter_map[letter:lower()] = name
    if not alt_letter_map_init then
      alt_letter_map_init = true
      extman.OnKey(
        function(key,shift,ctrl,alt)
          if alt and key < 255 then
            local ch = string.char(key)
            if alt_letter_map[ch] then
              extman.MenuCommand(alt_letter_map[ch])
            end
          end
        end)
    end
  end
end

local function set_shortcut(shortcut,name,which)
  if shortcut == 'Context' then
    local usr = 'user.context.menu'
    if props[usr] == '' then -- force a separator
      props[usr] = '|'
    end
    props[usr] = props[usr]..'|'..name..'|'..(IDM_TOOLS+command_number)..'|'
  else
    local cmd = shortcuts_used[shortcut]
    if cmd then
      print('Error: shortcut already used in "'..cmd..'"')
    else
      shortcuts_used[shortcut] = name
      if GTK then check_gtk_alt_shortcut(shortcut,name) end
      props['command.shortcut'..which] = shortcut
    end
  end
end

-- allows you to bind given Lua functions to shortcut keys
-- without messing around in the properties files!
-- Either a string or a table of strings; the string format is either
--      menu text|Lua command|shortcut
-- or
--      menu text|Lua command|mode|shortcut
-- where 'mode' is the file extension which this command applies to,
-- e.g. 'lua' or 'c', optionally followed by {mode specifier}, where 'mode specifier'
-- is the same as documented under 'command.mode'
-- 'shortcut' can be a usual SciTE key specifier, like 'Alt+R' or 'Ctrl+Shift+F1',
-- _or_ it can be 'Context', meaning that the menu item should also be added
-- to the right-hand click context menu.
function extman.Command(list)
  if type(list) == 'string' then
    list = {list}
  end
  for _,v in ipairs(list) do
    local name,cmd,mode,shortcut
    if type(v) == 'string' then --'Switch Source/Header|switch_source_header|*.c|Shift+Ctrl+H'
      name,cmd,mode,shortcut = extman.splitv(v,'|')
    else -- if type(v) == 'table'
      name,cmd,mode,shortcut = unpack(v)
    end
    if not shortcut then
      shortcut = mode
      mode = '.*'
    else
      mode = '.'..mode
    end
    local which = set_command(name,cmd,mode)
    if shortcut then
      set_shortcut(shortcut,name,which)
    end
    command_number = command_number + 1
  end
end

-- use this to launch Lua Tool menu commands directly by name
-- (commands are not guaranteed to work properly if you just call the Lua function)
function extman.MenuCommand(cmd)
  cmd = name_id_map[cmd]
  if cmd then scite.MenuCommand(cmd) end
end

local loaded = {}
local current_filepath

-- this will quietly fail....
local function silent_dofile(f)
  if extman.FileExists(f) then
    if not loaded[f] then
      dofile(f)
      loaded[f] = true
    end
    return true
  end
  return false
end

function extman.dofile(f)
  f = extman_path..dirsep..f
  silent_dofile(f)
end

function extman.require(f)
  local path = lua_path..dirsep..f
  if not silent_dofile(path) then
    silent_dofile(current_filepath..dirsep..f)
  end
end

if not GTK then
  extman.dofile 'scite_other.lua'
end

if not extman.DirectoryExists(lua_path) then
  print('Error: directory '..lua_path..' not found')
  return
end

local function load_script_list(script_list,path)
  if not script_list then
    print('Error: no files found in '..path)
  else
    current_filepath = path
    for _,file in pairs(script_list) do
      silent_dofile(file)
    end
  end
end

-- Load all scripts in the lua_path (usually 'scite_lua'), including within any subdirectories
-- that aren't 'examples' or begin with a '_'
local script_list = extman.Files(lua_path..dirsep..'*.lua')
load_script_list(script_list,lua_path)
local dirs = extman.Directories(lua_path,'^_')
for _,dir in ipairs(dirs) do
  load_script_list(extman.Files(dir..dirsep..'*.lua'),dir)
end

function extman.WordAtPos(pos)
  if not pos then pos = editor.CurrentPos end
  local p2 = editor:WordEndPosition(pos,true)
  local p1 = editor:WordStartPosition(pos,true)
  if p2 > p1 then
    return editor:textrange(p1,p2)
  end
end

function extman.GetSelOrWord()
  local s = editor:GetSelText()
  if s == '' then
    return extman.WordAtPos()
  else
    return s
  end
end

extman.Command {
  {'Reload Script', 'reload_script', "*.lua", 'Shift+Ctrl+R'}
}

function reload_script()
 local current_file = extman.CurrentFile()
 print('Reloading... '..current_file)
 loaded[current_file] = false
 silent_dofile(current_file)
end

function extman.slashify(s)
  return s:gsub('\\','\\\\')
end

--~ require"remdebug.engine"
--~ remdebug.engine.start()
