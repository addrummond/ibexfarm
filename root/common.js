// IE caches all ajax GET requests, so when using IE always use POST.
/*@cc_on
$.getJSON=function(uri,callback){return $.post(uri,{},callback,"json");}
@*/

// XHTML standards compliance idiocy.
$(document).ready(function () {
    $("a[rel=external]").attr('target', '_blank');
});

