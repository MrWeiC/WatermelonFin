#!/usr/bin/env python3
"""Build a screenshot report from named XCTest attachments and actual result trees.
Usage: build_media_report.py OUTPUT device=result.xcresult [device=retry.xcresult ...]
Later runs replace individual case outcomes while preserving the run history.
"""
import html
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
latest = {}
device_labels = {}
history = []
playback_evidence = []
private_screens = {'tab-Settings.png', '15-live-diagnostics.png'}

def cases(nodes):
    for node in nodes:
        if node.get('nodeType') == 'Test Case':
            yield node
        yield from cases(node.get('children', []))

for argument in sys.argv[2:]:
    device, bundle = argument.split('=', 1)
    tree = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', bundle]))
    if tree.get('devices'):
        info = tree['devices'][0]
        device_labels[device] = info['deviceName'] + ' / OS ' + info['osVersion']
    results = list(cases(tree['testNodes']))
    history.append({'group': device, 'bundle': Path(bundle).name, 'devices': tree.get('devices'), 'cases': [{'test': n['nodeIdentifier'], 'result': n.get('result')} for n in results]})
    for node in results:
        if node.get('result') in ('Passed', 'Failed', 'Skipped'):
            latest[(device, node['nodeIdentifier'])] = node['result']
    with tempfile.TemporaryDirectory(prefix='watermelon-report-') as temp:
        subprocess.run([sys.executable, str(Path(__file__).with_name('export_screenshots.py')), bundle, temp], check=True, stdout=subprocess.DEVNULL)
        attachments = Path(temp) / 'attachments'
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', str(attachments)], check=True, stdout=subprocess.DEVNULL)
        for test in json.loads((attachments / 'manifest.json').read_text()):
            for attachment in test.get('attachments', []):
                if attachment.get('suggestedHumanReadableName', '').startswith('server-playback-'):
                    record = json.loads((attachments / attachment['exportedFileName']).read_text())
                    playback_evidence.append({'group': device, 'bundle': Path(bundle).name, 'timestamp': attachment.get('timestamp'), 'paused': record.get('paused'), 'positionSeconds': (record.get('positionTicks') or 0) / 10_000_000, 'audioIndex': record.get('audioIndex'), 'subtitleIndex': record.get('subtitleIndex')})
        folder = output / 'after' / device
        folder.mkdir(parents=True, exist_ok=True)
        for source in Path(temp).glob('*.png'):
            # Keep screenshots containing account/server connection details local to xcresult.
            if source.name not in private_screens:
                shutil.copy2(source, folder / source.name)

