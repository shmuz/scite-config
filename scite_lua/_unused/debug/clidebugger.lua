-- Clidebug is  used for local Lua debugging sessions
extman.require 'debugger.lua'
local find = string.find
local match  = string.match
local GTK = extman.GetProp('PLAT_GTK')

-- the convention with cli debug is that all Windows filenames are lowercase!
local function canonical(file)
    if not GTK then file = file:lower() end
    return file
end

local function fpath(file)
    return canonical(fullpath(file))
end

-- 'eval' has been added to cli debugger; works exactly like remDebug.
local p_pattern = '^= '
local p_error_pattern = 'Run error: %[[^%]]%]:%d+:(.+)'
--local p_error_pattern = 'Run error:'

local function print_process(s,dbg)
    local err = s:match(p_error_pattern)
    if err then
        s = '(error)'..err
    else
        s = s:sub(3)
    end
    display(dbg.last_arg..' = '..s)
end

-- special actions for commands which require postprocessing
local postprocess_command = {
    eval = {pattern=p_pattern, action=print_process, single_pattern=true,
            alt_pat = p_error_pattern},
}

-- local function backslash(path)
--   return path:gsub('\\','/')
-- end

Clidebug = class(Dbg)

function Clidebug.discriminator(target)
    return find(target,'^:') == nil -- otherwise, we want remDebug!
end

function Clidebug:init(root)
    self.prompt = 'DBG' --'[DEBUG]>'
    self.no_target_ext = false
    self.cmd_file = join(root,'clidebug.cmd')
    -- find out where the Lua executable is; you can use the debug.lua property if it isn't the same
    -- as your lua executable specified in lua.properties.
    self.lua = extman.GetProp("debug.lua")
    if not self.lua then
        self.lua = extman.GetProp('command.go.*.lua'):match('^(%S+)')
    end
    -- this is added to the package.path of the Lua program
    self.clidebug_path = extman.GetProp('clidebug.path',join(extman.Path(),'lua_clidebugger'))
    self.clidebug_debugger = join(self.clidebug_path,'debugger.lua')
    if not GTK then
        self.clidebug_debugger = self.clidebug_debugger:lower() -- the lower here is a Windows peculiarity...
    end
    print('clidebug',self.clidebug_debugger)
    self.no_quit_confirm = true
    self.skip_system_extension = ".lua"
--  local drive = '';
    -- clidebug doesn't give fullpath
--  if not GTK then  = '[a-zA-Z]:' end
    -- slightly different from remDebug
    -- *NB* doesn't handle [thread] thingy! Easiest to put this elsewhere??
    self.break_line = '^Paused at file ([^%s]+) line (%d+)'
    self.silent_command = {}
    self.postprocess_command = postprocess_command
end

function Clidebug:command_line(target)
  self.target = target
    self.target_dir = props['FileDir']
    local ppath = extman.slashify(join(self.clidebug_path,'?.lua;'))
    return string.format('%s -e "package.path=\'%s\'..package.path" -lclidebug %s %s',
  --                   self.lua, ppath, self.target, self:parameter_string())
                       self.lua, ppath, props['FilePath'], self:parameter_string())
end

function Clidebug:dump_breakpoints(out)
    for b in Breakpoints() do
        -- note: different order to remDebug. *RD!
        out:write('setb '..b.line..' '..canonical(b.file)..'\n')
    end
end

-- {{{ these methods are common
function Clidebug:run_program(out,parms)
    self.target_dir = props['FileDir']
    if not GTK then self.target_dir = self.target_dir:lower() end
    out:write('rootpath '..self.target_dir..'\n')
  out:write('run\n')
end

function Clidebug:step()
    dbg_command('step')
end

function Clidebug:step_over()
    dbg_command('over')
end

function Clidebug:finish()
    dbg_command('out')
end

function Clidebug:continue()
    dbg_command('run')
end

--}}}

function Clidebug:quit()
    dbg_command('os.exit(0)')
end

function Clidebug:inspect(word)
    dbg_command('eval',word)
end

--RD!
-- these function will only pass us the filename part, not the path!
function Clidebug:set_breakpoint(file,lno)
    dbg_command('setb',lno..' '..fpath(file))
end

--RD!
function Clidebug:clear_breakpoint(file,line,num)
    if file then
        dbg_command('delb',line..' '..fpath(file))
    else
        print ('no breakpoint at '..file..':'..line)
    end
end

function Clidebug:backtrace(count)
    dbg_command('trace')
end

function Clidebug:finish()
    dbg_command('out')
end

-- this is not quite precisely right....
function Clidebug:locals()
    dbg_command('vars')
end

function Clidebug:frame(idx)
    dbg_command('set',idx)
end

function Clidebug:detect_program_end(line)
    return find(line,'^Program finished')
end

function Clidebug:goto_file_line(file,line)
    ProcessOutput("Paused at file "..self.target_dir..'/'..file.." line "..line..'\n')
end

-- there is some clidebugger hackery going on here. It will put us into its own version of debug.stacktrace,
-- and we need to put the program into frame #3, which is where the wobby originally happened. The usual Lua
-- error message is put out by the 'Message: ' line, which we use to capture the file:line needed to jump to.
-- The jumping is achieved by pushing the correct break pattern back into the input above (there must be
-- a more elegant way of doing this!)
local fmsg,lmsg

function Clidebug:find_execution_break(line)
    local _,_,file,lineno = find(line,self.break_line)
    if _ then
--      print('gotcha',file)
        if file == self.clidebug_debugger and fmsg then -- our program threw a wobbly!
            self:frame(3)
            return fmsg,lmsg,true
        else
            return file,lineno
        end
    else
        local f,l = match(line,'Message: (%S+):(%d+)')
        if f then
            fmsg = f
            lmsg = l
        end
    end
end

function Clidebug:detect_frame(line)
    local frame,file,lnum = match(line,'%[(%d+)%]%s+%w+ in (%S+):(%d+)')
    if frame then
        self:frame(frame)
        self:goto_file_line(file,lnum)
    end
end

register_debugger('clidebug','lua',Clidebug)
