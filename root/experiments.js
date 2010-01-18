$.widget("ui.addExperimentDialog", {
    _init: function () {
        this.element.addClass("add_experiment");

        var input;
        var action;
        this.element
            .append($("<div>").addClass("box")
                    .append($("<table>")
                            .append($("<tr>")
                                    .append($("<th>").text("Name:"))
                                    .append($("<td>")
                                            .append(input = $("<input>")
                                                    .attr('type', 'text')
                                                    .attr('name', 'name')
                                                    .attr('size', 20)))
                                    .append($("<td>")
                                            .append(action = $("<input type='button' value='Create'>"))))));

        // Make sure the text box gets focus when it's shown.
        $(this.element).bind("after_toggle_or_show", null, function () { input[0].focus(); });

        var t = this;
        function create () {
            if (input[0].value.match(/^\s*$/))
                return;

            var xmlhttp = $.post(BASE_URI + 'ajax/newexperiment', { name: input[0].value }, function (data) {
                if (data.error) {
                    t.element.find("p.error").remove();
                    t.element.append($("<div>").append($("<p>")
                                     .addClass("error")
                                     .html(data.error)
                                     .append(" (")
                                     .append($("<span>").addClass("ok").text("OK").click(function () { t.element.find("p.error").hide("normal"); }))
                                     .append(")")));
                }
                else {
                    t.element.hide("normal", function () {
                        t.element.remove();
                        if (t.options.createdCallback)
                            t.options.createdCallback(input[0].value);
                    });
                }
            }, "json");
        }

        action.click(create);
        input.keypress(function (e) {
            if (e.which == 13) // Return
                create();
        });
    }
});

$.widget("ui.showExperiment", {
    _init: function () {
        this.element.addClass("experiment");

        var version = this.options.experiment[1].replace('/^\s+//', '').replace(/\s+$/, '');

        var delete_;
        var rename;
        var rename_opts;
        var lnk;
        var t = this;
        var lock = false;
        var ays;
        this.element
            .append(lnk = $("<a>").attr('href', BASE_URI + 'manage/' + escape(this.options.experiment[0]))
                                  .text(this.options.experiment[0]))
            .append(" (ibex ").append(version).append(") ")
            .append(" (").append(delete_ = $("<span>").addClass("linklike").text("delete"))
            .append(" | ").append(rename = $("<span>").addClass("linklike").text("rename")).append(")")
            .append(rename_opts = $("<div>")
                    .rename({
                        name: t.options.experiment[0],
                        actionCallback: function (newname) {
                            if (newname.match(/^\s*$/) || newname == t.options.experiment[0])
                                return;

                            var xmlhttp = $.post(BASE_URI + 'ajax/rename_experiment/' + escape(t.options.experiment[0]), { newname: newname }, function (data) { 
                                if (data.error) {
                                    rename_opts.rename("showError", data.error);
                                }
                                else {
                                    rename_opts.rename("hideError");
                                    if (t.options.renamedCallback)
                                        t.options.renamedCallback(newname);
                                }
                            }, "json");
                            xmlhttp.onreadystatechange = function () {
                                if (xmlhttp.readyState == 4) {

                                }
                            }            
                        },
                        cancelCallback: function () {
                            rename_opts.hide("normal", function () {
                                lock = false;
                            });
                        }
                    }))
            .append(ays = $("<div>").areYouSure({
                question: "Are you sure you want to delete this experiment?",
                actionText: "delete",
                uncheckedMessage: "Check the box before clicking to confirm that you want to delete the experiment.",
                cancelCallback: function () {
                    ays.hide("normal", function () { lock = false; });
                },
                actionCallback: function () {
                    var xmlhttp = $.post(BASE_URI + 'ajax/delete_experiment/' + escape(t.options.experiment[0]), { }, function (data) {
                        // Note that deleting an experiment cannot fail (barring some internal error in the server).
                        t.element.hide("slow", function () {
                            t.element.remove();
                            if (t.options.removedCallback)
                                t.options.removedCallback(t.options.experiment[0]);
                        });
                    }, "json");
                    xmlhttp.onreadystatechange = function () {
                        if (xmlhttp.readyState == 4) {

                        }
                    }
                }
            }).hide());

        if (this.options.highlight) {
            lnk.flash();
            window.location = "#highlighted";
        }

        delete_.click(function () {
            if (lock && lock != "delete")
                return;

            // Show the "are you sure?" thing.
            ays.toggle("normal", function () {
                lock = lock ? false : "delete";
            });
        });
        rename.click(function () {
            if (lock && lock != "rename")
                return;

            rename_opts.toggle("normal", function () {
                lock = lock ? false : "rename";
            });
            return true;
        });
    }
});

$.widget("ui.experimentList", {
    _init: function () {
        var t = this;

        function refresh (name) {
            t.options.highlight = name;
            t.element.empty();
            t._init();
        }

        spinnifyGET(this.element, this.options.url, function (data) {
            var experiments = data.experiments.sort(function (e1, e2) { return e1[0] < e2[0] ? -1 : (e1[0] == e2[0] ? 0 : 1) });

            if (experiments.length == 0) {
                t.element.addClass("no_experiments");
                t.element.append("You do not currently have any experiments set up.")
            }
            else {
                t.element.addClass("experiment_list");
                var ul;
                t.element.append(ul = $("<ul>"));

                for (var i = 0; i < experiments.length; ++i) {
                    ul.append($("<li>")
                              .showExperiment({ experiment: experiments[i],
                                                removedCallback: refresh,
                                                renamedCallback: refresh,
                                                highlight: experiments[i][0] == t.options.highlight }));
                }
            }

            var cexp;
            var opts;
            t.element.append($("<p>")
                             .append(cexp = $("<span>")
                                     .addClass("linklike")
                                     .addClass("create_experiment")
                                     .html("&raquo; Create a new experiment"))
                             .append(opts = $("<div>")
                                     .addExperimentDialog({ createdCallback: refresh })
                                     .hide()));
            cexp.click(function () {
                opts.toggle("normal");
            });    
        });
    }
});

$(document).ready(function () {
    $("#experiments").experimentList({ url: BASE_URI + 'ajax/experiments' });
});
