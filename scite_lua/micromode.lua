-- micromode.lua introduces Sciboo-style 'micro-modes' to SciTE.
-- For instance, if your C file begins like this:
-- // build@ gcc fred.c alice.o -o fred
-- then that will set the property command.build.* to 'gcc fred.c alice.o -o fred'.
--
-- General format is '<operation>@ <command> <args>'
-- build,compile and go are valid operations; otherwise, the name is assumed to
-- be a global Lua function that will handle this build operation
-- If the args end with a single '*', it will be replaced with $(FileNameExt)
-- (As an extension, if the command is a GNU-style compiler, then '- o $(FileName)'
-- is appended as well, so that 'build@ gcc *' will work as expected.)
-- If the command is a valid global Lua function, it will be used instead. So:
--  --go@ dofile *
-- will mean that a Lua script is to be run using SciTE Lua.

local compile_tool = {gcc=1,['g++']=2,gfortran=1,g95=1}

local propset = {}

local function check_micro_mode(f)
    if #propset > 0 then -- very important to keep clearing these guys out!
        for _,k in ipairs(propset) do
            props[k] = nil
        end
        propset = {}
    end
    local line =  extman.Line(editor,0)
    if not line then return end
    local _,_,p,val = line:find('([a-z]+)@%s+(.+)')
    if _ then
        local custom_build, lua_function
        if p ~= 'build' and p ~= 'compile' and p ~= 'go' then
            custom_build = p
            p = 'build'
        end
        local prop = 'command.'..p..'.*'
        if val:sub(1,1) == '$' then -- might have been a property expansion!
            val = val:sub(3,-2)
            val = props[val]
        end
        if val == "" then return end
        local cmd = val:match('^(%S+)')
        if val:find('%*$') then
            val = val:sub(1,-2) .. '$(FileNameExt)'
            if compile_tool[cmd] then
                val = val .. ' -o $(FileName)'
            end
        end
        lua_function = cmd and _G[cmd]
        if not custom_build and not lua_function then
            props[prop] = val
        else
            local subsys
            -- a Lua function; use the 3 subsystem to evaluate it!
            if custom_build then
                props[prop] = custom_build..' '..val
                subsys = 'command.build.subsystem.*'
            else
                props[prop] = val
                subsys = 'command.go.subsystem.*'
            end
            props[subsys] = '3'
            table.insert(propset,subsys)
        end
        table.insert(propset,prop)
    end
end

extman.OnOpenSwitch(check_micro_mode)
extman.OnSave(check_micro_mode)

