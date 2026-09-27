(function () {
"use strict";


const QR_REFRESH_MS = 30000;
const CACHE_VERSION = "gate-screen-albashir-supabase-v4";

const config = window.AL_BASHIR_CONFIG || {};


const elements = {

    date: document.getElementById("date"),
    time: document.getElementById("time"),
    shift: document.getElementById("shift"),

    qrContainer: document.getElementById("qrContainer"),

    status: document.getElementById("status"),

    update: document.getElementById("update"),

    expires: document.getElementById("expires"),

    gateName: document.getElementById("gateName")

};


let gateData = null;



function setStatus(message, ok = true){

    if(!elements.status) return;

    elements.status.textContent = message;

    elements.status.style.color =
    ok ? "#6cff8a" : "#ff7777";

}



function apiUrl(path){

    return String(config.SUPABASE_URL || "")
    .replace(/\/$/,"") + path;

}



function apiHeaders(){

    return {

        "apikey":
        config.SUPABASE_ANON_KEY,

        "Authorization":
        "Bearer " + config.SUPABASE_ANON_KEY,

        "Content-Type":
        "application/json"

    };

}




async function loadGateData(){

try{


const rpc =
config.RPC_NAME || "gate_screen_api";



const response = await fetch(

apiUrl(
"/rest/v1/rpc/" + rpc
),

{

method:"POST",

headers:apiHeaders(),

body:JSON.stringify({})

}

);



if(!response.ok){

throw new Error(
"RPC ERROR " + response.status
);

}



const data =
await response.json();



gateData =
Array.isArray(data)
? data[0]
: data;



updateGate();


setStatus(
"النظام يعمل Online ✓",
true
);



}

catch(error){

console.error(error);


setStatus(
"تعذر الاتصال بالنظام",
false
);


}

}





function updateGate(){


if(!gateData)
return;



// الوقت والتاريخ من توقيت الأردن

const now = new Date();



if(elements.date){

elements.date.textContent =

now.toLocaleDateString(
"ar-JO",
{
timeZone:"Asia/Amman",
year:"numeric",
month:"2-digit",
day:"2-digit"
}

);

}



if(elements.time){

elements.time.textContent =

now.toLocaleTimeString(
"ar-JO",
{
timeZone:"Asia/Amman",
hour:"2-digit",
minute:"2-digit",
second:"2-digit"
}

);

}




if(elements.shift){

elements.shift.textContent =
gateData.shift || "--";

}




if(elements.gateName &&
gateData.gate_name){

elements.gateName.textContent =
gateData.gate_name;

}




if(elements.expires){

elements.expires.textContent =
"ينتهي QR: " +
(
gateData.expires_at || "--"
);

}



drawQr(
gateData.qr_token
);



}





async function drawQr(token){


const qr =
window.QRCode;



if(!qr ||
typeof qr.toCanvas !== "function"){


setStatus(
"مكتبة QR غير موجودة",
false
);


return;

}




if(!token){


elements.qrContainer.textContent =
"لا يوجد QR";


return;

}




const canvas =
document.createElement("canvas");



try{


await qr.toCanvas(

canvas,

token,

{

width:450,

margin:3,

errorCorrectionLevel:"M",

color:{

dark:"#000000",

light:"#ffffff"

}

}

);



elements.qrContainer
.replaceChildren(canvas);



if(elements.update){

elements.update.textContent =
"آخر تحديث QR: " +
new Date()
.toLocaleTimeString(
"ar-JO",
{
timeZone:"Asia/Amman"
}
);

}



}

catch(error){


elements.qrContainer.textContent =
"فشل إنشاء QR";


console.error(error);


}


}







function registerServiceWorker(){


if(!("serviceWorker" in navigator))
return;



window.addEventListener(
"load",
()=>{


navigator.serviceWorker.register(
"./service-worker.js"
)
.catch(()=>{});


}

);


}




window.__GATE_SCREEN_CACHE_VERSION__ =
CACHE_VERSION;



loadGateData();



setInterval(
loadGateData,
QR_REFRESH_MS
);



registerServiceWorker();



})();
