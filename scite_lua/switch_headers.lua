-- toggles between C++ source files and corresponding header files

-- luacheck: new_globals switch_source_header
extman.Command('Switch Source/Header|switch_source_header|*.cpp;*.cxx;*.c++;*.c;*.h;*.hpp|Shift+Ctrl+H')
local cpp_exts = {'cpp','cxx','c++','c'}
local hpp_exts = {'h','hpp'}

local function within(list,val)
  for _,v in ipairs(list) do
     if val == v then return true end
  end
  return false
end

local function does_exist(basename,extensions)
  for _,ext in ipairs(extensions) do
    local f = basename..'.'..ext
    if extman.FileExists(f) then return f end
  end
  return nil
end

function switch_source_header()
   local file = props['FilePath']
   local ext = props['FileExt']
   local basename = props['FileDir']..'/'..props['FileName']
   local other
   if within(cpp_exts,ext) then
      other = does_exist(basename,hpp_exts)
   elseif within(hpp_exts,ext) then
      other = does_exist(basename,cpp_exts)
   else
      print('not a C++ file',file); return
   end
   if not other then
      print('source/header does not exist',file)
   else
      scite.Open(other)
   end
 end
