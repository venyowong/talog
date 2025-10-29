const amisLib = amisRequire('amis');
amisLib.registerFilter('md5', function (value) {
  return md5(value)
});

const onRequest = function(api) {
  api.headers = {
    ...api.headers,
    'token': localStorage.getItem("token")
  };
  return api;
}

const onResponse = function(api, payload, query, request, response) {
  if (response.status == 401) {
    window.location = "./login.html";
    return
  }
  payload.status = payload.code;

  return payload;
}

const request = function(method, url, body) {
  let xhr = new XMLHttpRequest();
  xhr.open(method, url, false);
  xhr.setRequestHeader('token', localStorage.getItem("token"));
  if (body) {
    xhr.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
  }
  xhr.send(body);
  if (xhr.status == 401) {
    window.location = "./login.html";
    return
  }
  return JSON.parse(xhr.responseText);
}