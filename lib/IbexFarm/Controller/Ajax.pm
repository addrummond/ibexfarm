package IbexFarm::Controller::Ajax;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use IbexFarm;
use IbexFarm::FNames;
use IbexFarm::DeployIbex;
use IbexFarm::Quota;
use IbexFarm::AjaxHeaders qw( ajax_headers );
use File::Spec::Functions qw( splitdir catdir catfile splitpath no_upwards );
use File::stat;
use File::Path qw( make_path rmtree );
use File::Copy qw( move copy );
#use File::Copy::Recursive qw( dircopy );
use File::Temp;
use DateTime;
use Encode;
use Encode::Guess;
use HTML::GenerateUtil qw( escape_html );
use IbexFarm::PasswordProtectExperiment::Factory;
use IbexFarm::PasswordProtectExperiment::Apache;
use JSON::XS;
use IbexFarm::Util;
use Digest::MD5;

my $get_default_config = sub {
    my %additions = @_;

    my %h = (
        SERVER_MODE => "cgi",
        RESULT_FILES_DIR => "results",
        RESULT_FILE_NAME => "results",
	RAW_RESULT_FILE_NAME => "raw_results",
        SERVER_STATE_DIR => "server_state",
        INCLUDE_HEADERS_IN_RESULTS_FILE => \1,
        INCLUDE_COMMENTS_IN_RESULTS_FILE => \1,
        JS_INCLUDES_DIR => "js_includes",
        CSS_INCLUDES_DIR => "css_includes",
        DATA_INCLUDES_DIR => "data_includes",
        OTHER_INCLUDES_DIR => "other_includes",
        CHUNK_INCLUDES_DIR => "chunk_includes",
        STATIC_FILES_DIR => "www",
        CACHE_DIR => "cache",
        JS_INCLUDES_LIST => ["block"],
        CSS_INCLUDES_LIST => ["block"],
        DATA_INCLUDES_LIST => ["block"]
    );
    for my $k (keys %additions) { $h{$k} = $additions{$k}; }
    return \%h;
};

my $pre_check_quota = sub {
    my $c = shift;

    return 1 unless (IbexFarm->config->{enforce_quotas});
    return ! -f catfile(IbexFarm->config->{quota_record_dir}, "BAD_" . $c->user->username);
};

my $post_check_quota = sub {
    return 1 unless (IbexFarm->config->{enforce_quotas});

    my $c = shift;

    my $qdir = catdir(IbexFarm->config->{deployment_dir},
                       $c->user->username);
    my $qwwdir = catdir(IbexFarm->config->{deployment_www_dir},
                        $c->user->username);
    my ($ok, $e) = IbexFarm::Quota::check_quota({
        max_files_in_dir => IbexFarm->config->{quota_max_files_in_dir},
        max_file_size => IbexFarm->config->{quota_max_file_size},
        max_total_size => IbexFarm->config->{quota_max_total_size}
    }, $qdir, $qwwdir);

    # Keep a record of their quota violation.
    if (! $ok) {
        die "Oh no!" if (-e IbexFarm->config->{quota_record_dir} && ! -d IbexFarm->config->{quota_record_dir});
        if (! -d IbexFarm->config->{quota_record_dir}) {
            mkdir IbexFarm->config->{quota_record_dir} or die "Unable to make quota record dir: $!";
        }

        open my $t, ">" . catfile(IbexFarm->config->{quota_record_dir}, 'BAD_' . $c->user->username) or die "Unable to touch 'BAD_' record: $!";
        close $t or die "Error closing after touch: $!";
    }
    return ($ok, $e);
};

