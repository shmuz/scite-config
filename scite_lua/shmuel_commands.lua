-- Started 2008-11-06 by Shmuel Zeigerman
-- luacheck: globals smz_Compile smz_GitRestore smz_InsertDate smz_InsertGUID

extman.Command {
  { "Compile CPP-file" , "smz_Compile"    , "*.cpp{savebefore:yes}", "Alt+F9" },
  { "Git Restore"      , "smz_GitRestore" ,                },
  { "Insert Date"      , "smz_InsertDate" , "Ctrl+Shift+T" },
  { "Insert GUID"      , "smz_InsertGUID" , "Ctrl+F11"     },
  { "Sort Lines"       , "smz_SortLines"  , "Ctrl+M"       },
}
--------------------------------------------------------------------------------

function smz_InsertGUID()
  if extman.GetProp('PLAT_GTK') then
    local fp = io.popen("uuidgen")
    if fp then
      local str = '"'..fp:read("*l"):upper()..'"'
      editor:AddText(str)
      fp:close()
    end
  else
    local su = require "sysutils"
    local str = '"'..su.Uuid(su.Uuid()):upper()..'"'
    editor:AddText(str)
  end
end
--------------------------------------------------------------------------------

function smz_InsertDate()
  local patterns = {
      "%Y-%m-%d",
      "%Y-%m-%d, %a",
      "%Y-%m-%d %H:%M",
      "%Y-%m-%d %H:%M:%S",
      "[%Y-%m-%d]",
      "[%Y-%m-%d, %a]",
      "[%Y-%m-%d %H:%M]",
      "[%Y-%m-%d %H:%M:%S]",
    }
  local list, time = {}, os.time()
  for i,pat in ipairs(patterns) do
    local txt = os.date(pat, time)
    list[i], list[txt] = txt, pat
  end
  extman.UserListShow(list, 1,
    function(txt)
      local pane = editor.Focus and editor or output
      pane:AddText( os.date(list[txt]) )
      return true -- no further handlers should be called
    end)
end
--------------------------------------------------------------------------------

local FAR2M_Includes

local function get_far2m_includes()
  if not FAR2M_Includes then
    local list = {
      ".",
      "../_build/far",
      "../utils/include",
      "../WinPort",
      "far2sdk",
      "src",
      "src/base",
      "src/bookmarks",
      "src/cfg",
      "src/console",
      "src/filemask",
      "src/hist",
      "src/locale",
      "src/macro",
      "src/mix",
      "src/panels",
      "src/plug",
      "src/vt",
    }
    for k,v in ipairs(list) do list[k] = "-I"..v; end
    FAR2M_Includes = table.concat(list, " ")
  end
  return FAR2M_Includes
end

local function RunShellCommand(command)
  print(">"..command)
  local fp, msg = io.popen(command)
  if fp then
    local curpos = output.CurrentPos
    for ln in fp:lines() do print(ln) end
    if fp:close() then
      print("SUCCESS")
    else
      output:GotoPos(curpos)
    end
  else
    print(msg)
  end
end

function smz_Compile()
  if nil == props.FilePath:match("/far2m/far/src/") then
    print("OUTSIDE THE WORK TREE"); return
  end

  local incl = get_far2m_includes()
  local dir_start = "~/repos/far2m/far"
  local flags = "-std=c++17 -Wall -fPIC -D_FILE_OFFSET_BITS=64 -DUNICODE"
  local command = ("cd %s && g++ %s %s -c %s -o /tmp/far2m_tmp.o 2>&1"):format(
    dir_start, incl, flags, props.FilePath:match("src/.+"))
  RunShellCommand(command)
end

function smz_GitRestore()
  local command = ("git restore ")..props.FilePath
  RunShellCommand(command)
end
--------------------------------------------------------------------------------
