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
const employeesList = document.getElementById("employeesList");

let session =
JSON.parse(localStorage.getItem("albashir_session") || "null");



function apiUrl(path){
return config.SUPABASE_URL.replace(/\/$/,"") + path;
}



function headers(){

return {
apikey:config.SUPABASE_ANON_KEY,
Authorization:
"Bearer "+
(session?.access_token || config.SUPABASE_ANON_KEY),
"Content-Type":"application/json"
};

}



function message(text,error=false){

if(!result)return;

result.textContent=text;
result.style.color=
error ? "#ff7777":"#6cff8a";

}



photoFile?.addEventListener("change",()=>{

const file=photoFile.files[0];

if(file)
preview.src=URL.createObjectURL(file);

});




// LOGIN

loginForm?.addEventListener("submit",async e=>{

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
throw Error("بيانات الدخول غير صحيحة");


session=await res.json();

localStorage.setItem(
"albashir_session",
JSON.stringify(session)
);


message("تم تسجيل الدخول بنجاح");

loadEmployees();


}catch(e){

message(e.message,true);

}

});




// رفع الصورة

async function uploadPhoto(id,file){

const ext=file.name.split(".").pop();

const path=
id+"/"+Date.now()+"."+ext;


const res=await fetch(

apiUrl(
"/storage/v1/object/"+
(config.EMPLOYEE_PHOTOS_BUCKET||"employee-photos")
+"/"+
encodeURIComponent(path)
),

{
method:"POST",
headers:{
...headers(),
"x-upsert":"true",
"Content-Type":file.type
},
body:file
});


if(!res.ok)
throw Error("فشل رفع الصورة");


return path;

}




// حفظ الموظف

async function saveEmployee(id,name,path){


const data={

employee_id:id,

full_name:name || null,

photo_path:path,

updated_at:
new Date().toISOString()

};



const res=await fetch(

apiUrl(
"/rest/v1/"+
(config.EMPLOYEES_TABLE||"employees")+
"?on_conflict=employee_id"
),

{
method:"POST",
headers:{
...headers(),
Prefer:
"resolution=merge-duplicates"
},
body:
JSON.stringify(data)
});


if(!res.ok)
throw Error("فشل حفظ بيانات الموظف");


}





// signed url

async function signedUrl(path){


const res=await fetch(

apiUrl(
"/storage/v1/object/sign/"+
(config.EMPLOYEE_PHOTOS_BUCKET||"employee-photos")+
"/"+
encodeURIComponent(path)
),

{
method:"POST",
headers:headers(),
body:
JSON.stringify({
expiresIn:600
})
}

);


if(!res.ok)
return null;


const data=await res.json();


return apiUrl(
"/storage/v1"+
data.signedURL
);

}




// تحميل الموظفين

async function loadEmployees(){


if(!employeesList)return;


try{


const res=await fetch(

apiUrl(
"/rest/v1/"+
(config.EMPLOYEES_TABLE||"employees")+
"?select=*"
),

{
headers:headers()
}

);


const employees=await res.json();


employeesList.innerHTML="";


employees.forEach(emp=>{


const div=document.createElement("div");

div.style.margin="20px";


div.innerHTML=`

<h3>${emp.full_name||"-"}</h3>

رقم الموظف:
${emp.employee_id||"-"}

<br>

القسم:
${emp.department||"-"}

<br>

الاختصاص:
${emp.specialty||"-"}

<br>

الحالة:
${emp.status||"-"}

<div></div>

`;



if(emp.photo_path){

signedUrl(emp.photo_path)
.then(url=>{

if(url){

const img=document.createElement("img");

img.src=url;

img.className="preview";

div.querySelector("div")
.appendChild(img);

}

});


}


employeesList.appendChild(div);


});


}catch(e){

employeesList.textContent=
"تعذر تحميل الموظفين";

}

}






// حفظ الصورة

form?.addEventListener("submit",async e=>{

e.preventDefault();


if(!session){

message(
"يجب تسجيل الدخول أولاً",
true
);

return;

}



const id=employeeId.value.trim();
const name=fullName.value.trim();
const file=photoFile.files[0];


if(!id || !file){

message(
"رقم الموظف والصورة مطلوبان",
true
);

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
"تم الحفظ بنجاح"
);


loadEmployees();



}catch(e){

message(e.message,true);

}

});



loadEmployees();


})();
