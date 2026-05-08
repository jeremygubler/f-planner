# PhotoPlanner PWA

## Dateien
```
photoplanner/
├── index.html          ← Haupt-App
├── manifest.json       ← PWA-Manifest
├── sw.js               ← Service Worker (Offline + Caching)
├── icons/              ← App-Icons (alle Grössen)
│   ├── icon-72.png
│   ├── icon-96.png
│   ├── icon-128.png
│   ├── icon-144.png
│   ├── icon-152.png
│   ├── icon-192.png
│   ├── icon-384.png
│   ├── icon-512.png
│   ├── icon-maskable-192.png
│   ├── icon-maskable-512.png
│   └── apple-touch-icon.png
└── README.md

```

## Netlify Deployment (5 Minuten)

1. Gehe zu https://netlify.com → "Add new site" → "Deploy manually"
2. Diesen ganzen Ordner als ZIP hochladen (oder Drag & Drop)
3. Fertig! Die App ist online und als PWA installierbar.

## Lokales Testen

Service Workers funktionieren NICHT über file:// Protokoll.
Für lokales Testen einen HTTP-Server starten:

```bash
# Python (einfachste Methode)
python3 -m http.server 8080
# → http://localhost:8080

# Node.js
npx serve .
# → http://localhost:3000
```

## PWA Features

- ✅ Installierbar auf Android, iOS, Desktop
- ✅ Offline-Modus (letzte Daten gecacht)
- ✅ Wetter-API Antworten 24h gecacht
- ✅ CDN-Libraries (SunCalc, Leaflet) gecacht
- ✅ "Zurück online" Benachrichtigung
- ✅ App-Shortcuts (Golden Hour, Milchstrasse)
- ✅ Push Notification Support (braucht Backend für echte Alerts)
- ✅ iOS Installationshinweis

## App installieren

**Android (Chrome):**
→ Button "App installieren" erscheint automatisch unten rechts

**iOS (Safari):**  
→ Teilen-Button → "Zum Home-Bildschirm" 

**Desktop (Chrome/Edge):**
→ Install-Icon in der Adressleiste, oder der Button in der App
