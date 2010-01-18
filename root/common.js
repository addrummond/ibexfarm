// IE caches all ajax GET requests, so when using IE always use POST.
/*@cc_on
$.getJSON=function(uri,callback){return $.post(uri,{},callback,"json");};
(function(){var oldajax=$.ajax;$.ajax=function(opts){opts.type="POST";return oldajax(opts);};})();
@*/

$.ajaxSetup({cache: false, global: false});

// Turning off caching can cause jQuery to send POST instead of GET.
// For file progress queries, we must ensure that a GET request is sent.
function cachedGetJSON(url, callback) {
    return $.ajax({
        cache: true,
        url: url,
        type: "GET",
        success: callback,
        dataType: "json"
    });
}

$(document).ready(function () {
    // XHTML standards compliance idiocy.
    $("a[rel=external]").attr('target', '_blank');

    // Move to error/message div if there is one on the page.
    var e = $(".error");
    if (e.length && ! $(e.get(0)).hasClass("noskipto")) {
        $(e.get(0)).attr('id', 'error');
        window.location = '#error';
    }
    else {
        var m = $(".message");
        if (m.length && ! $(m.get(0)).hasClass("noskipto")) {
            $(m.get(0)).attr('id', 'message');
            window.location = '#message';
        }
    }

    // Message divs dissapear after a few seconds.
    setTimeout(function () {
        var ms = $(".message");
        for (var i = 0; i < ms.length; ++i) {
            if ($(m[i]).hasClass("dontremove"))
                $(ms[i]).fadeTo("slow", 0);
            else
                $(ms[i]).fadeOut("slow");
        }
    }, 3000);
});
