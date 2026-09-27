(function () {
"use strict";

const config = window.AL_BASHIR_CONFIG || {};

const loginForm = document.getElementById("loginForm");
const emailInput = document.getElementById("email");
const passwordInput = document.getElementById("password");

const roleSelect = document.getElementById("role");
const userIdInput = document.getElementById("userId");

const result = document.getElementById("result");
const rolesList = document.getElementById("rolesList");

let session = null;
let currentRole = null;



function api(path){
    return String(config.SUPABASE_URL || "")
    .replace(/\/$/,"") + path;
}



function headers(){

return {

"apikey": config.SUPABASE_ANON_KEY,

"Authorization":
"Bearer " + session.access_token,

"Content-Type":
"application/json"

};

}



function show(message,error=false){

if(result){

result.textContent = message;

result.style.color =
error ? "#ff7777" : "#6cff8a";

}

}




async function login(e){

e.preventDefault();

try{

show("جاري تسجيل الدخول...");

const response = await fetch(

api("/auth/v1/token?grant_type=password"),

{

method:"POST",

headers:{

apikey:config.SUPABASE_ANON_KEY,

"Content-Type":"application/json"

},

body:JSON.stringify({

email:
emailInput.value.trim(),

password:
passwordInput.value

})

}

);



if(!response.ok)
throw new Error("بيانات الدخول غير صحيحة");


session = await response.json();


localStorage.setItem(
"albashir_admin_session",
JSON.stringify(session)
);


await checkRole();



}catch(err){

show(err.message,true);

}

}





async function checkRole(){

const user =
session.user.id;


const response = await fetch(

api(
"/rest/v1/user_roles?user_id=eq."+user
),

{

headers:headers()

}

);



if(!response.ok)
throw new Error("لا يمكن قراءة الصلاحيات");


const data =
await response.json();


if(!data.length){

throw new Error(
"لا يوجد دور مرتبط بهذا المستخدم"
);

}



currentRole =
data[0].role;



if(currentRole !== "SUPER_ADMIN"){

throw new Error(
"هذا الحساب ليس SUPER_ADMIN"
);

}



show(
"تم الدخول كـ SUPER_ADMIN"
);



loadRoles();


}







async function loadRoles(){

const response = await fetch(

api("/rest/v1/user_roles?select=*"),

{

headers:headers()

}

);



const data =
await response.json();



if(!rolesList)
return;



rolesList.innerHTML="";



data.forEach(row=>{


const item =
document.createElement("div");


item.className="role-item";


item.innerHTML = `

<div>
<b>${row.role}</b>
<br>
${row.user_id || ""}
<br>
${row.employee_id || ""}
</div>

`;



rolesList.appendChild(item);



});


}








async function saveRole(e){

e.preventDefault();


if(currentRole !== "SUPER_ADMIN"){

show(
"ليس لديك صلاحية",
true
);

return;

}



const uid =
userIdInput.value.trim();



const role =
roleSelect.value;



if(!uid){

show(
"أدخل User ID",
true
);

return;

}



try{


const response =
await fetch(

api("/rest/v1/user_roles"),

{

method:"POST",

headers:{

...headers(),

"Prefer":
"resolution=merge-duplicates"

},

body:JSON.stringify({

user_id:uid,

role:role

})

}

);



if(!response.ok)

throw new Error(
"فشل حفظ الدور"
);



show(
"تم حفظ الصلاحية"
);



loadRoles();



}catch(err){

show(
err.message,
true
);

}


}







function restore(){

const old =
localStorage.getItem(
"albashir_admin_session"
);


if(old){

try{

session =
JSON.parse(old);


}catch{}

}

}



if(loginForm)

loginForm.addEventListener(
"submit",
login
);



const roleForm =
document.getElementById("roleForm");


if(roleForm)

roleForm.addEventListener(
"submit",
saveRole
);



restore();



})();
