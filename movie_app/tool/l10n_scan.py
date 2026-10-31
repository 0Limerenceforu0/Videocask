"""扫描硬编码中文文案（用户可见），用于评估 l10n 化工作量。

用法：python tool/l10n_scan.py [--list]
"""
import json
import os
import re
import sys
from collections import Counter

# 只匹配"用户可见文案"的典型位置，避免把日志/异常信息误计入
PATTERNS = [
    re.compile(r"""(?:Text|SelectableText|Tooltip)\s*\(\s*'([^']*[\u4e00-\u9fff][^']*)'"""),
    re.compile(r"""\b(?:label|labelText|hintText|helperText|errorText|tooltip)\s*:\s*'([^']*[\u4e00-\u9fff][^']*)'"""),
    re.compile(r"""\b(?:title|subtitle|content|message|confirmText|cancelText)\s*:\s*'([^']*[\u4e00-\u9fff][^']*)'"""),
    re.compile(r"""SnackBar\(\s*content:\s*Text\(\s*'([^']*[\u4e00-\u9fff][^']*)'"""),
]

ARB = 'lib/l10n/app_zh.arb'


def arb_keys(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as fh:
        data = json.load(fh)
    return [k for k in data if not k.startswith('@')]


def scan():
    counter = Counter()
    per_file = {}
    for base in ('lib',):
        for dp, _, names in os.walk(base):
            for name in names:
                if not name.endswith('.dart'):
                    continue
                path = os.path.join(dp, name)
                src = open(path, encoding='utf-8').read()
                for pat in PATTERNS:
                    for m in pat.finditer(src):
                        text = m.group(1)
                        # 跳过 unicode 转义写法，它们本来就是显式转义
                        if '\\u' in text:
                            continue
                        counter[text] += 1
                        per_file.setdefault(path, []).append(text)
    return counter, per_file


def main():
    counter, per_file = scan()
    keys = arb_keys(ARB)
    print('arb 已有词条: %d' % len(keys))
    print('硬编码中文: 去重 %d 条 / 出现 %d 次 / 涉及 %d 个文件'
          % (len(counter), sum(counter.values()), len(per_file)))
    print()
    print('=== 文件分布 TOP 15 ===')
    for path, items in sorted(per_file.items(), key=lambda x: -len(x[1]))[:15]:
        print('%4d  %s' % (len(items), path.replace('/', os.sep)))
    if '--list' in sys.argv:
        print()
        print('=== 全部文案（按频次）===')
        for text, n in counter.most_common():
            print('%3d  %s' % (n, text))
    else:
        print()
        print('=== 高频文案 TOP 20 ===')
        for text, n in counter.most_common(20):
            print('%3d  %s' % (n, text))


if __name__ == '__main__':
    main()
