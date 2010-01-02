package IbexFarm::Controller::Ajax;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use IbexFarm;
use IbexFarm::FNames;
use IbexFarm::DeployIbex;
use File::Spec::Functions qw( splitdir catdir catfile splitpath no_upwards );
use File::stat;
use File::Path qw( make_path rmtree );
use File::Copy qw( move );
use DateTime;
use Encode;
use Encode::Guess;
use CGI qw( escapeHTML );

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
        STATIC_FILES_DIR => "www",
        CACHE_DIR => "cache",
        JS_INCLUDES_LIST => ["block"],
        CSS_INCLUDES_LIST => ["block"],
        DATA_INCLUDES_LIST => ["block"]
    );
    for my $k (keys %additions) { $h{$k} = $additions{$k}; }
    return \%h;
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

    # Authentication: we allow this if (a) it's a local request,
    # (b) it's from one of the hosts specified in the config file
    # or (c) they're logged in as the user who owns this experiment.
    unless ($c->req->hostname eq "localhost" ||
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
    die "Oh dear" unless (defined $contents);
    my $json = JSON::decode_json($contents);
    die "Bad JSON in 'CONFIG' file." unless (ref($json) eq "HASH");
    for my $k (keys %$json) { $c->stash->{$k} = $json->{$k}; }
    close $cnf or die "Unable to close 'CONFIG' after reading: $!";

    $c->detach($c->view("JSON"));
}

my @DIRS = qw( js_includes css_includes data_includes server_state results );
my %DIRS_TO_TYPES = (
    js_includes => 'text/javascript',
    css_includes => 'text/css',
    data_includes => 'text/javascript',
    server_state => 'text/plain',
    results => 'text/plain'
);
my %OPTIONAL_DIRS = ( server_state => 1, results => 1 );

sub get_dirs :Path("get_dirs") :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{dirs} = \@DIRS;
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
    my @upls = grep { $_ !~ /^\s*$/ } (map { chomp; $_; } <$wable>);
    close $upl or die "Unable to close 'UPLOADED' file in browse request.";
    push @wables, @upls;
    return @wables;
};

