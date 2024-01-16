-- Goal  : Sort lines in SciTE editor.
-- Start : 2008-11-06 by Shmuel Zeigerman

-- luacheck: globals editor props

do
  local v1,v2 = _VERSION:match("(%d+)%.(%d+)")
  if not v1 or v1*100 + v2 < 503 then
    print("Lua version 5.3 or higher is required")
    return
  end
end

local min = math.min
local tinsert = table.insert

-- Depends on: scite
local function GetDefaultEOL()
  local EOL = editor.EOLMode
  return (EOL==0 and "\r\n") or (EOL==1 and "\r") or "\n"
end

-- Depends on: scite
local function IsColumnType()
  return editor.SelectionIsRectangle
end

-- Depends on: scite
local function PutLines (lines)
  local n1 = editor:LineFromPosition(editor.SelectionStart)
  local n2 = editor:LineFromPosition(editor.SelectionEnd - 1)
  local pos1 = editor:PositionFromLine(n1)
  local pos2 = editor:PositionFromLine(n2 + 1)
  editor:SetSel(pos1,pos2)
  editor:ReplaceSel(table.concat(lines))
end

-- Iterator factory.
-- Depends on: scite
-- Depends on: data names, namely, on the following strings:
--    StringText, StringEOL, SelStart, SelEnd
local function EditorBlockLines ()
  local Lnum = editor:LineFromPosition(editor.SelectionStart)
  local Prev, Done
  return function()
    while not Done do
      local selstart = editor:GetLineSelStartPosition(Lnum)
      local line = (selstart >= 0) and editor:GetLine(Lnum)
      if not line then
        Done = true
        return (Prev and not Prev.empty) and Prev or nil
      end
      local selend = editor:GetLineSelEndPosition(Lnum)
      local linestart = editor:PositionFromLine(Lnum)
      Lnum = Lnum + 1
      local text,eol = line:match("^([^\r\n]*)([\r\n]*)$")
      local retval = Prev
      Prev = { empty=(selstart==selend); StringText=text; StringEOL=eol;
               SelStart=selstart-linestart; SelEnd=min(selend-linestart,#text) }
      if retval then return retval; end
    end
  end
end

-- Depends on: data names, namely, on the following strings:
--    StringText, SelStart, SelEnd
local function GetLines (columntype)
  local arr_index, arr_target, arr_compare = {},{},{}
  for line in EditorBlockLines() do
    tinsert(arr_index, #arr_index+1)
    tinsert(arr_target, line)
    local s = columntype and line.StringText:sub(line.SelStart+1, line.SelEnd)
      or line.StringText
    tinsert(arr_compare, s)
  end
  return arr_compare, arr_index, arr_target
end

-- Depends on: data names, namely, on the following strings:
--    StringText, StringEOL, SelStart, SelEnd
local function BuildNewText (arr_compare, arr_index, arr_target, OnlySelection, DefaultEOL)
  local tb = {}
  for i, v in ipairs(arr_index) do
    local newtext, newEOL
    if OnlySelection then
      local old = arr_target[i]
      local oldtext = old.StringText
      local blockstart, blockend = old.SelStart, old.SelEnd
      local blockwidth = blockend - blockstart
      local S = arr_compare[v]
      if #oldtext <= blockstart then
        if S == "" then newtext = oldtext
        else newtext = oldtext .. (" "):rep(blockstart - #oldtext) .. S
        end
      elseif #oldtext <= blockend then
        newtext = oldtext:sub(1, blockstart) .. S
      else
        if #S < blockwidth then S = S .. (" "):rep(blockwidth - #S) end
        newtext = oldtext:sub(1, blockstart) .. S .. oldtext:sub(blockend + 1)
      end
      newEOL = arr_target[i].StringEOL
    else
      newtext, newEOL = arr_target[v].StringText, arr_target[v].StringEOL
    end
    tb[#tb+1] = newtext .. (newEOL ~= "" and newEOL or DefaultEOL)
  end
  return tb
end

-- almost generic
local function Column (subj, colnum, colpat)
  for A in subj:gmatch(colpat) do
    if colnum == 1 then return A end
    colnum = colnum - 1
  end
end

local template = [[
local _Column, _ColPat, L = ...
local _A
local N  = tonumber
local C  = function(n) return _Column(_A,n,_ColPat) end
local LC = function(n) return L(C(n)) end
local NC = function(n) return N(C(n)) end
return function(a, i) _A=a return %s end
]]

-- almost generic
local function compile(expr, fieldname, env, colpat)
  local func = assert(load(template:format(expr), fieldname, "t", env))
  return func(Column, colpat, string.lower)
end

-- generic
local function DoSort (arr_compare, arr_index, arr_dialog)
  local function cmp(i1, i2)
    local a, b = arr_compare[i1], arr_compare[i2]
    for _, data in ipairs(arr_dialog) do
      local v1, v2 = data.expr(a, i1), data.expr(b, i2)
      if v1 ~= v2 then
        if type(v1) == "string" then
          v1 = assert(data.func(v1,v2), "compare function failed")
          v2 = 0
        end
        if v1 > v2 then return data.rev end
        if v1 < v2 then return not data.rev end
      end
    end
    return i1 < i2 -- this makes sort stable
  end
  table.sort(arr_index, cmp)
end

-- give expressions read access to the global table
local meta = { __index=_G }

-- Depends on: data names, namely, on the following strings:
--    edtColPat
--    cbxFileName, edtFileName
--    cbxUse1, edtExpr1, cbxRev1
--    cbxUse2, edtExpr2, cbxRev2
--    cbxUse3, edtExpr3, cbxRev3
local function GetExpressions (aData, env)
  if aData.cbxFileName then
    local chunk = assert(loadfile(aData.edtFileName, "t", env))
    chunk()
  end
  local arr_dialog = {}
  for i = 1,3 do
    if aData["cbxUse"..i] then
      local expr, rev = aData["edtExpr"..i], aData["cbxRev"..i]
      local func = function(v1,v2) return v1==v2 and 0 or v1<v2 and -1 or 1; end
      tinsert(arr_dialog, {
        expr = compile(expr, "Expression "..i, env, aData.edtColPat),
        rev = rev or false,
        func = func})
    end
  end
  return arr_dialog
end

-- generic
local function SortWithRawData (aData, columntype)
  local env = setmetatable({}, meta)
  local arr_dialog = GetExpressions(aData, env)
  if #arr_dialog == 0 then
    return  -- no expressions available
  end
  local arr_compare, arr_index, arr_target = GetLines(columntype)
  if #arr_compare < 2 then
    return  -- nothing to sort
  end
  env.I = #arr_index
  DoSort(arr_compare, arr_index, arr_dialog)
  -- put the sorted lines into the editor
  local OnlySelection = columntype and aData.cbxOnlySel
  local EOL = GetDefaultEOL()
  local lines = BuildNewText(arr_compare, arr_index, arr_target, OnlySelection, EOL)
  PutLines(lines)
end

-- Keep it as an upvalue to preserve data during a SciTE session
local DialogData = {
  cbxUse1=true;  edtExpr1="a"; cbxCase1=false;  cbxRev1=false;
  cbxUse2=false; edtExpr2="";  cbxCase2=false;  cbxRev2=false;
  cbxUse3=false; edtExpr3="";  cbxCase3=false;  cbxRev3=false;

  cbxFileName = false; edtFileName = "";
  edtColPat   = "%S+";
  cbxOnlySel  = false;
}

function smz_SortLines()
  -- Create a strip
  local Strip = {
    "'Expression:'",     "[]", "(&Direct Sort)",  -- 0,1,2
    "\n",
    "'Column Pattern:'", "[]", "(&Reverse Sort)", -- 3,4,5
    "\n",
    "'Only selected:'",  "{}", "(&Cancel)",       -- 6,7,8
  }
  local edtExpr1,   btnDirect  = 1,2
  local edtColPat,  btnReverse = 4,5
  local cbxOnlySel, btnCancel  = 7,8

  scite.StripShow(table.concat(Strip))
  scite.StripSet(edtExpr1, DialogData.edtExpr1)
  scite.StripSet(edtColPat, DialogData.edtColPat)
  scite.StripSetList(cbxOnlySel, "No\nYes")
  scite.StripSet(cbxOnlySel, DialogData.cbxOnlySel and "Yes" or "No")

  extman.SetStripHandler {
    action = function(control, msg, data)
      if msg == "clicked" then
        if control == btnCancel then
          scite.StripShow("")
        else
          DialogData.edtExpr1   = scite.StripValue(edtExpr1)
          DialogData.edtColPat  = scite.StripValue(edtColPat)
          DialogData.cbxRev1    = (control == btnReverse)
          DialogData.cbxOnlySel = (scite.StripValue(cbxOnlySel) == "Yes")
          SortWithRawData (DialogData, IsColumnType())
        end
      end
    end;
  }
end
