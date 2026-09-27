(function () {
  "use strict";

  const QR_REFRESH_MS = 30000;
  const STORAGE_KEY = "albashir_gate_last_data";

  const config = window.AL_BASHIR_CONFIG || {};

  const elements = {
    date: document.getElementById("date"),
    time: document.getElementById("time"),
    shift: document.getElementById("shift"),
    qrContainer: document.getElementById("qrContainer"),
    status: document.getElementById("status"),
    update: document.getElementById("update")
  };

  let currentData = null;

  function setStatus(message, ok) {
    if (!elements.status) return;
    elements.status.textContent = message;
    elements.status.style.color = ok ? "#6cff8a" : "#ff7777";
  }


  function localShift() {
    const hour = new Date().getHours();

    if (hour >= 7 && hour < 15) return "الوردية الصباحية";
    if (hour >= 15 && hour < 23) return "الوردية المسائية";

    return "الوردية الليلية";
  }


  function updateClock(data) {
    const now = new Date();

    elements.date.textContent =
      data?.date || now.toLocaleDateString("ar-JO");

    elements.time.textContent =
      data?.time || now.toLocaleTimeString("ar-JO");

    elements.shift.textContent =
      data?.shift || localShift();
  }


  function saveOffline(data) {
    localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify(data)
    );
  }


  function loadOffline() {
    try {
      return JSON.parse(
        localStorage.getItem(STORAGE_KEY)
      );
    } catch {
      return null;
    }
  }


  async function getGateData() {

    if (!config.SUPABASE_URL || !config.SUPABASE_ANON_KEY) {
      return null;
    }

    const url =
      config.SUPABASE_URL.replace(/\/$/, "") +
      "/rest/v1/rpc/" +
      (config.RPC_NAME || "gate_screen_api");


    const response = await fetch(url, {
      method: "POST",
      headers: {
        apikey: config.SUPABASE_ANON_KEY,
        Authorization:
          "Bearer " + config.SUPABASE_ANON_KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({})
    });


    if (!response.ok) {
      throw new Error("Supabase error " + response.status);
    }


    const result = await response.json();


    return result.data || result;

  }



  function drawQR(token) {

    const qr = window.QRCode;


    if (!qr || typeof qr.toCanvas !== "function") {

      elements.qrContainer.textContent =
        "QRCode library missing";

      setStatus(
        "مشكلة في مكتبة QR",
        false
      );

      return;
    }


    if (!token) {

      elements.qrContainer.textContent =
        "لا يوجد QR حاليا";

      setStatus(
        "لا يوجد Token",
        false
      );

      return;
    }



    const canvas = document.createElement("canvas");


    qr.toCanvas(
      canvas,
      token,
      {
        width: 300,
        margin: 2,
        errorCorrectionLevel: "M"
      },
      function (error) {

        if (error) {

          elements.qrContainer.textContent =
            "فشل إنشاء QR";

          return;

        }


        elements.qrContainer.replaceChildren(canvas);

        elements.update.textContent =
          "آخر تحديث QR: " +
          new Date().toLocaleTimeString("ar-JO");

      }
    );

  }



  async function refreshGate() {

    try {

      const data = await getGateData();


      if (data) {

        currentData = data;

        saveOffline(data);

        updateClock(data);

        drawQR(
          data.qr_token
        );

        setStatus(
          data.system_status === "ONLINE"
            ? "النظام يعمل ✓"
            : "النظام غير متاح",
          data.system_status === "ONLINE"
        );

        return;
      }


    } catch (error) {

      console.log(error);

    }


    // Offline fallback

    const offlineData = loadOffline();


    if (offlineData) {

      currentData = offlineData;

      updateClock(offlineData);

      drawQR(
        offlineData.qr_token
      );

      setStatus(
        "النظام يعمل Offline ✓",
        true
      );

    } else {

      updateClock(null);

      drawQR(null);

      setStatus(
        "لا توجد بيانات",
        false
      );

    }

  }



  if ("serviceWorker" in navigator) {

    navigator.serviceWorker.register(
      "./service-worker.js"
    ).catch(console.error);

  }


  refreshGate();

  setInterval(
    refreshGate,
    QR_REFRESH_MS
  );


  setInterval(
    function () {
      updateClock(currentData);
    },
    1000
  );


})();
