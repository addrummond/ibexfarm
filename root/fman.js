function show_date (date) {
    return date[0] + '-' + date[1] + '-' + date[2] + ' ' + date[3] + ':' + date[4] + ':' + date[5];
}

var generateProgressID;
(function () {
var alpha = "0123456789abcdef";
generateProgressID = function () {
    var id = '';
    for(var i=0; i < 32; i++) {
        id += alpha.charAt(Math.round(Math.random()*14));
    }
    return id;
}
})();

$.widget("ui.browseFile", {
    _init: function () {
        this.element.addClass("file").addClass(this.options.writable ? "writable" : "unwritable");

        var t = this;
        var download;
        var delete_;
        var upload;
        var ays;
        var rename;
        var rename_opts;
        var ulinfo;
        var ulmsg;
        var fname;
        var ncols = 0; // Keep track of number of cols in first <tr> so that we can set
                       // a colspan property later (gross eh?)
        var lock = false;
        this.element.append(
            $("<table>")
                .append($("<tr>")
                        .append(++ncols && (fname = ($("<td>")
                                .text(this.options.filename))))
                        .append(++ncols && $("<td>")
                                .append(download = $("<div>")
                                        .addClass("download_file")
                                        .append("(")
                                        .append($("<a>")
                                                .attr('href', BASE_URI +
                                                              'ajax/download/' + escape(EXPERIMENT) + '/' +
                                                              escape(this.options.dir) + '/' +
                                                              escape(this.options.filename))
                                                .text("download"))
                                        .append(this.options.writable ? "" : ")")))
                        .append(delete_ = ((! this.options.writable) ? null : ++ncols && $("<td>")
                                .append($("<div>")
                                        .addClass("delete_file")
                                        .append(" | ")
                                        .append($("<span>").addClass("linklike").text("delete")))))
                        .append(rename = ((! this.options.writable) ? null : ++ncols && $("<td>")
                                .append($("<div>")
                                        .addClass("rename")
                                        .append(" | ")
                                        .append($("<span>").addClass("linklike").text("rename")))))
                        .append(((! this.options.writable) ? null : ++ncols && $("<td>")
                                .append($("<div>")
                                        .append(" | ")
                                        .append(upload = $("<span>")
                                                             .addClass("linklike")
                                                             .text("upload new version"))
                                        .append(")"))))
                        .attr('title', 'Modified ' + show_date(this.options.modified)))
                .append((! this.options.writable) ? null : $("<tr>")
                        .append($("<td colspan='" + ncols + "'>")
                                .append(ulinfo = $("<div>")
                                        .append(ulmsg = $("<span>"))
                                        .hide())))
        ).append(
            rename_opts = $("<div>")
                .rename({
                    name: this.options.filename,
                    cancelCallback: function () {
                        rename_opts.hide("normal", function () {
                            lock = false;
                        });
                    },
                    actionCallback: function (newname) {
                        if (newname.match(/^\s*$/) || newname == t.options.filename)
                            return;

                        var xmlhttp = $.post(BASE_URI + 'ajax/rename_file/' + escape(EXPERIMENT) + '/' + escape(t.options.dir) + '/' + escape(t.options.filename), { newname: newname }, function (data) {
                            if (data.error) {
                                rename_opts.rename("showError", data.error);
                            }
                            else {
                                rename_opts.rename("hideError");
                                if (t.options.renamedCallback)
                                    t.options.renamedCallback(newname)
                            }
                        }, "json");
                        xmlhttp.onreadystatechange = function () {
                            if (xmlhttp.readyState == 4) {
                                
                            }
                        }
                    }
                })
        ).append(
            ays = $("<div>")
                .areYouSure({
                    question: "Are you sure you want to delete this file?",
                    actionText: "yes, delete it",
                    uncheckedMessage: "Check the box before clicking to confirm that you want to delete the file.",
                    cancelCallback: function () {
                        ays.hide("normal", function () {
                            lock = false;
                        });
                    },
                    actionCallback: function () {
                        var xmlhttp = $.getJSON(
                            BASE_URI +
                            'ajax/delete_file/' +
                            escape(EXPERIMENT) + '/' +
                            escape(t.options.dir) + '/' +
                            escape(t.options.filename),
                            function (data) {
                                if (t.options.deletedCallback)
                                    t.options.deletedCallback();
                            }
                        );
                        xmlhttp.onreadystatechange = function () {
                            if (xmlhttp.readyState == 4) {

                            }
                        };
                    }
                }).hide()
        );

        if (this.options.highlight) {
            fname.flash();
            window.location = "#highlighted";
        }

        if (delete_) {
            delete_.click(function () {
                if (lock && lock != "delete")
                    return;

                ays.toggle("normal", function () {
                    lock = lock ? false : "delete";
                });
            });
        }
        if (rename) {
            rename.click(function () {
                if (lock && lock != "rename")
                    return;

                rename_opts.toggle("normal", function () {
                    lock = lock ? false : "rename";
                });
            });
        }
        if (upload) {
            var intervalId;

            var progressId = generateProgressID();
            new AjaxUpload(upload, {
                hoverClass: 'hoverClass',
                action: BASE_URI + 'ajax/upload_file/' +
                        escape(EXPERIMENT) + '/' +
                        escape(t.options.dir) + '/' +
                        escape(t.options.filename) +
                        '?progress_id=' + progressId
                ,
                name: "userfile",
                autoSubmit: true,
                data: { },
                responseType: false,
                onSubmit: function (file, extension) {
                    ulmsg.removeClass("error");
                    ulmsg.text("Uploading: 0%");
                    ulinfo.show("normal");

                    // Poll server for progress info on file upload.
                    var first = 0;
                    intervalId = setInterval(function () {
                        if (! first++) return;
                        var xmlhttp = $.getJSON(
                            BASE_URI + 'progress?progress_id=' + progressId,
                            function (data) {
                                if (! (data && ((data.received==0) || data.received) && data.size))
                                    clearInterval(intervalId);
                                else if (data.aborted) {
                                    ulmsg.addClass("error");
                                    ulmsg.text("Upload aborted.");
                                    clearInterval(intervalId);
                                }
                                else {
                                    var bytes = data.received;
                                    var size = data.size;
                                    if (size > 0)
                                        ulmsg.text("Uploading: " + parseInt(bytes*100.0 / size) + "%");
                                    if (bytes == size)
                                        clearInterval(intervalId);
                                }
                            }
                        );
                        xmlhttp.onreadystatechange = function () {
                            if (xmlhttp.readyState == 4) {
                                
                            }
                        };
                    }, 500);

                    return true; // Don't cancel upload.
                },
                onComplete: function (file, response) {
                    clearInterval(intervalId);

                    if (! response.match(/^\s*$/)) {
                        ulmsg.addClass("error");
                        ulmsg.html(response)
                            .append(" (")
                            .append($("<span>").addClass("ok").text("OK").click(function () { ulinfo.hide("normal"); }))
                            .append(")");
                    }
                    else {
                        ulmsg.empty();
                        ulmsg.append("Upload complete (")
                             .append($("<span>").addClass("ok").text("OK").click(function () { ulinfo.hide("normal"); }))
                             .append(")");
                    }
                }
            });
        }
    }
});

