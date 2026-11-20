const CACHE='sspace-static-v4';
const CORE_ASSETS=['./','./index.html','./manifest.webmanifest'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE_ASSETS)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key.startsWith('sspace-static-')&&key!==CACHE).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;

  if(request.mode==='navigate'){
    event.respondWith(
      fetch(request).then(response=>{
        if(response&&response.ok){
          const copy=response.clone();
          event.waitUntil(caches.open(CACHE).then(cache=>cache.put('./index.html',copy)));
        }
        return response;
      }).catch(()=>caches.match('./index.html'))
    );
    return;
  }

  if(request.destination==='document'||request.destination==='script'||request.destination==='style'||request.destination==='image'||url.pathname.endsWith('.webmanifest')){
    event.respondWith(
      caches.match(request).then(cached=>{
        const network=fetch(request).then(response=>{
          if(response&&response.ok){
            const copy=response.clone();
            event.waitUntil(caches.open(CACHE).then(cache=>cache.put(request,copy)));
          }
          return response;
        }).catch(()=>cached);
        if(cached){
          event.waitUntil(network.then(()=>undefined));
          return cached;
        }
        return network;
      })
    );
  }
});
