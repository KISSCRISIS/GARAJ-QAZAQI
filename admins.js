(function () {

"use strict";


const config = window.AL_BASHIR_CONFIG || {};


let session = null;



const loginForm =
document.getElementById("loginForm");


const roleForm =
document.getElementById("roleForm");


const rolesList =
document.getElementById("rolesList");


const result =
document.getElementById("result");



const email =
document.getElementById("email");


const password =
document.getElementById("password");


const userId =
document.getElementById("userId");


const role =
document.getElementById("role");






function apiUrl(path){

return String(config.SUPABASE_URL || "")
.replace(/\/$/,"") + path;

}





function headers(){


return {

"apikey":
config.SUPABASE_ANON_KEY,


"Authorization":
"Bearer " +
(
session?.access_token ||
config.SUPABASE_ANON_KEY
),


"Content-Type":
"application/json"

};


}




function message(text,error=false){


result.textContent=text;


result.style.color =
error ? "#ff7777" : "#6cff8a";


}





// LOGIN

loginForm.addEventListener(
"submit",
async function(e){


e.preventDefault();


try{


message("جاري تسجيل الدخول...");


const res = await fetch(

apiUrl(
"/auth/v1/token?grant_type=password"
),

{

method:"POST",

headers:{

"apikey":
config.SUPABASE_ANON_KEY,

"Content-Type":
"application/json"

},


body:JSON.stringify({

email:
email.value.trim(),


password:
password.value

})

}

);



if(!res.ok)
throw Error("فشل تسجيل الدخول");



session =
await res.json();



message(
"تم تسجيل الدخول"
);



loadRoles();



}

catch(err){


message(
err.message,
true
);


}



});







// LOAD ROLES

async function loadRoles(){


try{


const res =
await fetch(

apiUrl(
"/rest/v1/user_roles?select=*"
),

{

headers:headers()

}

);



if(!res.ok)
throw Error();



const data =
await res.json();



renderRoles(data);



}

catch(e){


rolesList.textContent =
"تعذر تحميل الصلاحيات";


}

}





function renderRoles(data){


rolesList.innerHTML="";



if(!data.length){

rolesList.textContent =
"لا توجد صلاحيات";

return;

}



data.forEach(item=>{


const box =
document.createElement("div");


box.style.background="#151515";

box.style.padding="15px";

box.style.margin="15px 0";

box.style.borderRadius="15px";


box.innerHTML = `

<strong>User ID:</strong>
<br>
${item.user_id}

<br><br>

<strong>Role:</strong>
${item.role}

<br><br>

<button>
حذف
</button>

`;



box.querySelector("button")
.onclick = () =>
deleteRole(item.id);



rolesList.appendChild(box);



});


}







// ADD / UPDATE ROLE

roleForm.addEventListener(
"submit",
async function(e){


e.preventDefault();



if(!session){

message(
"سجل الدخول أولاً",
true
);

return;

}




try{


const res =
await fetch(

apiUrl(
"/rest/v1/user_roles"
),

{

method:"POST",

headers:{

...headers(),

"Prefer":
"resolution=merge-duplicates"

},


body:JSON.stringify({

user_id:
userId.value.trim(),


role:
role.value


})

}

);



if(!res.ok)
throw Error(
"فشل حفظ الصلاحية"
);



message(
"تم حفظ الصلاحية"
);



loadRoles();



}

catch(err){


message(
err.message,
true
);


}



});








// DELETE ROLE

async function deleteRole(id){


if(!confirm("حذف هذه الصلاحية؟"))
return;



const res =
await fetch(

apiUrl(
"/rest/v1/user_roles?id=eq."+id
),

{

method:"DELETE",

headers:headers()

}

);



if(res.ok){

message(
"تم الحذف"
);

loadRoles();

}


}






loadRoles();



})();
