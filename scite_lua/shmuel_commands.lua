-- Started 2008-11-06 by Shmuel Zeigerman
-- luacheck: globals smz_SortLines smz_InsertGUID smz_InsertDate smz_StripTest smz_Compile

extman.Command {
--{"Sort Lines",    "smz_SortLines",  "Ctrl+M"},
--{"Insert GUID",   "smz_InsertGUID", "Ctrl+F11"},
  {"Insert Date",   "smz_InsertDate", "Ctrl+Shift+T"},
  {"Strip example", "smz_StripTest",  "Ctrl+F10"},
  {"Compile CPP-file", "smz_Compile", "*.cpp{savebefore:yes}", "Alt+F9"},
}
--------------------------------------------------------------------------------

-- function smz_SortLines()
--   require("scite.sortlines")()
-- end
--------------------------------------------------------------------------------

-- function smz_InsertGUID()
--   local su = require "sysutils"
--   local str = '"' .. su.Uuid(su.Uuid()):upper() .. '"'
--   editor:AddText(str)
-- end
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

function smz_StripTest()
    if false and editor.SelectionStart == editor.SelectionEnd then
        scite.StripShow("")
        return
    end

    -- create a strip
    local t = {
      "!", "'Explanation:'", "{}", "(&Search)", -- 0,1,2
      "\n",
      "'Name:'", "[Name]", "(OK)", "(Cancel)"   -- 3,4,5,6
    }
    scite.StripShow(table.concat(t))
    local cmbFruit, btnSearch = 1,2
    local edtName, btnOK, btnCancel = 4,5,6
    scite.StripSetList(cmbFruit, "Apple\nBanana\nLemon\nOrange\nPear\nKiwi")
    scite.StripSet(cmbFruit, "<choose a fruit>")
    scite.StripSet(edtName, "A Ionger name")

    -- set the strip handler
    extman.SetStripHandler {
      action = function(control, change, data)
        if control == btnSearch and change == 'clicked' then
          print('Search for ' .. scite.StripValue(cmbFruit))
        else
          print('OnStrip ' .. control .. ' ' .. change)
        end
      end;
    }
end
--------------------------------------------------------------------------------

function smz_Compile()
  if nil == props.FilePath:match("/far2m/far/src/") then
    print("OUTSIDE THE WORK TREE"); return
  end

  local incl = {
    "far2sdk", "src", "src/base", "src/mix", "src/bookmarks", "src/cfg", "src/console",
    "src/filemask", "src/hist", "src/locale", "src/macro", "src/panels", "src/plug", "src/vt",
    "../WinPort", "../utils/include", "../_build/far" }
  for k,v in ipairs(incl) do incl[k] = "-I"..v; end
  incl = table.concat(incl, " ")

  local dir_start = "~/far2m/far"
  local flags = "-std=c++11 -Wall -fPIC -Wno-unused-function -D_FILE_OFFSET_BITS=64"
  local command = ("cd %s && g++ %s %s -c %s -o /tmp/far2m_tmp.o 2>&1"):format(
    dir_start, incl, flags, props.FilePath:match("src/.+"))

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
--------------------------------------------------------------------------------
