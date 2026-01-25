#!/usr/bin/env python3

import requests
import re

f = open("Sources/GBPeerJs/Script/loco-whitelist.txt", "r")
whitelist = dict.fromkeys(f.read().splitlines(), 1)
f.close()

lang = [
    {
        'request': 'https://localise.biz/api/export/locale/en.strings?fallback=en&no-comments=1&key=4KDSKnNq2ywUlUmkrkdxITznT9v103az',
        'path': 'Sources/GBPeerJs/GBPeerJs/i18n/en.lproj/Localizable.strings'
    },
    {
        'request': 'https://localise.biz/api/export/locale/vi.strings?fallback=en&no-comments=1&key=4KDSKnNq2ywUlUmkrkdxITznT9v103az',
        'path': 'Sources/GBPeerJs/GBPeerJs/i18n/vi.lproj/Localizable.strings'
    },
    {
        'request': 'https://localise.biz/api/export/locale/id.strings?fallback=en&no-comments=1&key=4KDSKnNq2ywUlUmkrkdxITznT9v103az',
        'path': 'Sources/GBPeerJs/GBPeerJs/i18n/id.lproj/Localizable.strings'
    },
    {
        'request': 'https://localise.biz/api/export/locale/zh.strings?fallback=en&no-comments=1&key=4KDSKnNq2ywUlUmkrkdxITznT9v103az',
        'path': 'Sources/GBPeerJs/GBPeerJs/i18n/zh-Hans.lproj/Localizable.strings'
    }
]
for lan in lang:
  response = requests.get(lan['request'])
  rawText = response.text.splitlines()
  result = []
  for raw in rawText:
    candidate = re.findall(r'"([^"]*)"', raw.split("=")[0])
    if len(candidate) > 0 and candidate[0] in whitelist:
      result.append(raw)

  with open(lan['path'], 'w') as f:
    for item in result:
      f.write("%s\n" % item)
