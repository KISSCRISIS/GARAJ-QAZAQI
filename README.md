# Gate Screen ALBASHIR - Offline

شاشة بوابة محلية تعمل من `localhost` بدون إنترنت وبدون CDN.

## الملفات المطلوبة

- `index.html`
- `app.js`
- `style.css`
- `qrcode.min.js`
- `service-worker.js`
- `manifest.json`
- `logo.jpg`

## التشغيل المحلي

افتح المجلد بخادم محلي، مثل:

```bash
node -e "const http=require('http'),fs=require('fs'),path=require('path');const root=process.cwd();const types={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.jpg':'image/jpeg'};http.createServer((req,res)=>{let url=decodeURIComponent(req.url.split('?')[0]);if(url==='/'||url==='')url='/index.html';const file=path.normalize(path.join(root,url));fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end('Not found');return;}res.writeHead(200,{'Content-Type':types[path.extname(file).toLowerCase()]||'application/octet-stream','Cache-Control':'no-store'});res.end(data);});}).listen(8000,'127.0.0.1',()=>console.log('http://127.0.0.1:8000/'));"
```

ثم افتح:

```txt
http://127.0.0.1:8000/
```

## ملاحظات

- مكتبة QR محلية داخل `qrcode.min.js`.
- لا يوجد اعتماد على Supabase أو CDN.
- يتم تحديث QR كل 30 ثانية.
- `service-worker.js` يحفظ الملفات الأساسية للعمل Offline.