summary = [{'device': device, 'test': name, 'result': result} for (device, name), result in sorted(latest.items())]
(output / 'playback-evidence.json').write_text(json.dumps(playback_evidence, indent=2) + '\n')
(output / 'test-results.json').write_text(json.dumps({'latestCases': summary, 'runHistory': history}, ensure_ascii=False, indent=2) + '\n')
esc = html.escape
rows = ''.join(f'<tr><td>{esc(device_labels.get(r["device"], r["device"]))}</td><td>{esc(r["test"])}</td><td class="{r["result"].lower()}">{r["result"]}</td></tr>' for r in summary)
galleries = ''
for folder in sorted((output / 'after').iterdir()):
    cards = ''.join(f'<figure><a href="{esc(str(p.relative_to(output)))}"><img loading="lazy" src="{esc(str(p.relative_to(output)))}" alt="{esc(p.stem)}"></a><figcaption>{esc(p.stem)}</figcaption></figure>' for p in sorted(folder.glob('*.png')))
    galleries += f'<h2>{esc(device_labels.get(folder.name, folder.name))} · screenshots</h2><div class="gallery">{cards}</div>'
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>WatermelonFin · Media & Playback Audit</title>
<style>body{margin:0;background:#101217;color:#edf0f5;font:16px/1.65 system-ui,sans-serif}main{max-width:1150px;margin:auto;padding:36px 24px}h1{font-size:clamp(28px,5vw,48px);line-height:1.15}h2{margin-top:48px}a{color:#8fc9ff}.note{padding:20px;background:#20252f;border-radius:16px}.pair,.gallery{display:grid;gap:24px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr))}figure{margin:0}img{display:block;max-width:100%;max-height:760px;margin:auto;border-radius:16px}figcaption{padding:10px;color:#bec6d5}.gallery img{max-height:460px}table{width:100%;border-collapse:collapse;font-size:14px}td,th{text-align:left;border-bottom:1px solid #363c48;padding:10px;overflow-wrap:anywhere}.passed{color:#70e6ad}.failed{color:#ff8798}code{overflow-wrap:anywhere}.scroll{overflow:auto}li{margin:8px 0}</style><main>
<p>WatermelonFin / Regression audit / 2026-10-28–29</p><h1>从“能登录”到真正能用</h1>
<p>基于真实 Jellyfin 服务器与受限账号，验证媒体导航、搜索、电影和剧集播放、音轨、字幕，以及设置与诊断入口。每个截图来自实际运行的应用。</p>
<div class="note"><strong>权限边界：</strong>账号非管理员，禁止内容删除及文件夹删除。测试启动前会拒绝权限不符合要求的账号；没有执行删除操作，也没有修改权限。密码从 macOS Keychain 读取，仅保留在本地驱动进程中。</div>
<h2>修复前后 · 同一 iPhone 13 Pro Max / iOS 26.5</h2><div class="pair"><figure><img src="before/media.png" alt="修复前导航标题覆盖卡片"><figcaption>Before：卡片进入导航栏区域，真实点击无法进入媒体库；图标、文字和按钮背景挤在一起。</figcaption></figure><figure><img src="after/comparison/01-live-media-before-navigation.png" alt="修复后媒体页面"><figcaption>After：恢复安全区域；采用紧凑的触屏卡片，保留 TV 卡片布局。六个入口和返回操作逐一测试。</figcaption></figure></div>
<h2>测试发现与修复</h2><ol><li>媒体页忽略安全区域，第一排卡片被导航栏覆盖。修复后同时验证坐标不重叠和真实导航。</li><li>手机复用了大图标与系统 bordered 按钮，造成截字和红色胶囊背景。改为 plain 卡片、更强的图片遮罩；辅助功能大字体切换为单列。</li><li>当前服务器拒绝 SDK 的 GET QuickConnect/Initiate。改用 POST，保留反向代理路径，测试夹具同步严格检查 HTTP 方法。</li><li>MPV 对 anamorphic H.264 的多余限制触发转码，原有四条音轨只剩默认一条。移除这一限制，真实播放验证英文音轨切换。</li><li>播放菜单会被五秒自动隐藏计时器移除。音轨、字幕与播放选项改为明确的选择面板；打开时暂停自动隐藏，关闭后恢复。</li><li>续播按钮只朗读剩余时间。增加明确的 Play/Resume 辅助功能名称和稳定标识。</li><li>iOS 27 的自动搜索栏布局没有呈现输入框。明确指定始终显示导航搜索栏，并重测搜索到播放。</li><li>iPad 横屏播放返回后详情标题和播放按钮消失。让详情头部保持挂载，下方季/推荐等内容保留延迟加载，验证旋转、关闭和返回。</li></ol><p><a href="before/search-ios27.png">iOS 27 搜索框缺失的原始截图</a></p>
<h2>证据与范围</h2><p>播放验证读取同一模拟器的服务器会话，要求播放时间前进、暂停状态变化、拖动后位置有明显改变且与滑块显示值对应、音轨/字幕索引变化。截图另外确认视频帧、横屏和选择面板。<a href="playback-evidence.json">脱敏的服务器播放状态证据</a>保留暂停、时间和轨道索引。真实服务器的进度/续播记录会随正常播放更新。</p>
<p>UI/UX Pro Max 检查：导航安全区、可读字号、图片上文字对比、44pt 音轨/字幕触摸目标、大字体布局。独立代码审查检查了导航、兼容性改动、菜单生命周期和受限账号检查；审查不替代运行测试。</p>
<div class="note"><strong>没有声称已覆盖：</strong>实体 iPhone/iPad/Apple TV、所有编解码器/网络条件、原生 AVPlayer 全套操作。tvOS 此次提供编译与单元回归证据，未声称完成遥控器端到端播放。现有 Live TV 页面仍是 Coming soon 占位页，不能算直播播放通过。账号/服务器详情截图留在本地结果包，不放入公开仓库。</div>
<h2>自动化结果</h2><p>下表按设备与用例展示最后一次结果；早期失败及后续重测保留于 <a href="test-results.json">完整运行记录</a>。不同设备的系统版本以记录内 xcresult 元数据为准。</p><div class="scroll"><table><thead><tr><th>设备组</th><th>用例</th><th>最后结果</th></tr></thead><tbody>ROWS</tbody></table></div>
<h2>复跑</h2><p>先运行 <code>python3 Scripts/UITests/live_jellyfin_driver.py</code>。它使用现有 <code>~/.config/watermelonfin-mcp/connection.json</code> 和 Keychain 凭据，并在 loopback 18097 提供授权/只读观察接口。使用 Xcode 的 WatermelonFin iOS scheme 运行 <code>LiveMediaFlowTests</code>；当前测试片源是此服务器上已验证的三份样本，移植到其他服务器时需替换样本。没有本地驱动时此实服测试会跳过。模拟器测试需要签名以使用 Keychain。</p><p>离线权限边界检查：<code>python3 -O Scripts/UITests/test_live_driver_policy.py</code>。严格接口夹具：<code>python3 Scripts/UITests/jellyfin_fixture.py</code>，再运行 <code>SignInFlowTests/testQuickConnectRecoversAfterRetry</code>。</p>
GALLERIES</main></html>'''
(output / 'index.html').write_text(page.replace('ROWS', rows).replace('GALLERIES', galleries))
print(json.dumps({'cases': len(summary), 'failures': sum(r['result'] == 'Failed' for r in summary), 'screenshots': len(list((output/'after').rglob('*.png')))}))
