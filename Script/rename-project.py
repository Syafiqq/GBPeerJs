#!/usr/bin/env python3

import os
import fileinput

rootDir = './'
rootDir = os.path.abspath(rootDir)
fromKey = 'GBProjectTemplate'
toKey = 'GBPeerJs'

for dirName, subdirList, fileList in os.walk(rootDir, topdown=False):
  if fromKey in os.path.basename(dirName):
    dirname = os.path.dirname(dirName)
    basename = os.path.basename(dirName)
    resolvedname = dirname + '/' + basename.replace(fromKey, toKey)
    # print()
    # print('Dirname to %s' % dirName)
    # print('Replace to %s' % resolvedname)
    # print()
    os.rename(dirName, resolvedname)

for dirName, subdirList, fileList in os.walk(rootDir, topdown=False):
  if '.git' not in dirName and '.idea' not in dirName and 'Pods' not in dirName:
    for fname in fileList:
      dirname = dirName
      basename = fname
      filename = dirname + '/' + basename
      resolvedname = dirname + '/' + basename.replace(fromKey, toKey)
      os.rename(filename, resolvedname)

for dirName, subdirList, fileList in os.walk(rootDir, topdown=False):
  if '.git' not in dirName and '.idea' not in dirName and 'Pods' not in dirName:
    for fname in fileList:
      dirname = dirName
      basename = fname
      filename = dirname + '/' + basename
      if '.DS_Store' not in basename and 'rename-project.py' not in basename and 'xcuserstate' not in basename:
        with fileinput.FileInput(filename, inplace=True, backup='.bak') as file:
          for line in file:
            print(line.replace(fromKey, toKey), end='')
        os.remove(filename + '.bak')
