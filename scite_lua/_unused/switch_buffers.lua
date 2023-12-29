--switch_buffers.lua
--drops down a list of buffers, in recently-used order

-- luacheck: new_globals do_buffer_list last_buffer
extman.Command 'Switch Buffer|do_buffer_list|Alt+F12'
extman.Command 'Last Buffer|last_buffer|Ctrl+F12'

local buffers = {}
local remove = table.remove
local insert = table.insert

extman.OnOpenSwitch(function(f)
--- swop the new current buffer with the last one!
    local idx
    for i,file in ipairs(buffers) do
        if file == f then  idx = i; break end
    end
    if idx then
        remove(buffers,idx)
        insert(buffers,1,f)
    else
        insert(buffers,1,f)
    end
end)

function last_buffer()
    if #buffers > 1 then
        scite.Open(buffers[2])
    end
end

function do_buffer_list()
    if not extman.GetPropBool('buffer.switch.fullpath',false) then
        local files = {}
        for i = 1,#buffers do
            files[i] = basename(buffers[i])
        end
        extman.UserListShow(files,2,function(s)
            for i = 1,#files do
                if s == files[i] then
                    scite.Open(buffers[i])
                end
            end
        end)
    else
        extman.UserListShow(buffers,2,scite.Open)
    end
end