$.widget("ui.browseDir", {
    _init: function () {
        var t = this;
        var xmlhttp = $.getJSON(BASE_URI + 'ajax/browse?dir=' + escape(this.options.dir) + '&experiment=' + escape(EXPERIMENT), function (data) {
            t.element.addClass("dir");

            function refresh (highlight) {
                t.element.empty();
                t.options.highlight = highlight;
                t._init();
            }

            var table;
            var upload;
            var upload_msg;
            t.element.append(table = $("<table>")
                             .append($("<tr>")
                                     .append($("<th>")
                                             .text("/" + t.options.dir + " (")
                                             .append(upload = $("<span>")
                                                     .addClass("linklike")
                                                     .text("upload a file to this directory"))
                                             .append(")")))
                             .append($("<tr>")
                                     .append($("<td>")
                                             .append(upload_msg = $("<div>").hide()))));

            var progressId = generateProgressID();
            var intervalId;
            new AjaxUpload(upload, {
                hoverClass: 'hoverClass',
                action: BASE_URI + 'ajax/upload_file/' +
                        escape(EXPERIMENT) + '/' +
                        escape(t.options.dir) +
	                '?progress_id=' + progressId
                ,
                name: "userfile",
                autoSubmit: true,
                data: { },
                responseType: false,
                onSubmit: function (file, extension) {
                    upload_msg.removeClass("error");
                    upload_msg.text("Uploading: 0%");
                    upload_msg.show("normal");

                    // Poll server for progress info on file upload.
                    var first = 0;
                    intervalId = setInterval(function () {
                        if (! first++) return;
                        var xmlhttp = $.getJSON(
                            BASE_URI + 'progress?progress_id=' + progressId
                            ,
                            function (data) {
                                if (! (data && ((data.received==0) || data.received) && data.size))
                                    clearInterval(intervalId);
                                else if (data.aborted) {
                                    upload_msg.addClass("error");
                                    upload_msg.text("Upload aborted.");
                                    clearInterval(intervalId);
                                }
                                else {
                                    var bytes = data.received;
                                    var size = data.size;
                                    if (size > 0)
                                        upload_msg.text("Uploading: " + parseInt(bytes*100.0 / size) + "%");
                                    if (bytes == size)
                                        clearInterval(intervalId);
                                }
                            }
                        );
                        xmlhttp.onreadystatechange = function () {
                            if (xmlhttp.readyState == 4) {
                                
                            }
                        }
                    }, 500);
                },
                onComplete: function (file, response) {
                    clearInterval(intervalId);

                    if (! response.match(/^\s*$/)) {
                        upload_msg.addClass("error");
                        upload_msg.html(response)
                            .append(" (")
                            .append($("<span>").addClass("ok").text("OK").click(function () { upload_msg.hide("normal"); }))
                            .append(")");
                    }
                    else {
                        upload_msg.empty();
                        refresh(file);
                    }
                }
            });

            if (data.not_present) {
                t.element.append($("<tr>").append($("<td>").addClass("not_present").text("[This directory is not present]")));
            }
            else {
                for (var i = 0; i < data.entries.length; ++i) {
                    if (data.entries[i][0]) continue; // Ignore dirs.

                    var filename = data.entries[i][1];
                    var size     = data.entries[i][2];
                    var modified = data.entries[i][3];
                    var writable = data.entries[i][4];

                    t.element.append($("<tr>").append($("<td>").append($("<div>").browseFile({
                        filename: filename,
                        highlight: filename == t.options.highlight,
                        size: size,
                        dir: t.options.dir,
                        modified: modified,
                        writable: writable,
                        deletedCallback: refresh,
                        renamedCallback: refresh
                    }))));
                }
            }
        });
        xmlhttp.onreadystatechange = function () {
            if (xmlhttp.readyState == 4) {
                
            }
        }
    }
});

$(document).ready(function () {
    var xmlhttp = $.getJSON(BASE_URI + 'ajax/get_dirs', function (data) {
        var sdirs = data.dirs.sort();
        for (var i = 0; i < data.dirs.length; ++i) {
            $("#files").append($("<div>").browseDir({ dir: sdirs[i] }));
        }
    });
    xmlhttp.onreadystatechange = function () {
        if (xmlhttp.readyState == 4) {

        }
    }
});
