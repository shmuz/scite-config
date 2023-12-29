-- go@ dofile *
    l = editor:LineFromPosition(editor.CurrentPos)
print(l)
line = extman.Line(editor,l)
indent = line:match('(%s+)')
print(indent..'gotcha',#indent)


