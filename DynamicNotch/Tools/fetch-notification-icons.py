"""Refresh bundled app identity artwork from Apple's public App Store lookup."""
import json
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
apps = {
    'ChatGPT': ('6448311069', ['GPT', 'Chat GPT', 'chatgpt.com', 'chat.openai.com']),
    'Instagram': ('389801252', ['instagram.com']),
    'tiket.com': ('890405921', ['Tiket', 'tiket.com']),
    'Telegram': ('686449807', ['Telegram Web', 'web.telegram.org', 'telegram.org', 'ru.keepcoder.Telegram', 'org.telegram.desktop']),
    'WhatsApp': ('310633997', ['WhatsApp Messenger', 'web.whatsapp.com', 'whatsapp.com', 'net.whatsapp.WhatsApp']),
    'Gmail': ('422689480', ['mail.google.com']),
}
entries = []
for index, (name, (app_id, aliases)) in enumerate(apps.items()):
    with urllib.request.urlopen(f'https://itunes.apple.com/lookup?id={app_id}&country=id', timeout=30) as response:
        result = json.load(response)['results'][0]
    asset = f'NotificationIcon{index}'
    directory = root / 'DynamicNotch' / 'Assets.xcassets' / (asset + '.imageset')
    directory.mkdir(parents=True, exist_ok=True)
    url = result['artworkUrl512']
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read()
    # Apple artwork URLs normally deliver JPEG; preserve the actual file format.
    suffix = 'png' if data.startswith(b'\x89PNG') else 'jpg'
    filename = 'icon.' + suffix
    (directory / filename).write_bytes(data)
    (directory / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': filename}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
    entries.append({'name': name, 'bundleID': result['bundleId'], 'aliases': aliases, 'asset': asset,
                    'source': result['trackViewUrl'], 'artworkURL': url})
    print(name, result['bundleId'])
(root / 'DynamicNotch' / 'NotificationIconCatalog.json').write_text(json.dumps(entries, indent=2) + '\n')
