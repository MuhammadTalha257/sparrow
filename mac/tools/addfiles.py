#!/usr/bin/env python3
"""Register new Swift files in Sparrow.xcodeproj (both targets). Usage: addfiles.py File.swift ..."""
import sys, re, random, os
pbx = os.path.join(os.path.dirname(__file__), '..', 'Sparrow.xcodeproj', 'project.pbxproj')
s = open(pbx).read()
def nid():
    while True:
        i = ''.join(random.choice('0123456789ABCDEF') for _ in range(24))
        if i not in s: return i
for name in sys.argv[1:]:
    if f'/* {name} */' in s: print('exists', name); continue
    ref = nid()
    s = s.replace('/* Begin PBXFileReference section */\n',
      f'/* Begin PBXFileReference section */\n\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n', 1)
    s = s.replace('\t\t\t\tA83D5410BD030B243ADDCFF4 /* ClaudeService.swift */,\n',
      f'\t\t\t\tA83D5410BD030B243ADDCFF4 /* ClaudeService.swift */,\n\t\t\t\t{ref} /* {name} */,\n', 1)
    for m in re.findall(r'\t\t\t\t([0-9A-F]{24}) /\* ClaudeService.swift in Sources \*/,\n', s):
        bid = nid()
        s = s.replace('/* Begin PBXBuildFile section */\n',
          f'/* Begin PBXBuildFile section */\n\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n', 1)
        s = s.replace(f'\t\t\t\t{m} /* ClaudeService.swift in Sources */,\n',
          f'\t\t\t\t{m} /* ClaudeService.swift in Sources */,\n\t\t\t\t{bid} /* {name} in Sources */,\n', 1)
    print('added', name)
open(pbx, 'w').write(s)
