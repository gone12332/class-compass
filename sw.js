// Keeps Class Compass working when the school wifi is weak or off.
// Network first for the page so updates show up; cached copy when offline.
var CACHE = "class-compass-v8";
var FILES = ["./", "./index.html", "./config.js", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png"];
self.addEventListener("install", function(e){
  e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(FILES); }).then(function(){ return self.skipWaiting(); }));
});
self.addEventListener("activate", function(e){
  e.waitUntil(caches.keys().then(function(keys){
    return Promise.all(keys.filter(function(k){ return k !== CACHE; }).map(function(k){ return caches.delete(k); }));
  }).then(function(){ return self.clients.claim(); }));
});
self.addEventListener("fetch", function(e){
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  if (url.origin !== location.origin){
    // Fonts: use the cache when there, otherwise fetch and remember.
    e.respondWith(caches.match(req).then(function(hit){
      return hit || fetch(req).then(function(res){ var copy = res.clone(); caches.open(CACHE).then(function(c){ c.put(req, copy); }); return res; });
    }));
    return;
  }
  e.respondWith(fetch(req).then(function(res){
    var copy = res.clone(); caches.open(CACHE).then(function(c){ c.put(req, copy); }); return res;
  }).catch(function(){ return caches.match(req, { ignoreSearch: true }).then(function(hit){ return hit || caches.match("./index.html"); }); }));
});