sub config_ : Path("config") :Args(0) { # 'config' seems to be reserved by Catalyst.
    my ($self, $c) = @_;
    my $ps = $c->req->params;

    $c->detach('bad_request') unless ($ps->{dir});

    # Get username and experiment name from dir containing server.py.
    my @www_dir = splitdir(IbexFarm->config->{deployment_www_dir});
    if ($www_dir[$#www_dir] eq '') { pop @www_dir; } # Handle paths with trailing '/'.
    if ($www_dir[0] eq '') { shift @www_dir; } # Ditto trailing '/'.
    my @rdir = splitdir($ps->{dir});
    # Sanity check: 'dir' must not contain '..', '.' or anything like that.
    $c->detach('bad_request') if scalar(no_upwards(@rdir) != scalar(@rdir));
    if ($rdir[$#rdir] eq '') { pop @rdir; }
    if ($rdir[0] eq '') { shift @rdir; }

    $c->detach('bad_request') if scalar(@www_dir) + 2 != scalar(@rdir);

    for (my $i = 0; $i < scalar(@www_dir); ++$i) {
        $c->detach('bad_request') unless ($www_dir[$i] eq $rdir[$i]);
    }

    # Tail of the path will be username/experiment name.
    my $username = $rdir[$#rdir-1];
    my $experiment_name = $rdir[$#rdir];

    # Authentication: we allow this if either (a) it's a local request,
    # (b) it's from one of the hosts specified in the config file
    # or (c) they're logged in as the user who owns this experiment.
    unless ((! $c->req->hostname) ||
            $c->req->hostname eq "localhost" ||
            (grep { $_ eq $c->req->hostname } @{IbexFarm->config->{config_permitted_hosts}}) ||
            ($c->user_exists && $c->user->username eq $username)) {
        $c->detach('unauthorized');
    }

    # Check that the experiment exists.
    my $expdir = catdir(IbexFarm->config->{deployment_dir}, $username, $experiment_name);
    $c->detach('default') unless (-d $expdir);

    # Open the CONFIG file for this experiment, parse the JSON
    # and return the JSON data structure giving config info.
    # (We could just slurp the file and send it right back, but it
    # seems like a good idea to check that it's actually valid JSON.)
    open my $cnf, catfile($expdir, IbexFarm->config->{ibex_archive_root_dir}, 'CONFIG')
        or die "Unable to open 'CONFIG' for reading: $!";
    local $/;
    my $contents = <$cnf>;
    close $cnf or die "Unable to close 'CONFIG' after reading: $!";
    die "Oh dear" unless (defined $contents);
    my $json = JSON::XS::decode_json($contents);
    die "Bad JSON in 'CONFIG' file." unless (ref($json) eq "HASH");
    for my $k (keys %$json) { $c->stash->{$k} = $json->{$k}; }

    $c->detach($c->view("JSON"));
}

sub get_dirs :Path("get_dirs") :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{dirs} = IbexFarm->config->{dirs};
    $c->detach($c->view("JSON"));
}

# Checks if two paths are equal, allowing for '*' wildcards
# (e.g. "/foo/bar" matches "/foo/bar/" and "/foo/bar",
#  "/foo/*" matches "/foo/bar", etc.)
my $check_match = sub {
    my ($p1, $p2) = @_;
    my @p1 = splitpath($p1);
    my @p2 = splitpath($p2);
    # Don't deny identity because of a trailing '/' in one but not the other.
    pop @p1 unless ($p1[$#p1]);
    pop @p2 unless ($p2[$#p2]);
    
    return 0 if (scalar(@p1) != scalar(@p2));

    for (my $i = 0; $i < scalar(@p2); ++$i) {
        return 0 unless ($p1[$i] eq "*" || $p2[$i] eq "*" || $p1[$i] eq $p2[$i]);
    }
    return 1;
};

my $get_wables = sub {
    my $base = shift;

    # Open the WRITABLE file, which tells us which files can be modified
    # by the user (one file per line).
    open my $wable, catfile($base, 'WRITABLE') or die "Unable to open 'WRITABLE' file in browse request.";
    my @wables = grep { $_ !~ /^\s*$/ } (map { chomp; $_; } <$wable>);
    close $wable or die "Unable to close 'WRITABLE' file in browse request.";
    # Ditto for the UPLOADED file (users can modify files which they uploaded).
    open my $upl, catfile($base, 'UPLOADED') or die "Unable to open 'UPLOADED' file in browse request.";
    my @upls = grep { $_ !~ /^\s*$/ } (map { chomp; $_; } <$upl>);
    close $upl or die "Unable to close 'UPLOADED' file in browse request.";
    push @wables, @upls;
    return @wables;
};

sub browse :Path("browse") :Args(0) {
    my ($self, $c) = @_;

    my $ps = $c->req->params;

    $c->detach('unauthorized') unless ($c->user_exists);
    $c->detach('bad_request') unless ($ps->{dir} &&
                                      (grep { $_ eq $ps->{dir} } @{IbexFarm->config->{dirs}}) &&
                                      $ps->{experiment} &&
                                      IbexFarm::FNames::is_ok_fname($ps->{experiment}));

    my $base = catdir(IbexFarm->config->{deployment_dir},
                      $c->user->username,
                      $ps->{experiment},
                      IbexFarm->config->{ibex_archive_root_dir});
    my $dir = catdir($base, $ps->{dir});

    if (! -d $dir) {
        if (IbexFarm->config->{optional_dirs}{$ps->{dir}}) {
            $c->stash->{not_present} = \1;
            $c->detach($c->view("JSON"));
            return;
        }
        else { die "Dir did not exist! ('$ps->{dir}')"; }
    }

    $c->detach('bad_request') unless (-d $dir);

    my @wables = $get_wables->($base);

    opendir my $DIR, $dir or die "Unable to open dir for browsing ('$dir'): $!";
    my @entries;
    while (defined (my $e = readdir($DIR))) {
        next if IbexFarm::Util::is_special_file($e);

        my $fn = catfile($dir, $e);
        my $stats = stat($fn) or die "Unable to stat file for browsing: $!";
        my $size = $stats->size || 0;
        my $modified = ($stats->mtime && DateTime->from_epoch(epoch => $stats->mtime)) || undef;
        if (ref($modified)) {
            $modified = [
                $modified->year,
                $modified->month,
                $modified->day,
                $modified->hour,
                $modified->minute,
                $modified->second
            ];
        }
        push @entries, [ -d $fn ? 1 : 0,
                         $e,
                         $size,
                         $modified,
                         (grep { $check_match->($_, catfile($ps->{dir}, $e)); } @wables) ? 1 : 0
                       ];
    }
    closedir($DIR) or die "Unable to close dir for browsing ('$dir'): $!";

    $c->stash->{entries} = \@entries;
    $c->detach($c->view("JSON"));
}

my $getfilename = sub {
    my ($c, $expname, $dir, $fname) = @_;
    return catfile(IbexFarm->config->{deployment_dir},
                   $c->user->username,
                   $expname,
                   IbexFarm->config->{ibex_archive_root_dir},
                   $dir,
                   $fname);
};

sub download :Path("download") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless scalar(@_) == 3;
    my ($expname, $dir, $fname) = @_;

    $c->detach('bad_request') unless ((grep { $_ eq $dir } @{IbexFarm->config->{dirs}}) &&
                                      IbexFarm::FNames::is_ok_fname($expname));

    # Neither 'dir' nor 'file' params should contain separators (this
    # is important for security reasons).
    my ($vol, $path, $file) = splitpath($dir);
    $c->detach('bad_request') if ($path || $vol);
    ($vol, $path, $file) = splitpath($fname);
    $c->detach('bad_request') if ($path || $vol);

    my $f = $getfilename->($c, $expname, $dir, $fname);
    $c->detach('default') unless (-f $f);

    # Slurp the file and serve it up;
    local $/;
    open my $fh, $f or die "Unable to open '$f' for slurping: $!";
    my $contents = <$fh>;
    close $fh or die "Unable to close '$f' after slurping: $!";
    die "Unable to slurp '$f': $!" unless defined($contents);

    my $decoder = Encode::Guess->guess($contents);
    my $encoding = ref($decoder) ? $decoder->name : "UTF-8";

    ajax_headers($c, IbexFarm->config->{dirs_to_types}{$dir}, $encoding);
    $c->res->body($contents || " ");
    return 0;
}

sub experiments :Path("experiments") :Args(0) {
    my ($self, $c) = @_;

    $c->detach('unauthorized') unless $c->user_exists;

    my $dir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username);
    opendir my $DIR, $dir or die "Unable to open dir '$dir' for user: $!";
    my @exps;
    while (defined (my $e = readdir($DIR))) {
        next if IbexFarm::Util::is_special_file($e) || $e eq IbexFarm->config->{USER_FILE_NAME};
        # If one experiment is corrupt, we should still list the others.
        eval {
            push @exps, [$e, IbexFarm::Util::get_experiment_version(catdir($dir, $e))];
        };
    }
    closedir $DIR or die "Unable to close dir '$dir' for user: $!";

    $c->stash->{experiments} = \@exps;
    $c->detach($c->view("JSON"));
}

sub newexperiment :Path("newexperiment") :Args(0) {
    my ($self, $c) = @_;
    $c->detach('bad_request') unless $c->req->method eq "POST" && $c->req->params->{name};
    $c->detach('unauthorized') unless $c->user_exists;

    my $ps = $c->req->params;

    # The 'USER' file is reserved, so they can't call experiments by that name.
    if ($ps->{name} eq IbexFarm->config->{USER_FILE_NAME}) {
        $c->stash->{error} = "Experiments may not be called '" . IbexFarm->config->{USER_FILE_NAME} . "'.";
        $c->detach($c->view("JSON"));
    }
    # Does an experiment of that name already exist?
    elsif (-d catfile(IbexFarm->config->{deployment_dir},
                   $c->user->username,
                   $ps->{name})) {
        $c->stash->{error} = "An experiment of that name already exists for this user.";
        $c->detach($c->view("JSON"));
    }
    else {
        if (! IbexFarm::FNames::is_ok_fname($ps->{name})) {
            $c->stash->{error} = "Experiment names may contain only " . escape_html(IbexFarm::FNames::OK_CHARS_DESCRIPTION) . 'and must be less than ' . IbexFarm->config->{max_fname_length} . ' characters long.';
            $c->detach($c->view("JSON"));
        }
        else {
            # Go ahead and create the new experiment.

            my $dir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username);
            my $wwwdir = catdir(IbexFarm->config->{deployment_www_dir}, $c->user->username);
            (-d $dir ? 1 : make_path(catdir(IbexFarm->config->{deployment_dir}, $c->user->username)))
            && (-d $wwwdir ? 1 : make_path(catdir(IbexFarm->config->{deployment_www_dir}, $c->user->username)))
            or die "Unable to create deployment dir and/or deployment www dir: $!";

            IbexFarm::DeployIbex::deploy(
                deployment_dir => $dir,
                ibex_archive => IbexFarm->config->{ibex_archive},
                ibex_archive_root_dir => IbexFarm->config->{ibex_archive_root_dir},
                name => $ps->{name},
                hashbang => IbexFarm->config->{python_hashbang},
                external_config_url => IbexFarm->config->{config_url},
                pass_params => 1,
                www_dir => $wwwdir
            );

            # Write a record of the configuration (file containing JSON dict).
            my $ibexdir = catfile($dir, $ps->{name}, IbexFarm->config->{ibex_archive_root_dir});
            open my $cnf, ">" . catfile($ibexdir, "CONFIG") or die "Unable to open 'CONFIG' file: $!";
            print $cnf JSON::XS::encode_json(
                $get_default_config->(
                    IBEX_WORKING_DIR => $ibexdir
                )
            );
            close $cnf or die "Unable to close 'CONFIG' file: $!";

            $c->detach($c->view("JSON")); # Empty dict indicates success.
        }
    }
}

# Args: (username, expname, add => [...], del => [...])
my $manage_UPLOADED = sub {
    my ($username, $expname, %opts) = @_;

    my $uplfile = catfile(IbexFarm->config->{deployment_dir},
                          $username,
                          $expname,
                          IbexFarm->config->{ibex_archive_root_dir},
                          'UPLOADED');
    open my $uplr, $uplfile or die "Unable to open 'UPLOADED' file: $!";
    local $/;
    my $contents = <$uplr>;
    close $uplr or die "Error closing 'UPLOADED' file: $!";
    die "Error reading 'UPLOADED' file: $!" unless (defined $contents);

    open my $uplw, ">$uplfile" or die "Unable to open 'UPLOADED' file: $!";
    my %dontadd;
    for my $line (split /\n/, $contents) {
        chomp $line;
        if ($opts{add}) { for my $toadd (@{$opts{add}}) {
            if ($toadd eq $line) { $dontadd{$line} = 1; }
        } }

        if ((! $opts{del}) || (! grep { $_ eq $line } @{$opts{del}})) {
            print $uplw "$line\n";
        }
    }

    for my $toadd (@{$opts{add}}) {
        if (! $dontadd{$toadd}) {
            print $uplw "$toadd\n";
        }
    }

    close $uplw or die "Unable to close 'UPLOADED' file: $!";
};

sub rename_file :Path("rename_file") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless scalar(@_) == 3 && $c->req->params->{newname};
    my ($expname, $dir, $fname) = @_;
    my $newname = $c->req->params->{newname};

    unless (IbexFarm::FNames::is_ok_fname($newname)) {
        $c->stash->{error} = "Filenames may contain only " . escape_html(IbexFarm::FNames::OK_CHARS_DESCRIPTION) . ' and must be less than ' . IbexFarm->config->{max_fname_length} . ' characters long.';
        $c->detach($c->view("JSON"));
        return;
    }

    my $file = $getfilename->($c, $expname, $dir, $fname);
    my $newfile = $getfilename->($c, $expname, $dir, $newname);

    if (-e $newfile) {
        $c->stash->{error} = "A file of that name already exists.";
    }
    elsif (! -f $file) {
        $c->detach('default');
    }
    else {
        move $file, $newfile or die "Unable to move file: $!";

        # Update the UPLOADED file.
        $manage_UPLOADED->($c->user->username, $expname,
                           add => [ catfile($dir, $newname) ],
                           del => [ catfile($dir, $fname) ]);

        $c->detach($c->view("JSON"));
    }
}

sub delete_file :Path("delete_file") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless scalar(@_) == 3;
    my ($expname, $dir, $fname) = @_;

    my $file = $getfilename->($c, $expname, $dir, $fname);

    if (! -f $file) {
        $c->detach('default');
    }
    else {
        unlink $file or die "Error deleting a file ('$file'): $!";

        $manage_UPLOADED->($c->user->username, $expname, del => [ catfile($dir, $fname) ]);

        $c->detach($c->view("JSON"));
    }
}

# This is a bit unusual, in that it returns a string as its response (or the empty string
# for success) rather than JSON. This is to compensate for the inadequacies of the nasty
# Javascript handling the uploading.
#
sub upload_file :Path("upload_file") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless (scalar(@_) == 3 || scalar(@_) == 2) && $c->req->method eq "POST";

    my $finalize = sub { $c->engine->finalize_read($c); };

    # Check that the user hasn't exceeded their quota.
    my ($ok, $qerror) = $pre_check_quota->($c);
    if (! $ok) {
        $finalize->();
        ajax_headers($c, 'text/html', 'UTF-8');
        $c->res->body("You have exceeded your quota. Please contact " .
                      escape_html(IbexFarm->config->{webmaster_name}) .
                      " (<a href='mailto:'" . escape_html(IbexFarm->config->{webmaster_email}) . "'>" .
                      escape_html(IbexFarm->config->{webmaster_email}) . "</a>) to resolve this issue.");
        return 0;
    }

    # Check file size.
    unless ($c->req->content_length <= IbexFarm->config->{max_upload_size_bytes}) {
        $finalize->();
        ajax_headers($c, 'text/html', 'UTF-8');
        $c->res->body("The maximum size for uploaded files is " . sprintf("%.2f", IbexFarm->config->{max_upload_size_bytes} / 1024.0 / 1024.0) . "MB.");
        return 0;
    }

    $c->prepare_body;

    my ($expname, $dir, $fname) = @_;
    my $up = $c->req->upload('userfile') or $c->detach('bad_request');
    # If the filename wasn't given, just use the name of the file that's being uploaded.
    $fname ||= $up->filename;

    if (! IbexFarm::FNames::is_ok_fname($fname)) {
        ajax_headers($c, 'text/html', 'UTF-8');
        $c->res->body("Filenames may contain only " . IbexFarm::FNames::OK_CHARS_DESCRIPTION . ' and must be less than ' . IbexFarm->config->{max_fname_length} . ' characters long.');
        return 0;
    }

    # Check that the dir is ok.
    $c->detach('bad_request') unless (grep { $_ eq $dir } @{IbexFarm->config->{dirs}} );
    # It may be that the dir doesn't exist yet ('results', 'server_state'), in
    # which case we create it.
    my $absdir = catdir(IbexFarm->config->{deployment_dir},
                        $c->user->username,
                        $expname,
                        IbexFarm->config->{ibex_archive_root_dir},
                        $dir);
    # If it exists, but as as something other than a dir, then...uh oh.
    die "Very weird" if (-e $absdir && ! -d $absdir);
    if (! -d $absdir) {
        mkdir $absdir or die "Unable to create dir '$absdir': $!";
    }

    my $file = $getfilename->($c, $expname, $dir, $fname);

    # Currently, haven't figured out a good way of checking that they're not uploading
    # concurrently to the same location (have to find a way of interfacing with the UploadProgress
    # plugin without modifying its code). I should fix this at some point, but it's not a
    # huge deal -- the second upload will just overwrite the first.
    if (0) {#(defined $currently_being_uploaded{$file}) {
        ajax_headers($c, 'text/html', 'UTF-8');
        $c->res->body("This location is already being uploaded to.");
        return 0;
    }
    else {
        my $u = $up;
        if (! $u) { $c->detach('bad_request'); return; }
        else { # TODO: Else not actually necessary here.
            # Check that either (a) the file doesn't currently exist
            # or (b) that the user has permission to write to this file.
            my @wables = $get_wables->(catdir(IbexFarm->config->{deployment_dir},
                                              $c->user->username,
                                              $expname,
                                              IbexFarm->config->{ibex_archive_root_dir}));
            my $fff = catfile($dir, $fname);
            if ((-e $file) && (! grep { $check_match->($_, $fff); } @wables)) {
                ajax_headers($c, 'text/html', 'UTF-8');
                $c->res->body("You do not have permission to upload to this location.");
            }
            else {
                $u->copy_to($file) or die "Unable to copy uploaded file to final location: $!";

                # Keep a record of the fact that the user uploaded this file, so that
                # we know they're allowed to write to it. (First check that the user
                # hasn't already uploaded this file to make sure that we don't add
                # duplicate entries).
                $manage_UPLOADED->($c->user->username,
                                   $expname,
                                   add => [ catfile($dir, $fname) ]);

                # If the user is now in violation of their quota, keep a record of this.
                $post_check_quota->($c);

                ajax_headers($c, 'text/html', 'UTF-8');
                $c->res->body(" "); # Have to set it to something because otherwise Catalyst thinks it hasn't been set (!)
                return 0;
            }
        }
    }
}

sub rename_experiment :Path("rename_experiment") {
    my ($self, $c) = (shift, shift);
    $c->detach('bad_request') unless $c->req->method eq "POST";
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') if scalar(@_) != 1 || (! $c->req->params->{newname});
    my $expname = shift;
    my $newname = $c->req->params->{newname};

    unless (IbexFarm::FNames::is_ok_fname($newname)) {
        $c->stash->{error} = "Experiment names may contain only " . escape_html(IbexFarm::FNames::OK_CHARS_DESCRIPTION) . ' and must be less than ' . IbexFarm->config->{max_fname_length} . ' characters long.';
        $c->detach($c->view("JSON"));
        return;
    }

    my $edir = catdir(IbexFarm->config->{deployment_dir},
                      $c->user->username,
                      $expname);
    my $newedir = catdir(IbexFarm->config->{deployment_dir},
                         $c->user->username,
                         $newname);
    $c->detach('default') unless (-d $edir);
    die "OMG!" if (-e $newedir && ! -d $newedir);

    if ($expname eq IbexFarm->config->{USER_FILE_NAME}) {
        $c->stash->{error} = "Experiments may not be called '" . IbexFarm->config->{USER_FILE_NAME} . "'.";
        $c->detach($c->view("JSON"));
    }
    elsif (-d $newedir) {
        $c->stash->{error} = "An experiment of that name already exists.";
        $c->detach($c->view("JSON"));
    }
    else {
        my $ewwwdir;
        my $newewwwdir;
        if (IbexFarm->config->{deployment_www_dir}) {
            $ewwwdir = catdir(IbexFarm->config->{deployment_www_dir},
                              $c->user->username,,
                              $expname);
            $newewwwdir = catdir(IbexFarm->config->{deployment_www_dir},
                                $c->user->username,
                                $newname);
            die "Inconsistency!" unless -d $ewwwdir && ! -e $newewwwdir;
        }

        # Update the working dir config paramater.
        open my $cnf, catfile($edir, IbexFarm->config->{ibex_archive_root_dir}, 'CONFIG')
            or die "Unable to open 'CONFIG' for reading: $!";
        local $/;
        my $contents = <$cnf>;
        close $cnf or die "Unable to close 'CONFIG' after reading: $!";
        die "Oh dear" unless (defined $contents);
        my $json = JSON::XS::decode_json($contents);
        die "Bad JSON in 'CONFIG' file." unless (ref($json) eq "HASH" && $json->{IBEX_WORKING_DIR});
        $json->{IBEX_WORKING_DIR} = catdir($newedir, IbexFarm->config->{ibex_archive_root_dir});
        open my $ocnf, '>' . catfile($edir, IbexFarm->config->{ibex_archive_root_dir}, 'CONFIG');
        print $ocnf JSON::XS::encode_json($json);
        close $ocnf or die "Unable to close 'CONFIG' after writing: $!";

        # Finally, move the dir(s).
        move($edir, $newedir) or die "Error moving: $!";
        if ($ewwwdir) {
            move($ewwwdir, $newewwwdir) or die "Error moving www: $!";
        }

        $c->detach($c->view("JSON"));
    }
}

sub delete_experiment :Path("delete_experiment") {
    my ($self, $c) = (shift, shift);
    $c->detach('bad_request') unless $c->req->method eq "POST";
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') if scalar(@_) != 1;
    my $expname = shift;

    my $edir = catdir(IbexFarm->config->{deployment_dir},
                      $c->user->username,
                      $expname);
    $c->detach('default') unless (-d $edir);

    # Check that the www dir also exists if these are separate.
    my $ewwdir;
    if (IbexFarm->config->{deployment_www_dir}) {
        $ewwdir = catdir(IbexFarm->config->{deployment_www_dir},
                         $c->user->username,
                         $expname);
        die "Inconsistency!" unless (-d $ewwdir)
    }

    # Delete the dirs.
    my @todelete = $edir;
    push @todelete, $ewwdir if $ewwdir;
    my $r = rmtree(\@todelete, 0, 0);
    unless ($r) {
        die "Error deleting experiment '$expname' of user '", $c->user->username, "': [$r] $!";
    }

    $c->detach($c->view("JSON")); # This will return the empty hash {} as the result.
}

sub get_experiment_auth_status :Path("get_experiment_auth_status") {
    my ($self, $c) = (shift, shift);
    $c->detach('default') unless (IbexFarm->config->{experiment_password_protection});
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless (scalar(@_) == 1);
    my $expname = shift;

    # Check that the experiment exists.
    my $dir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username, $expname);
    $c->detach('default') unless (-d $dir);

    my $authfile = catfile(IbexFarm->config->{deployment_dir},
                           $c->user->username,
                           $expname,
                           IbexFarm->config->{ibex_archive_root_dir},
                           'AUTH');
    if (! -f $authfile) {
        $c->detach($c->view("JSON"));
    }
    else {
        open my $auth, $authfile or die "Unable to open 'AUTH' file: $!";
        local $/;
        my $contents = <$auth>;
        close $auth or die "Unable to close 'AUTH' file: $!";
        chomp $contents;
        if ((! $contents) || $contents =~ /^\s*$/) {
            $c->detach($c->view("JSON"));
        }
        else {
            $c->stash->{username} = $contents;
            $c->detach($c->view("JSON"));
        }
    }
}

sub password_protect_experiment :Path("password_protect_experiment") {
    my ($self, $c) = (shift, shift);
    $c->detach('default') unless (IbexFarm->config->{experiment_password_protection});
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless ($c->req->method eq "POST" && scalar(@_) == 1 && ($c->req->params->{password} || $c->req->params->{remove}));
    my $expname = shift;

    # Check that the experiment exists.
    my $dir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username, $expname);
    $c->detach('default') unless (-d $dir);

    # Get hold of whatever implementation of password protection it is that we're using.
    my $pwp = IbexFarm::PasswordProtectExperiment::Factory->new(IbexFarm->config->{experiment_password_protection});

    my $username;
    my $authfile = catfile(IbexFarm->config->{deployment_dir},
                           $c->user->username,
                           $expname,
                           IbexFarm->config->{ibex_archive_root_dir},
                           'AUTH');
    if ($c->req->params->{password}) {
        $username = $pwp->password_protect_experiment($c->user->username, $expname, $c->req->params->{password});
        open my $auth, ">$authfile";
        print $auth $username;
        close $auth or die "Unable to close 'AUTH' file: $!";
    }
    else {
        $pwp->password_unprotect_experiment($c->user->username, $expname);
        if (-f $authfile) {
            unlink $authfile or die "Unable to delete 'AUTH' file: $!";
        }
    }

    $c->stash->{username} = $username if $username;
    $c->detach($c->view("JSON"));
}

sub from_git_repo :Path("from_git_repo") {
    my ($self, $c) = (shift, shift);
    $c->detach('default') unless (IbexFarm->config->{git_path});
    $c->detach('unauthorized') unless ($c->user_exists);
    $c->detach('bad_request') unless ($c->req->method eq 'POST' && scalar(@_) == 0 && $c->req->params->{url} && $c->req->params->{expname});
    my $git_url = $c->req->params->{url};

    # The commented out code below is the old code, which (quite bizarrely stupidly) didn't
    # maintain a separate history for each experiemnt.
#    # Update the user's profile to keep track of the git repo/branch they just used.
#    my $ufile = catfile(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME});
#    IbexFarm::Util::update_json_file(
#        $ufile,
#        sub {
#            my $json = shift;
#            $json->{git_repo_url} = $git_url,
#            $json->{git_repo_branch} = $c->req->params->{branch};
#            return $json;
#        }
#    );

    my $ufile = catfile(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME});
    IbexFarm::Util::update_json_file(
	$ufile,
	sub {
	    my $json = shift;
	    $json->{git_repos} = { } unless $json->{git_repos};
	    $json->{git_repos}{$c->req->params->{expname}} = {
		url => $git_url,
		branch => $c->req->params->{branch}
	    };
	    $json;
	}
    );

    # Get a temporary dir for checking out the git repo.
    my $tmpdir = File::Temp::tempdir();
    $tmpdir or die "Unable to create temporary dir for checking out git repo: $!";

    # Get a temporary file for storing any error messages from git.
    my ($tempefilefh, $tempefile) = File::Temp::tempfile();
    $tempefilefh or die "Unable to create temporary error file for checking out git repo: $!";

    # Checkout the repo. Setting a timeout here to prevent checking out of enormous
    # repos (should probably set a size limit too, but haven't figured out a good
    # way of doing this yet). See:
    #     http://www.linuxquestions.org/questions/programming-9/perl-can-i-make-the-system-function-timeout-386890/
    # for example code (although the code there doesn't bother to kill the child process).
    my $pid;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n"; };
        if (($pid = fork()) == 0) {
            my @as = (IbexFarm->config->{git_path}, 'clone');
            push @as, '--depth', '1', '-b', $c->req->params->{branch} if ($c->req->params->{branch});
            push @as, $git_url, $tmpdir;
            open STDERR, ">$tempefile" or die "Unable to redirect STDERR for executing git: $!";
            exec(@as);
        }
        # calls to exec never return, so we only get here if we're in the parent process.
        alarm IbexFarm->config->{git_checkout_timeout_seconds};
        waitpid($pid, 0) == -1 and die "WTF?!";
        alarm 0;
    };
    # Again, must be in the parent process at this point.
    if ($@) {
        # Kill the git process.
        kill 9, $pid;

        if (-e $tmpdir) { rmtree([$tmpdir], 0, 0) or die "Unable to remove temporary git repo checkout dir (15): $!"; }
        close $tempefilefh or die "Unable to delete temporary git error message file.";

        die $@ unless ($@ eq "alarm\n");
        # It timed out.
        $c->stash->{error} = "Timeout while trying to check out repository (try again soon)";
        $c->detach($c->view("JSON"));
    }
    if ($?) { # git process exited with an error.
        if (-e $tmpdir) { rmtree([$tmpdir], 0, 0) || die "Unable to remove temporary git repo checkout dir (1): $!"; }
        local $/;
        seek $tempefilefh, 0, 0 or die "Error seeking: $!";
        $c->stash->{error} = substr(<$tempefilefh>, 0, 1000); # Don't send huge error messages.
        close $tempefilefh or die "Unable to close temporary git error message file.";
        $c->detach($c->view("JSON"));
    }
    close $tempefilefh or die "Unable to delete temporary git error message file.";

    my $edir = catdir(IbexFarm->config->{deployment_dir},
                      $c->user->username,
                      $c->req->params->{expname});

    my @dirs_modified;
    my @files_modified;
    for my $dir (@{IbexFarm->config->{sync_dirs}}) {
        next unless (-d catdir($tmpdir, $dir));

        opendir my $DIR, catdir($tmpdir, $dir) or die "Unable to open dir: $!";
        while (defined (my $entry = readdir($DIR))) {
            next if IbexFarm::Util::is_special_file($entry);

            my $moddir = sub {
                push @dirs_modified, $dir unless (grep { $_ eq $dir } @dirs_modified);
            };

            my $oldf = catfile($edir, IbexFarm->config->{ibex_archive_root_dir}, $dir, $entry);
            my $newf = catfile($tmpdir, $dir, $entry);
            eval {
                # Don't compute MD5 hashes for non-existent or large files.
                if ((! -e $oldf) || -s $oldf > 65536 || -s $newf > 65536) {
                    push @files_modified, catfile($dir, $entry);
                    $moddir->();
                }
                else {
                    open my $of, $oldf;
                    open my $nf, $newf;
                    local $/;
                    my ($oldc, $newc) = (<$of>, <$nf>);
                    close $of; close $nf;
                    if (Digest::MD5::md5_hex($oldc) ne Digest::MD5::md5_hex($newc)) {
                        push @files_modified, catfile($dir, $entry);
                        $moddir->();
                    }
                }
            };
            if ($@) {
                die "Error futzing around with MD5s: $!";
            }

            copy(catfile($tmpdir, $dir, $entry), catfile($edir, IbexFarm->config->{ibex_archive_root_dir}, $dir, $entry)) or die "Copying error: $!";
        }
    }

    # Remove the temporary dir.
    rmtree([$tmpdir], 0, 0) or die "Unable to clean up temp dir in from_git_repo: $!";

    $c->stash->{dirs_modified} = \@dirs_modified;
    $c->stash->{files_modified} = \@files_modified;
    $c->detach($c->view("JSON"));
}

my $ereq = sub {
    my ($c, $code) = @_;
    ajax_headers($c, 'text/json', 'UTF-8', $code);
    $c->res->body('null');
    return 0;
};

sub bad_request :Path { $ereq->($_[1], 400); }
sub unauthorized :Path { $ereq->($_[1], 401); }
sub conflict :Path { $ereq->($_[1], 409); }
sub request_entity_too_large :Path { $ereq->($_[1], 413); }
sub default :Path { $ereq->($_[1], 404); }

1;
