const CACHE_NAME = "gate-screen-albashir-offline-v3";

const ASSETS = [
  "./",
  "./index.html",
  "./style.css",
  "./app.js",
  "./qrcode.min.js",
  "./logo.jpg",
  "./manifest.json",
  "./config.js",

  // Admin
  "./admin.html",
  "./admin.js"
];


self.addEventListener("install", (event) => {

  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(ASSETS))
  );

  self.skipWaiting();

});


self.addEventListener("activate", (event) => {

  event.waitUntil(

    caches.keys().then((keys) =>

      Promise.all(

        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))

      )

    )

  );

  self.clients.claim();

});


self.addEventListener("fetch", (event) => {

  if (event.request.method !== "GET") return;


  event.respondWith(

    caches.match(event.request)
      .then((cachedResponse) => {

        if (cachedResponse) {
          return cachedResponse;
        }


        return fetch(event.request)
          .then((networkResponse) => {

            const responseCopy =
              networkResponse.clone();


            caches.open(CACHE_NAME)
              .then((cache) => {

                cache.put(
                  event.request,
                  responseCopy
                );

              });


            return networkResponse;

          });

      })

  );

});
