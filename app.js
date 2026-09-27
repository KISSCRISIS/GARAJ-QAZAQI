(function () {
  "use strict";

  const QR_REFRESH_MS = 30000;
  const CACHE_VERSION = "gate-screen-albashir-offline-v2";

  const elements = {
    date: document.getElementById("date"),
    time: document.getElementById("time"),
    shift: document.getElementById("shift"),
    qrContainer: document.getElementById("qrContainer"),
    status: document.getElementById("status"),
    update: document.getElementById("update")
  };

  function setStatus(message, ok) {
    elements.status.textContent = message;
    elements.status.style.color = ok ? "#6cff8a" : "#ff7777";
  }

  function getShift(now) {
    const hour = now.getHours();
    if (hour >= 7 && hour < 15) return "الوردية الصباحية";
    if (hour >= 15 && hour < 23) return "الوردية المسائية";
    return "الوردية الليلية";
  }

  function updateClock() {
    const now = new Date();
    elements.date.textContent = now.toLocaleDateString("ar-JO");
    elements.time.textContent = now.toLocaleTimeString("ar-JO");
    elements.shift.textContent = getShift(now);
  }

  function qrPayload() {
    const now = new Date();
    return JSON.stringify({
      app: "ALBASHIR_HOSPITAL_GATE",
      department: "EMERGENCY_DEPARTMENT",
      type: "OFFLINE_GATE_SCREEN",
      issued_at: now.toISOString(),
      valid_for_seconds: 30
    });
  }

  async function drawQr() {
    const qr = window.QRCode;

    if (!qr || typeof qr.toCanvas !== "function") {
      elements.qrContainer.textContent =
        "QRCode library missing: تأكد أن qrcode.min.js هو ملف Browser UMD ويحمّل قبل app.js";
      setStatus("مكتبة QR غير محملة", false);
      return;
    }

    const canvas = document.createElement("canvas");

    try {
      await qr.toCanvas(canvas, qrPayload(), {
        width: 300,
        margin: 2,
        errorCorrectionLevel: "M",
        color: {
          dark: "#000000",
          light: "#ffffff"
        }
      });

      elements.qrContainer.replaceChildren(canvas);
      elements.update.textContent =
        "آخر تحديث QR: " + new Date().toLocaleTimeString("ar-JO");
      setStatus("النظام يعمل Offline ✓", true);
    } catch (error) {
      elements.qrContainer.textContent = "فشل إنشاء QR: " + error.message;
      setStatus("تعذر إنشاء QR", false);
    }
  }

  function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return;

    window.addEventListener("load", function () {
      navigator.serviceWorker.register("./service-worker.js").catch(function () {
        setStatus("النظام يعمل بدون تثبيت Offline cache", true);
      });
    });
  }

  window.__GATE_SCREEN_CACHE_VERSION__ = CACHE_VERSION;

  updateClock();
  setInterval(updateClock, 1000);

  drawQr();
  setInterval(drawQr, QR_REFRESH_MS);

  registerServiceWorker();
})();
