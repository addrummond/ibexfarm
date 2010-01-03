// Focus appropriate filed in form on login/create account.
$(document).ready(function () {
    var u = $("input[name=username]")[0];
    if ($("input[name=email]").length || ! $(u).attr('value'))
        u.focus();
    else
        $("input[name=password]")[0].focus();
});