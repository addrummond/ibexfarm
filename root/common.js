// IE caches all ajax GET requests, so when using IE always use POST.
/*@cc_on
$.getJSON=function(uri,callback){return $.post(uri,{},callback,"json");};
(function(){var oldajax=$.ajax; $.ajax=function(opts){opts.type="POST";return oldajax(opts);};})();
@*/

$(document).ready(function () {
    // XHTML standards compliance idiocy.
    $("a[rel=external]").attr('target', '_blank');

    // Move to error/message div if there is one on the page.
    var e = $(".error");
    if (e.length && ! $(e[0]).hasClass("noskipto")) {
        $(e[0]).attr('id', 'error');
        window.location = '#error';
    }
    else {
        var m = $(".message");
        if (m.length && ! $(m[0]).hasClass("noskipto")) {
            $(m[0]).attr('id', 'message');
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
