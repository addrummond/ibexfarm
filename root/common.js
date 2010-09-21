// IE caches all ajax GET requests, so when using IE always use POST.
/*@cc_on
$.getJSON=function(uri,callback){return $.post(uri,{},callback,"json");};
(function(){var oldajax=$.ajax;$.ajax=function(opts){opts.type="POST";return oldajax(opts);};})();
@*/

var STD_TOGGLE_SPEED = "fast";

// Taken from http://www.quirksmode.org/js/cookies.html
function createCookie(name,value,days) {
    if (days) {
        var date = new Date();
        date.setTime(date.getTime()+(days*24*60*60*1000));
        var expires = "; expires="+date.toGMTString();
    }
    else var expires = "";
    document.cookie = name+"="+value+expires+"; path=/";
}

// As above.
function readCookie(name) {
    var nameEQ = name + "=";
    var ca = document.cookie.split(';');
    for(var i=0;i < ca.length;i++) {
        var c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1,c.length);
            if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
    }
    return null;
}

// As above.
function eraseCookie(name) {
    createCookie(name,"",-1);
}

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
