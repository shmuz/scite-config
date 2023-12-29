extman.Command 'Exec Lua|*dofile $(FilePath)|*.lua|Shift+Ctrl+E'

if false then
  extman.Command 'Surround with code|do_code|*.html|Ctrl+J'

  --luacheck: new_globals do_code
  function do_code()
      local txt = editor:GetSelText()
      if txt then
          editor:ReplaceSel('<code>'..txt..'</code>')
      end
  end
end

if false then
  local substitutions = {teh='the',wd='would',cd='could'}

  extman.OnWord (function(w)
    local subst = substitutions[w.word]
    if subst then
        editor:SetSel(w.startp-1,w.endp-1)
        local was_whitespace = string.find(w.ch,'%s')
        if was_whitespace then
           subst = subst..w.ch
        end
        editor:ReplaceSel(subst)
        if not was_whitespace then
           editor:GotoPos(editor.CurrentPos + 1)
        end
    end
  end)
end
