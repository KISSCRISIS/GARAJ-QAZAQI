(function () {
  "use strict";

  const config = window.AL_BASHIR_CONFIG || {};

  const SESSION_KEY = "albashir_admin_session";

  let session = null;


  const loginForm = document.getElementById("loginForm");
  const employeeForm = document.getElementById("employeeForm");

  const email = document.getElementById("email");
  const password = document.getElementById("password");

  const employeeId = document.getElementById("employeeId");
  const fullName = document.getElementById("fullName");
  const phoneNumber = document.getElementById("phoneNumber");
  const department = document.getElementById("department");
  const specialty = document.getElementById("specialty");
  const employeeStatus = document.getElementById("employeeStatus");

  const photoFile = document.getElementById("photoFile");
  const preview = document.getElementById("preview");

  const result = document.getElementById("result");
  const employeesList = document.getElementById("employeesList");



  function hasConfig() {

    return Boolean(
      config.SUPABASE_URL &&
      config.SUPABASE_ANON_KEY
    );

  }



  function baseUrl() {

    return String(config.SUPABASE_URL || "")
      .replace(/\/+$/, "");

  }



  function headers(extra) {

    const token =
      session?.access_token ||
      config.SUPABASE_ANON_KEY;


    return Object.assign(

      {
        apikey: config.SUPABASE_ANON_KEY,
        Authorization: "Bearer " + token
      },

      extra || {}

    );

  }



  function message(text, error = false) {

    result.textContent = text;

    result.style.color =
      error ? "#ff7777" : "#39e58c";

  }




  function loadSession() {

    try {

      session = JSON.parse(
        localStorage.getItem(SESSION_KEY) || "null"
      );

    } catch {

      session = null;

    }

  }




  function saveSession(data) {

    session = data;

    localStorage.setItem(
      SESSION_KEY,
      JSON.stringify(data)
    );

  }




  photoFile.addEventListener(
    "change",
    function () {

      const file = photoFile.files[0];

      if (!file) {

        preview.removeAttribute("src");

        return;

      }


      preview.src =
        URL.createObjectURL(file);

    }
  );





  // LOGIN

  loginForm.addEventListener(
    "submit",
    async function (e) {

      e.preventDefault();


      if (!hasConfig()) {

        message(
          "أضف إعدادات Supabase في config.js",
          true
        );

        return;

      }


      try {


        const response =
          await fetch(

            baseUrl() +
            "/auth/v1/token?grant_type=password",

            {

              method:"POST",

              headers:{
                apikey:
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



        if (!response.ok)
          throw new Error(
            "فشل تسجيل الدخول"
          );



        saveSession(
          await response.json()
        );


        password.value="";


        const allowed =
          await checkRole();


        if (!allowed) {

          message(
            "ليس لديك صلاحية إدارة الموظفين",
            true
          );

          return;

        }


        message(
          "تم تسجيل الدخول بنجاح"
        );


        loadEmployees();


      } catch(error){

        message(
          error.message,
          true
        );

      }


    }
  );






  // CHECK ROLE

  async function checkRole(){

    const userId =
      session.user?.id;


    if (!userId)
      return false;



    const response =
      await fetch(

        baseUrl() +
        "/rest/v1/user_roles?user_id=eq." +
        userId,

        {

          headers:
            headers()

        }

      );



    if (!response.ok)
      return false;



    const data =
      await response.json();



    if (!data.length)
      return false;



    return (

      data[0].role === "admin" ||
      data[0].role === "administrator"

    );

  }






  // UPLOAD PHOTO

  async function uploadPhoto(
    id,
    file
  ){

    const ext =
      file.name.split(".").pop();


    const path =
      id +
      "/" +
      Date.now() +
      "." +
      ext;



    const bucket =
      config.EMPLOYEE_PHOTOS_BUCKET ||
      "employee-photos";



    const response =
      await fetch(

        baseUrl() +
        "/storage/v1/object/" +
        bucket +
        "/" +
        encodeURIComponent(path),

        {

          method:"POST",

          headers:
            headers({

              "Content-Type":
                file.type,

              "x-upsert":
                "true"

            }),

          body:file

        }

      );



    if (!response.ok)

      throw new Error(
        "فشل رفع الصورة"
      );


    return path;

  }






  // SAVE EMPLOYEE

  async function saveEmployee(
    id,
    photoPath
  ){


    const response =
      await fetch(

        baseUrl() +
        "/rest/v1/employees",

        {

          method:"POST",

          headers:
            headers({

              "Content-Type":
                "application/json",

              Prefer:
                "resolution=merge-duplicates"

            }),


          body:
            JSON.stringify({

              employee_id:id,

              full_name:
                fullName.value || null,


              phone_number:
                phoneNumber.value || null,


              department:
                department.value || null,


              specialty:
                specialty.value || null,


              status:
                employeeStatus.value || null,


              photo_path:
                photoPath,


              updated_at:
                new Date().toISOString()

            })

        }

      );



    if (!response.ok)

      throw new Error(
        "فشل حفظ بيانات الموظف"
      );

  }






  // SIGNED URL

  async function signedUrl(path){

    const bucket =
      config.EMPLOYEE_PHOTOS_BUCKET ||
      "employee-photos";


    const response =
      await fetch(

        baseUrl() +
        "/storage/v1/object/sign/" +
        bucket +
        "/" +
        encodeURIComponent(path),

        {

          method:"POST",

          headers:
            headers({

              "Content-Type":
                "application/json"

            }),

          body:
            JSON.stringify({

              expiresIn:600

            })

        }

      );



    if (!response.ok)
      return "";



    const data =
      await response.json();


    return data.signedURL
      ? baseUrl() +
        "/storage/v1" +
        data.signedURL
      : "";

  }







  // SAVE FORM

  employeeForm.addEventListener(
    "submit",
    async function(e){

      e.preventDefault();


      if (!session?.access_token){

        message(
          "سجل الدخول أولاً",
          true
        );

        return;

      }


      const file =
        photoFile.files[0];


      if (!employeeId.value || !file){

        message(
          "رقم الموظف والصورة مطلوبان",
          true
        );

        return;

      }



      try{


        message(
          "جار الحفظ..."
        );


        const path =
          await uploadPhoto(
            employeeId.value.trim(),
            file
          );


        await saveEmployee(
          employeeId.value.trim(),
          path
        );



        const url =
          await signedUrl(path);



        if(url)
          preview.src=url;



        message(
          "تم حفظ الموظف والصورة بنجاح"
        );


        loadEmployees();



      }catch(error){

        message(
          error.message,
          true
        );

      }


    }
  );







  // LOAD EMPLOYEES

  async function loadEmployees(){

    if(!employeesList)
      return;


    const response =
      await fetch(

        baseUrl() +
        "/rest/v1/employees?select=*",

        {

          headers:
            headers()

        }

      );


    if(!response.ok)
      return;



    const employees =
      await response.json();



    employeesList.innerHTML="";



    for(const emp of employees){


      let photo="";


      if(emp.photo_path)

        photo =
          await signedUrl(
            emp.photo_path
          );



      employeesList.innerHTML += `

      <div class="employee-card">

        ${
          photo
          ?
          `<img class="employee-photo" src="${photo}">`
          :
          ""
        }


        <div class="employee-info">

          <b>${emp.full_name || ""}</b><br>

          الرقم:
          ${emp.employee_id || ""}<br>

          القسم:
          ${emp.department || ""}<br>

          الحالة:
          ${emp.status || ""}

        </div>

      </div>

      `;


    }

  }




  loadSession();


})();
