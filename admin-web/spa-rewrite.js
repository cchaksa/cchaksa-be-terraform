function handler(event) {
  var request = event.request;
  var method = request.method;
  var uri = request.uri;

  if ((method !== "GET" && method !== "HEAD") || uri.indexOf("/api/") === 0) {
    return request;
  }

  var lastSegment = uri.substring(uri.lastIndexOf("/") + 1);
  if (uri.charAt(uri.length - 1) === "/" || lastSegment.indexOf(".") === -1) {
    request.uri = "/index.html";
  }

  return request;
}
