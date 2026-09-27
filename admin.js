(function () {
"use strict";

const config = window.AL_BASHIR_CONFIG || {};

const loginForm = document.getElementById("loginForm");
const email = document.getElementById("email");
const password = document.getElementById("password");

const form = document.getElementById("employeeForm");
const employeeId = document.getElementById("employeeId");
const fullName = document.getElementById("fullName");
const photoFile = document.getElementById("photoFile");

const preview = document.getElementById("preview");
const result = document.getElementById("result");

let session = null;


function apiUrl(path){
    return config.SUPABASE_URL.replace(/\/$/,"") + path;
}


function headers(){
    return {
        "apikey": config.SUPABASE_ANON_KEY,
        "Authorization":
            "Bearer " + 
            (session?.access_token || config.SUPABASE_ANON_KEY)
    };
}


function message(text,error=false){
    result.textContent=text;
    result.style.color=error ? "#ff7777":"#6cff8a";
}


photoFile.addEventListener("change",()=>{

    const file=photoFile.files[0];

    if(!file){
        preview.removeAttribute("src");
        return;
    }

    preview.src=URL.createObjectURL(file);

});


// تسجيل الدخول

loginForm.addEventListener("submit",async(e)=>{

e.preventDefault();

try{

message("جاري تسجيل الدخول...");

const res=await fetch(
apiUrl("/auth/v1/token?grant_type=password"),
{
method:"POST",
headers:{
apikey:config.SUPABASE_ANON_KEY,
"Content-Type":"application/json"
},
body:JSON.stringify({
email:email.value.trim(),
password:password.value
})
});


if(!res.ok)
throw new Error("فشل تسجيل الدخول");


session=await res.json();

message("تم تسجيل الدخول");

}catch(err){

message(err.message,true);

}

});



// رفع الصورة

async function uploadPhoto(employee,file){

const ext=file.name.split(".").pop();

const path=
employee+"/"+Date.now()+"."+ext;


const res=await fetch(

apiUrl(
"/storage/v1/object/"
+
(config.EMPLOYEE_PHOTOS_BUCKET || "employee-photos")
+
"/"
+
encodeURIComponent(path)
),

{
method:"POST",
headers:{
...headers(),
"Content-Type":file.type,
"x-upsert":"true"
},
body:file
});


if(!res.ok)
throw new Error("فشل رفع الصورة");


return path;

}



// حفظ بيانات الموظف

async function saveEmployee(id,name,path){


const res=await fetch(

apiUrl(
"/rest/v1/"
+
(config.EMPLOYEES_TABLE || "employees")
+
"?on_conflict=employee_id"
),

{
method:"POST",

headers:{
...headers(),
"Content-Type":"application/json",
"Prefer":"resolution=merge-duplicates"
},

body:JSON.stringify({

employee_id:id,
full_name:name || null,
photo_path:path,
updated_at:new Date().toISOString()

})

});


if(!res.ok)
throw new Error("فشل حفظ الموظف");

}




// Signed URL

async function signedUrl(path){

const res=await fetch(

apiUrl(
"/storage/v1/object/sign/"
+
(config.EMPLOYEE_PHOTOS_BUCKET || "employee-photos")
+
"/"
+
encodeURIComponent(path)
),

{

method:"POST",

headers:{
...headers(),
"Content-Type":"application/json"
},

body:JSON.stringify({
expiresIn:600
})

});


if(!res.ok)
return null;


const data=await res.json();


return apiUrl(
"/storage/v1"
+
data.signedURL
);

}





form.addEventListener("submit",async(e)=>{

e.preventDefault();


if(!session){

message("يجب تسجيل الدخول أولاً",true);
return;

}


const id=employeeId.value.trim();
const name=fullName.value.trim();
const file=photoFile.files[0];


if(!id || !file){

message("رقم الموظف والصورة مطلوبان",true);
return;

}



try{


message("جاري الرفع...");


const path=
await uploadPhoto(id,file);



await saveEmployee(
id,
name,
path
);



const url=
await signedUrl(path);



if(url)
preview.src=url;



message(
"تم رفع الصورة وربط الموظف بنجاح"
);



}catch(err){

message(err.message,true);

}



});

})();
