const C = 'zyvpay-v1';
const FILES = ['./', 'index.html', 'app.js', 'manifest.json', 'icon.svg', 'lib/qrcode.js', 'lib/jsQR.js'];
self.addEventListener('install', e => e.waitUntil(caches.open(C).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e => e.respondWith(caches.match(e.request).then(r => r || fetch(e.request))));
