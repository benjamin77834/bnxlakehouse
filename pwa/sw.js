const CACHE_NAME = 'datalake-costs-v1';
const ASSETS = ['/', '/index.html', '/manifest.json'];

self.addEventListener('install', (e) => {
    e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(ASSETS)));
});

self.addEventListener('fetch', (e) => {
    e.respondWith(
        fetch(e.request)
            .then(r => {
                const clone = r.clone();
                caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
                return r;
            })
            .catch(() => caches.match(e.request))
    );
});

// Push notifications para alarmas
self.addEventListener('push', (e) => {
    const data = e.data ? e.data.json() : { title: 'Alerta de Costos', body: 'Revisa tu dashboard' };
    e.waitUntil(
        self.registration.showNotification(data.title, {
            body: data.body,
            icon: 'icon-192.png',
            badge: 'icon-192.png',
            vibrate: [200, 100, 200],
            tag: 'cost-alert'
        })
    );
});