sub browse :Path("browse") :Args(0) {
    my ($self, $c) = @_;

    my $ps = $c->req->params;

    $c->detach('unauthorized') unless ($c->user_exists);
    $c->detach('bad_request') unless ($ps->{dir} &&
                                      (grep { $_ eq $ps->{dir} } @DIRS) &&
                                      $ps->{experiment} &&
                                      IbexFarm::FNames::is_ok_fname($ps->{experiment}));

    my $base = catdir(IbexFarm->config->{deployment_dir},
                      $c->user->username,
                      $ps->{experiment},
                      IbexFarm->config->{ibex_archive_root_dir});
    my $dir = catdir($base, $ps->{dir});

    if (! -d $dir) {
        if ($OPTIONAL_DIRS{$ps->{dir}}) {
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
        next if $e =~ /^[:.]/;

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

    $c->detach('bad_request') unless ((grep { $_ eq $dir } @DIRS) &&
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

    $c->res->code(200);
    $c->res->content_type($DIRS_TO_TYPES{$dir});
    $c->res->content_encoding($encoding);
    $c->res->body($contents);
}

sub experiments :Path("experiments") :Args(0) {
    my ($self, $c) = @_;

    $c->detach('unauthorized') unless $c->user_exists;

    my $dir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username);
    opendir my $DIR, $dir or die "Unable to open dir '$dir' for user: $!";
    my @exps;
    while (defined (my $e = readdir($DIR))) {
        next if $e =~ /^[:.]/;

        # Find the ibex version.
        my $versionfile = catfile($dir, $e, IbexFarm->config->{ibex_archive_root_dir}, "VERSION");
        open my $vf, $versionfile or die "Unable to open 'VERSION' file for reading: $!";
        my $version = <$vf>;
        die "Unable to read from 'VERSION' file: $!" unless (defined $version);
        close $vf or die "Unable to close 'VERSION' file: $!";

        push @exps, [$e, $version];
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

    # Does an experiment of that name already exist?
    if (-d catfile(IbexFarm->config->{deployment_dir},
                   $c->user->username,
                   $ps->{name})) {
        $c->stash->{error} = "An experiment of that name already exists for this user.";
        $c->detach($c->view("JSON"));
    }
    else {
        if (! IbexFarm::FNames::is_ok_fname($ps->{name})) {
            $c->stash->{error} = "Experiment names may contain only " . escapeHTML(IbexFarm::FNames::OK_CHARS_DESCRIPTION) . '.';
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
                external_config_url => "http://localhost/ajax/config",
                pass_params => 1,
                www_dir => $wwwdir
            );

            # Write a record of the configuration (file containing JSON dict).
            my $ibexdir = catfile($dir, $ps->{name}, IbexFarm->config->{ibex_archive_root_dir});
            open my $cnf, ">" . catfile($ibexdir, "CONFIG") or die "Unable to open 'CONFIG' file: $!";
            print $cnf JSON::encode_json(
                $get_default_config->(
                    IBEX_WORKING_DIR => catdir($dir, IbexFarm->config->{ibex_archive_root_dir})
                )
            );
            close $cnf or die "Unable to close 'CONFIG' file: $!";

            $c->detach($c->view("JSON")); # Empty dict indicates success.
        }
    }
}

sub rename_file :Path("rename_file") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless scalar(@_) == 3 && $c->req->params->{newname};
    my ($expname, $dir, $fname) = @_;
    my $newname = $c->req->params->{newname};

    unless (IbexFarm::FNames::is_ok_fname($newname)) {
        $c->stash->{error} = "Filenames may contain only " . escapeHTML(IbexFarm::FNames::OK_CHARS_DESCRIPTION);
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
        $c->detach($c->view("JSON"));
    }
}

# This is a bit unusual, in that it returns a string as its response (or the empty string
# for success) rather than JSON. This is to compensate for the inadequacies of the nasty
# Javascript handling the uploading.
my %currently_being_uploaded = ( );
my %currently_being_uploaded_sizes = ( );
sub upload_file :Path("upload_file") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless (scalar(@_) == 3 || scalar(@_) == 2) && $c->req->method eq "POST";

    my ($expname, $dir, $fname) = @_;
    # If the filename wasn't given, just use the name of the file that's being uploaded.
    if (! $fname) {
        if ($c->req->upload('userfile')) {
            $fname = $c->req->upload('userfile')->filename;
        }
        else {
            $c->detach('bad_request');
        }
    }
    # Check that the filename is ok.
    unless (IbexFarm::FNames::is_ok_fname($fname)) {
        $c->res->code(200);
        $c->res->content_type('text/html');
        $c->res->content_encoding('UTF-8');
        $c->res->body("Filenames may contain only " . escapeHTML(IbexFarm::FNames::OK_CHARS_DESCRIPTION));
        return 0;
    }

    my $file = $getfilename->($c, $expname, $dir, $fname);

    if (defined $currently_being_uploaded{$file}) {
        $c->res->code(200);
        $c->res->content_type('text/html');
        $c->res->content_encoding('UTF-8');
        $c->res->body("This location is already being uploaded to.");
        return 0;
    }
    else {
        my $u = $c->req->upload('userfile');
        if (! $u) { $c->detach('bad_request'); return; }
        if ($u->size > IbexFarm->config->{max_upload_size_bytes}) {
            $c->res->code(200);
            $c->res->content_type("text/html");
            $c->res->content_encoding("UTF-8");
            $c->res->body("The file is too large (maximum size is " . sprintf("%.1f", IbexFarm->config->{max_upload_size_bytes}/1024.0/1024.0) . " MB).");
            return 0;
        }
        else {
            # Check that either (a) the file doesn't currently exist
            # or (b) that the user has permission to write to this file.
            my @wables = $get_wables->(catdir(IbexFarm->config->{deployment_dir},
                                              $c->user->username,
                                              $expname,
                                              IbexFarm->config->{ibex_archive_root_dir}));
            my $fff = catfile($dir, $fname);
            if ((-e $file) && (! grep { $_ == $fff } @wables)) {
                $c->res->code(200);
                $c->res->content_type('text/html');
                $c->res->content_encoding('UTF-8');
                $c->res->body("You do not have permission to upload to this location.");
            }
            else {
                $currently_being_uploaded{$file} = 0;
                $currently_being_uploaded_sizes{$file} = $u->size;
                my $fh = $u->fh;

                my $n;
                while (($n = $fh->read(my $data, 1024*8)) > 0) {
                    $currently_being_uploaded{$file} += $n;
                }
                die "Error reading upload(ed/ing) file: $!" if ($n < 0);
                $fh->close or die "Unable to close temporary file handle during upload: $!";
    
                $u->copy_to($file) or die "Unable to copy uploaded file to final location: $!";

                undef $currently_being_uploaded{$file};
                undef $currently_being_uploaded_sizes{$file};

                # Keep a record of the fact that the user uploaded this file, so that
                # we know they're allowed to write to it. (First check that the user
                # hasn't already uploaded this file to make sure that we don't add
                # duplicate entries).
                my $uplfile = catfile(IbexFarm->config->{deployment_dir},
                                      $c->user->username,
                                      $expname,
                                      IbexFarm->config->{ibex_archive_root_dir},
                                      'UPLOADED');
                open my $uplr, $uplfile or die "Unable to open 'UPLOADED' file for reading in 'upload_file' request: $!";
                my $foundit = 0;
                while (my $line = <$uplr>) {
                    chomp $line;
                    $foundit = 1 if ($line eq $fff);
                }
                close $uplr or die "Unable to close 'UPLOADED' file after reading in 'upload_file' request: $!";
                if (! $foundit) {
                    open my $upl, ">>$uplfile" or die "Unable to open 'UPLOADED' file in 'upload_file' request: $!";
                    print $upl catfile($dir, $fname), "\n";
                    close $upl or die "Unable to close 'UPLOADED' file in 'upload_file' request: $!";
                }

                $c->res->code(200);
                $c->res->content_type('text/html');
                $c->res->content_encoding("UTF-8");
                $c->res->body(" "); # Have to set it to something because otherwise Catalyst thinks it hasn't been set (!)
                return 0;
            }
        }
    }
}

