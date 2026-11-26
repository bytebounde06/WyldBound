"""Builds the Home Screen web app (web/) and the iPhone app's files from WyldBound.html.
Run by GitHub Actions; you never need to run this yourself."""
import hashlib, json, os, shutil, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
GAME = 'WyldBound.html'
if not os.path.exists(GAME):
    sys.exit('WyldBound.html is missing. Upload it to the top level of the repository.')
html = open(GAME, encoding='utf-8').read()

icon = Image.open('icon/icon-1024.png').convert('RGB')

# ---- iPhone app ----
shutil.copy(GAME, 'ios/WyldBoundApp/WyldBound/WyldBound.html')
icon.save('ios/WyldBoundApp/WyldBound/Assets.xcassets/AppIcon.appiconset/icon-1024.png')

# ---- Home Screen web app ----
os.makedirs('web', exist_ok=True)
ver = hashlib.sha1(html.encode()).hexdigest()[:10]
head = ('<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">'
        '<meta name="apple-mobile-web-app-title" content="WyldBound"><meta name="mobile-web-app-capable" content="yes">'
        '<link rel="manifest" href="manifest.webmanifest"><link rel="apple-touch-icon" href="apple-touch-icon.png">'
        '<link rel="icon" href="icon-192.png">')
reg = ('<script>if("serviceWorker" in navigator&&/^https?:/.test(location.protocol)){'
       'navigator.serviceWorker.register("sw.js").catch(()=>{});'
       'if(navigator.storage&&navigator.storage.persist)navigator.storage.persist().catch(()=>{});}</script>')
web = html.replace('<title>', head + '<title>', 1)
web = web.replace('</body>', reg + '</body>', 1) if '</body>' in web else web + reg
open('web/index.html', 'w', encoding='utf-8').write(web)
for name, size in [('icon-192.png', 192), ('icon-512.png', 512), ('apple-touch-icon.png', 180)]:
    icon.resize((size, size), Image.LANCZOS).save('web/' + name)
json.dump({"name": "WyldBound", "short_name": "WyldBound", "start_url": "./", "scope": "./",
           "display": "fullscreen", "orientation": "portrait",
           "background_color": "#3a2e6e", "theme_color": "#3a2e6e",
           "icons": [{"src": "icon-192.png", "sizes": "192x192", "type": "image/png"},
                     {"src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable"}]},
          open('web/manifest.webmanifest', 'w'), indent=1)
open('web/sw.js', 'w').write("""// WyldBound offline cache. VERSION changes with every new game file so phones pick up updates.
const VERSION='wyldbound-%s';
const FILES=['./','index.html','manifest.webmanifest','icon-192.png','icon-512.png','apple-touch-icon.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(VERSION).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const url=new URL(e.request.url);if(url.origin!==location.origin)return;
  e.respondWith(caches.match(e.request,{ignoreSearch:true}).then(r=>r||(e.request.mode==='navigate'?caches.match('index.html'):null)).then(r=>r||fetch(e.request)));
});
""" % ver)
open('web/.nojekyll', 'w').write('')
print('Prepared web/ and iOS files, version', ver)