sub get_progress :Path("get_progress") {
    my ($self, $c) = (shift, shift);
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') unless scalar(@_) == 3;

    my ($expname, $dir, $fname) = @_;
    my $file = $getfilename->($c, $expname, $dir, $fname);

    $c->detach('default') unless (defined $currently_being_uploaded{$file});

    $c->stash->{bytes} = $currently_being_uploaded{$file};
    $c->stash->{size} = $currently_being_uploaded_sizes{$file};
    $c->detach($c->view("JSON"));
}

sub rename_experiment :Path("rename_experiment") {
    my ($self, $c) = (shift, shift);
    $c->detach('bad_request') unless $c->req->method eq "POST";
    $c->detach('unauthorized') unless $c->user_exists;
    $c->detach('bad_request') if scalar(@_) != 1 || (! $c->req->params->{newname});
    my $expname = shift;
    my $newname = $c->req->params->{newname};

    unless (IbexFarm::FNames::is_ok_fname($newname)) {
        $c->stash->{error} = "Experiment names may contain only " . escapeHTML(IbexFarm::FNames::OK_CHARS_DESCRIPTION);
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

    if (-d $newedir) {
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

my $ereq = sub {
    my ($self, $c, $code) = @_;
    $c->res->code($code);
    $c->res->content_type("text/json");
    $c->res->content_encoding("UTF-8");
    $c->res->body('null');
    return 0;
};

sub bad_request :Path { $ereq->(@_, 400); }
sub unauthorized :Path { $ereq->(@_, 401); }
sub conflict :Path { $ereq->(@_, 409); }
sub request_entity_too_large :Path { $ereq->(@_, 413); }
sub default :Path { $ereq->(@_, 404); }

1;
