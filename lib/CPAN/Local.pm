package CPAN::Local;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       update_local_cpan_index
                       list_local_cpan_packages
                       list_local_cpan_modules
                       list_local_cpan_dists
                       list_local_cpan_authors
                       list_local_cpan_deps
                       list_local_cpan_rev_deps
               );

our %SPEC;

my %common_args = (
    cpan => {
        schema => 'str*',
        summary => 'Location of your local CPAN mirror, e.g. /path/to/cpan',
        description => <<'_',

Defaults to C<~/cpan>.

_
    },
);

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Manage local CPAN mirror',
};

sub _set_args_default {
    my $args = shift;
    if (!$args->{cpan}) {
        require File::HomeDir;
        $args->{cpan} = File::HomeDir->my_home . '/cpan';
    }
}

sub _connect_db {
    require DBI;

    my $cpan = shift;

    my $db_path = "$cpan/index.db";
    $log->tracef("Connecting to SQLite database at %s ...", $db_path);
    DBI->connect("dbi:SQLite:dbname=$db_path", undef, undef,
                 {RaiseError=>1});
}

sub _create_schema {
    require SQL::Schema::Versioned;

    my $dbh = shift;

    my $spec = {
        latest_v => 1,

        install => [
            'CREATE TABLE author (
                 cpanid VARCHAR(20) NOT NULL PRIMARY KEY,
                 fullname VARCHAR(255) NOT NULL,
                 email TEXT
             )',

            'CREATE TABLE file (
                 id INTEGER NOT NULL PRIMARY KEY,
                 name TEXT NOT NULL,
                 cpanid VARCHAR(20) NOT NULL REFERENCES author(cpanid),

                 -- processing status: ok (meta has been extracted and parsed),
                 -- nometa (file does contain cpan meta), nofile (file does not
                 -- exist in mirror), unsupported (file type is not supported,
                 -- e.g. rar, non archive), metaerr (meta has some error), err
                 -- (other error).
                 status TEXT
             )',
            'CREATE UNIQUE INDEX ix_file__name ON file(name)',

            'CREATE TABLE module (
                 id INTEGER NOT NULL PRIMARY KEY,
                 name VARCHAR(255) NOT NULL,
                 file_id INTEGER NOT NULL,
                 version VARCHAR(20)
             )',
            'CREATE UNIQUE INDEX ix_module__name ON module(name)',
            'CREATE INDEX ix_module__file_id ON module(file_id)',

            # this is inserted
            'CREATE TABLE dist (
                 id INTEGER NOT NULL PRIMARY KEY,
                 name VARCHAR(90) NOT NULL,
                 abstract TEXT,
                 file_id INTEGER NOT NULL,
                 version VARCHAR(20)
             )',
            'CREATE INDEX ix_dist__name ON dist(name)',
            'CREATE UNIQUE INDEX ix_dist__file_id ON dist(file_id)',

            'CREATE TABLE dep (
                 dist_id INTEGER,
                 module_id INTEGER, -- if module is known (listed in module table), only its id will be recorded here
                 module_name TEXT,  -- if module is unknown (unlisted in module table), only the name will be recorded here
                 rel TEXT, -- relationship: requires, ...
                 phase TEXT, -- runtime, ...
                 version TEXT,
                 FOREIGN KEY (dist_id) REFERENCES dist(id),
                 FOREIGN KEY (module_id) REFERENCES module(id)
             )',
            'CREATE INDEX ix_dep__module_name ON dep(module_name)',
            'CREATE UNIQUE INDEX ix_dep__dist_id__module_id ON dep(dist_id,module_id)',
        ], # install
    }; # spec

    my $res = SQL::Schema::Versioned::create_or_update_db_schema(
        dbh => $dbh, spec => $spec);
    die "Can't create/update schema: $res->[0] - $res->[1]\n"
        unless $res->[0] == 200;
}

sub _parse_json {
    my $content = shift;

    state $json = do {
        require JSON;
        JSON->new;
    };
    my $data;
    eval {
        $data = $json->decode($content);
    };
    if ($@) {
        $log->errorf("Can't parse JSON: %s", $@);
        return undef;
    } else {
        return $data;
    }
}

sub _parse_yaml {
    require YAML::Syck;

    my $content = shift;

    my $data;
    eval {
        $data = YAML::Syck::Load($content);
    };
    if ($@) {
        $log->errorf("Can't parse YAML: %s", $@);
        return undef;
    } else {
        return $data;
    }
}

sub _add_prereqs {
    my ($dist_id, $hash, $phase, $rel, $sth_ins_dep, $sth_sel_mod) = @_;
    $log->tracef("  Adding prereqs (%s %s): %s", $phase, $rel, $hash);
    for my $mod (keys %$hash) {
        $sth_sel_mod->execute($mod);
        my $row = $sth_sel_mod->fetchrow_hashref;
        my ($mod_id, $mod_name);
        if ($row) {
            $mod_id = $row->{id};
        } else {
            $mod_name = $mod;
        }
        $sth_ins_dep->execute($dist_id, $mod_id, $mod_name, $phase,
                              $rel, $hash->{$mod});
    }
}

$SPEC{'update_local_cpan_files'} = {
    v => 1.1,
    args => {
        %common_args,
    },
};
sub update_local_cpan_files {
    require IPC::System::Options;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    IPC::System::Options::system(
        {die=>1, log=>1},
        "minicpan", "-l", $cpan, "-r", "http://mirrors.kernel.org/cpan",
    );
}

$SPEC{'update_local_cpan_index'} = {
    v => 1.1,
    args => {
        %common_args,
    },
};
sub update_local_cpan_index {
    require DBI;
    require File::Slurp::Tiny;
    require IO::Compress::Gzip;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    my $dbh  = _connect_db($cpan);
    _create_schema($dbh);

    # parse 01mailrc.txt.gz and insert the parse result to 'author' table
    {
        my $path = "$cpan/authors/01mailrc.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        my $sth = $dbh->prepare("INSERT OR IGNORE INTO author (cpanid,fullname,email) VALUES (?,?,?)");
        $dbh->begin_work;
        my $line = 0;
        while (<$fh>) {
            $line++;
            my ($cpanid, $fullname, $email) = /^alias (\S+)\s+"(.*) <(.+)>"/ or do {
                $log->warnf("  line %d: syntax error, skipped: %s", $line, $_);
                next;
            };
            $sth->execute($cpanid, $fullname, $email);
            my $id = $dbh->last_insert_id("","","","");
            if ($id) {
                $log->tracef("  new author: %s", $cpanid);
            }
        }
        $dbh->commit;
    }

    # parse 02packages.details.txt.gz and insert the parse result to 'file' and
    # 'module' tables. we haven't parsed distribution names yet because that
    # will need information from META.{json,yaml} inside release files.
    {
        my $path = "$cpan/modules/02packages.details.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        my $sth_ins_file = $dbh->prepare("INSERT OR IGNORE INTO file (name,cpanid) VALUES (?,?)");
        my $sth_ins_mod  = $dbh->prepare("INSERT OR REPLACE INTO module (name,file_id,version) VALUES (?,?,?)");

        $dbh->begin_work;

        my %files_in_table;
        my $sth = $dbh->prepare("SELECT name,id FROM file");
        while (my ($name, $id) = $sth->fetchrow_array) {
            $files_in_table{$name} = $id;
        }

        my %files_in_02packages; # key=filename, val=id (or undef if already exists in db)
        my $line = 0;
        while (<$fh>) {
            $line++;
            next unless /\S/;
            next if /^\S+:\s/;
            chomp;
            #say "D:$_";
            my ($pkg, $ver, $path) = split /\s+/, $_;
            $ver = undef if $ver eq 'undef';
            my ($author, $file) = $path =~ m!^./../(.+?)/(.+)! or do {
                $log->warnf("  line %d: Invalid path %s, skipped", $line, $path);
                next;
            };
            my $file_id;
            if (exists $files_in_02packages{$file}) {
                $file_id = $files_in_02packages{$file};
            } else {
                $sth_ins_file->execute($file, $author);
                $file_id = $dbh->last_insert_id("","","","");
                $log->tracef("  New file: %s", $file) if $file_id;
                $files_in_02packages{$file} = $file_id;
            }
            next unless $file_id;

            $sth_ins_mod->execute($pkg, $file_id, $ver);
            $log->tracef("  New/updated module: %s", $pkg);
        } # while <fh>

        # cleanup: delete file record (as well as dists, modules, and deps
        # records) for files in db that are no longer in 02packages.
      CLEANUP:
        {
            my @old_file_ids;
            for (keys %files_in_table) {
                push @old_file_ids, $files_in_table{$_}
                    unless exists $files_in_table{$_};
            }
            last CLEANUP unless @old_file_ids;
            $dbh->do("DELETE FROM dep WHERE dist_id IN (SELECT id FROM dist WHERE file_id IN (".join(",",@old_file_ids)."))");
            $dbh->do("DELETE FROM module WHERE file_id IN (".join(",",@old_file_ids).")");
            $dbh->do("DELETE FROM dist WHERE file_id IN (".join(",",@old_file_ids).")");
        }

        $dbh->commit;
    }

    # for each new file, try to extract its CPAN META
    {
        my $sth = $dbh->prepare("SELECT * FROM file WHERE status IS NULL");
        $sth->execute;
        my @files;
        while (my $row = $sth->fetchrow_hashref) {
            push @files, $row;
        }

        my $sth_set_file_status = $dbh->prepare("UPDATE file SET status=? WHERE id=?");
        my $sth_ins_dist = $dbh->prepare("INSERT OR REPLACE INTO dist (name,abstract,file_id,version) VALUES (?,?,?,?)");
        my $sth_ins_dep = $dbh->prepare("INSERT OR REPLACE INTO dep (dist_id,module_id,module_name,phase,rel, version) VALUES (?,?,?,?,?, ?)");
        my $sth_sel_mod  = $dbh->prepare("SELECT * FROM module WHERE name=?");

        my $i = 0;
        my $after_begin;

      FILE:
        for my $file (@files) {
            # commit after every 500 files
            if ($i % 500 == 499) {
                $log->tracef("COMMIT");
                $dbh->commit;
                $after_begin = 0;
            }
            if ($i % 500 == 0) {
                $log->tracef("BEGIN");
                $dbh->begin_work;
                $after_begin = 1;
            }
            $i++;

            $log->tracef("[#%i] Processing file %s ...", $i, $file->{name});
            my $status;
            my $path = "$cpan/authors/id/".substr($file->{cpanid}, 0, 1)."/".
                substr($file->{cpanid}, 0, 2)."/$file->{cpanid}/$file->{name}";

            unless (-f $path) {
                $log->errorf("File %s doesn't exist, skipped", $path);
                $sth_set_file_status->execute("nofile", $file->{id});
                next FILE;
            }

            # extract META.yml or META.json
            my $meta;
          GET_META:
            {
                unless ($path =~ /(.+)\.(tar|tar\.gz|tar\.bz2|tar\.Z|tgz|tbz2?|zip)$/i) {
                    $log->errorf("Doesn't support file type: %s, skipped", $file->{name});
                    $sth_set_file_status->execute("unsupported", $file->{id});
                    next FILE;
                }

                my ($name, $ext) = ($1, $2);
                if (-f "$name.meta") {
                    $log->tracef("Getting meta from .meta file: %s", "$name.meta");
                    eval { $meta = _parse_json(~~File::Slurp::Tiny::read_file("$name.meta")) };
                    unless ($meta) {
                        $log->errorf("Can't read %s: %s", "$name.meta", $@) if $@;
                        $sth_set_file_status->execute("err", $file->{id});
                        next FILE;
                    }
                    last GET_META;
                }

                eval {
                    if ($path =~ /\.zip$/i) {
                        require Archive::Zip;
                        my $zip = Archive::Zip->new;
                        $zip->read($path) == Archive::Zip::AZ_OK()
                            or die "Can't read zip file";
                        for my $member ($zip->members) {
                            if ($member->fileName =~ m!(?:/|\\)META.(yml|json)$!) {
                                #$log->tracef("  found %s", $member->fileName);
                                my $type = $1;
                                my $content = $zip->contents($member);
                                #$log->trace("[[$content]]");
                                if ($type eq 'yml') {
                                    $meta = _parse_yaml($content);
                                } else {
                                    $meta = _parse_json($content);
                                }
                                return; # from eval
                            }
                        }
                    } else {
                        require Archive::Tar;
                        my $tar = Archive::Tar->new;
                        $tar->read($path);
                        for my $member ($tar->list_files) {
                            if ($member =~ m!/META\.(yml|json)$!) {
                                #$log->tracef("  found %s", $member);
                                my $type = $1;
                                my ($obj) = $tar->get_files($member);
                                my $content = $obj->get_content;
                                #$log->trace("[[$content]]");
                                if ($type eq 'yml') {
                                    $meta = _parse_yaml($content);
                                } else {
                                    $meta = _parse_json($content);
                                }
                                return; # from eval
                            }
                        }
                    }
                }; # eval

                if ($@) {
                    $log->errorf("Can't extract meta from file %s: %s", $path, $@);
                    $sth_set_file_status->execute("err", $file->{id});
                    next FILE;
                }
            } # GET_META

            unless ($meta) {
                $log->infof("File %s doesn't contain META.json/META.yml, skipped", $path);
                $sth_set_file_status->execute("nometa", $file->{id});
                next FILE;
            }

            unless (ref($meta) eq 'HASH') {
                $log->infof("meta is not a hash, skipped");
                $sth_set_file_status->execute("metaerr", $file->{id});
                next FILE;
            }

            my $dist_name = $meta->{name};
            if (!defined($dist_name)) {
                $log->errorf("meta does not contain name, skipped");
                $sth_set_file_status->execute("metaerr", $file->{id});
                next FILE;
            }
            $dist_name =~ s/::/-/g; # sometimes author miswrites module name
            # insert dist record
            $sth_ins_dist->execute($dist_name, $meta->{abstract}, $file->{id}, $meta->{version});
            my $dist_id = $dbh->last_insert_id("","","","");

            # insert dependency information
            if (ref($meta->{build_requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{build_requires}, 'build', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{configure_requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{configure_requires}, 'configure', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{requires}, 'runtime', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{prereqs}) eq 'HASH') {
                for my $phase (keys %{ $meta->{prereqs} }) {
                    my $phprereqs = $meta->{prereqs}{$phase};
                    for my $rel (keys %$phprereqs) {
                        _add_prereqs($dist_id, $phprereqs->{$rel}, $phase, $rel, $sth_ins_dep, $sth_sel_mod);
                    }
                }
            }

            $sth_set_file_status->execute("ok", $file->{id});
        } # for file
        if ($after_begin) {
            $log->tracef("COMMIT");
            $dbh->commit;
        }
    }

    # there remains some files for which we haven't determine the dist name of
    # (e.g. non-existing file, no meta, can't parse meta). we determine the dist
    # from the module name.
    {
        my $sth = $dbh->prepare("SELECT id FROM file WHERE NOT EXISTS (SELECT id FROM dist WHERE file_id=file.id)");
        my @file_ids;
        $sth->execute;
        while (my ($id) = $sth->fetchrow_array) {
            push @file_ids, $id;
        }

        my $sth_sel_mod = $dbh->prepare("SELECT * FROM module WHERE file_id=? ORDER BY name LIMIT 1");
        my $sth_ins_dist = $dbh->prepare("INSERT INTO dist (name,file_id,version) VALUES (?,?,?)");

        $dbh->begin_work;
      FILE:
        for my $file_id (@file_ids) {
            $sth_sel_mod->execute($file_id);
            my $row = $sth_sel_mod->fetchrow_hashref or next FILE;
            my $dist_name = $row->{name};
            $dist_name =~ s/::/-/g;
            $log->tracef("Setting dist name for %s as %s", $row->{name}, $dist_name);
            $sth_ins_dist->execute($dist_name, $file_id, $row->{version});
        }
        $dbh->commit;
    }

    $log->tracef("Disconnecting from SQLite database ...");
    $dbh->disconnect;

    [200];
}

$SPEC{'update_local_cpan'} = {
    v => 1.1,
    args => {
        %common_args,
    },
};
sub update_local_cpan {
    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    update_local_cpan_files(%args);
    update_local_cpan_index(%args);
}

$SPEC{'stat_local_cpan'} = {
    v => 1.1,
    args => {
        %common_args,
    },
};
sub stat_local_cpan {
    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    [501, "Not yet implemented"];
}

sub _complete_mod {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);
    _set_args_default($res->[2]);

    my $dbh;
    eval { $dbh = _connect_db($res->[2]{cpan}) };

    # if we can't connect (probably because database is not yet setup), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT name FROM module WHERE name LIKE ? ORDER BY name");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($mod) = $sth->fetchrow_array) {
        # only complete one level deeper at a time
        if ($mod =~ /:\z/) {
            next unless $mod =~ /\A\Q$word\E:*\w+\z/i;
        } else {
            next unless $mod =~ /\A\Q$word\E\w*(::\w+)?\z/i;
        }
        push @res, $mod;
    }

    \@res;
};

sub _complete_dist {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);
    _set_args_default($res->[2]);

    my $dbh;
    eval { $dbh = _connect_db($res->[2]{cpan}) };

    # if we can't connect (probably because database is not yet setup), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT name FROM dist WHERE name LIKE ? ORDER BY name");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($dist) = $sth->fetchrow_array) {
        # only complete one level deeper at a time
        #if ($dist =~ /-\z/) {
        #    next unless $dist =~ /\A\Q$word\E-*\w+\z/i;
        #} else {
        #    next unless $dist =~ /\A\Q$word\E\w*(-\w+)?\z/i;
        #}
        push @res, $dist;
    }

    \@res;
};

sub _complete_cpanid {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);
    _set_args_default($res->[2]);

    my $dbh;
    eval { $dbh = _connect_db($res->[2]{cpan}) };

    # if we can't connect (probably because database is not yet setup), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT cpanid FROM author WHERE cpanid LIKE ? ORDER BY cpanid");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($cpanid) = $sth->fetchrow_array) {
        push @res, $cpanid;
    }

    \@res;
};

my %query_args = (
    query => {
        summary => 'Search query',
        schema => 'str*',
        cmdline_aliases => {q=>{}},
        pos => 0,
    },
    detail => {
        schema => 'bool',
    },
);

$SPEC{list_local_cpan_authors} = {
    v => 1.1,
    summary => 'List authors in local CPAN',
    args => {
        %common_args,
        %query_args,
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of CPAN ID's. If you set `detail` to true, will
return array of records.

_
    },
    examples => [
        {
            summary => 'List all authors',
            argv    => [],
            test    => 0,
        },
        {
            summary => 'Find CPAN IDs which start with something',
            argv    => ['MICHAEL%'],
            result  => ['MICHAEL', 'MICHAELW'],
            test    => 0,
        },
    ],
};
# XXX filter cpanid
sub list_local_cpan_authors {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db($cpan);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(cpanid LIKE ? OR fullname LIKE ? OR email like ?)";
        push @bind, $q, $q, $q;
    }
    my $sql = "SELECT
  cpanid id,
  fullname name,
  email
FROM author".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY id";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{id};
    }
    \@res;
}

$SPEC{list_local_cpan_packages} = {
    v => 1.1,
    summary => 'List packages in local CPAN',
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
            completion => \&_complete_cpanid,
        },
        dist => {
            summary => 'Filter by distribution',
            schema => 'str*',
            cmdline_aliases => {d=>{}},
            completion => \&_complete_dist,
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of package names. If you set `detail` to true,
will return array of records.

_
    },
};
sub list_local_cpan_packages {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db($cpan);

    my @bind;
    my @where;
    if (length($q)) {
        #push @where, "(name LIKE ? OR dist LIKE ?)"; # rather slow
        push @where, "(name LIKE ?)";
        push @bind, $q;#, $q;
    }
    if ($args{author}) {
        #push @where, "(dist_id IN (SELECT dist_id FROM dist WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @where, "(author=?)";
        push @bind, $args{author};
    }
    if ($args{dist}) {
        #push @where, "(dist_id=(SELECT dist_id FROM dist WHERE dist_name=?))";
        push @where, "(dist=?)";
        push @bind, $args{dist};
    }
    my $sql = "SELECT
  name,
  version,
  (SELECT name FROM dist WHERE dist.file_id=module.file_id) dist,
  (SELECT cpanid FROM file WHERE id=module.file_id) author
FROM module".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    \@res;
}

$SPEC{list_local_cpan_modules} = $SPEC{list_local_cpan_packages};
sub list_local_cpan_modules {
    goto &list_local_cpan_packages;
}

$SPEC{list_local_cpan_dists} = {
    v => 1.1,
    summary => 'List distributions in local CPAN',
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
            completion => \&_complete_cpanid,
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of distribution names. If you set `detail` to
true, will return array of records.

_
    },
    examples => [
        {
            summary => 'List all distributions',
            argv    => ['--cpan', '/cpan'],
            test    => 0,
        },
        {
            summary => 'Grep by distribution name, return detailed record',
            argv    => ['--cpan', '/cpan', 'data-table'],
            test    => 0,
        },
        {
            summary   => 'Filter by author, return JSON',
            src       => 'list-local-cpan-dists --cpan /cpan --author perlancar --json',
            src_plang => 'bash',
            test      => 0,
        },
    ],
};
sub list_local_cpan_dists {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $detail = $args{detail};
    my $q = $args{query} // '';
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db($cpan);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(name LIKE ?)";
        push @bind, $q;
    }
    if ($args{author}) {
        #push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @where, "(author=?)";
        push @bind, $args{author};
    }
    my $sql = "SELECT
  name,
  version,
  (SELECT name FROM file WHERE id=dist.file_id) file,
  (SELECT cpanid FROM file WHERE id=dist.file_id) author
FROM dist".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    \@res;
}

sub _get_prereqs {
    require Module::CoreList;
    require Version::Util;

    my ($mod, $dbh, $memory, $level, $max_level, $phase, $rel, $include_core, $plver) = @_;

    $log->tracef("Finding dependencies for module %s (level=%i) ...", $mod, $level);

    # first find out which distribution that module belongs to
    my $sth = $dbh->prepare("SELECT id FROM dist WHERE file_id=(SELECT file_id FROM module WHERE name=?)");
    $sth->execute($mod);
    my ($dist_id) = $sth->fetchrow_array;
    return [404, "No such module: $mod"] unless $dist_id;

    # fetch the dependency information
    $sth = $dbh->prepare("SELECT
  CASE WHEN dp.module_id THEN (SELECT name FROM module WHERE id=dp.module_id) ELSE dp.module_name END AS module,
  phase,
  rel,
  version
FROM dep dp
WHERE dp.dist_id=?
ORDER BY module");
    $sth->execute($dist_id);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        #say "include_core=$include_core, is_core($row->{module}, $row->{version}, $plver)=", Module::CoreList::is_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        next if !$include_core && Module::CoreList::is_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        if (defined $memory->{$row->{module}}) {
            if (Version::Util::version_gt($row->{version}, $memory->{$row->{module}})) {
                $memory->{$row->{version}} = $row->{version};
            }
            next;
        }
        delete $row->{phase} unless $phase eq 'ALL';
        delete $row->{rel}   unless $rel   eq 'ALL';
        $row->{level} = $level;
        push @res, $row;
        $memory->{$row->{module}} = $row->{version};
    }

    if (@res && ($max_level==-1 || $level < $max_level)) {
        my $i = @res-1;
        while ($i >= 0) {
            my $subres = _get_prereqs($res[$i]{module}, $dbh, $memory,
                                      $level+1, $max_level, $phase, $rel, $include_core, $plver);
            $i--;
            next if $subres->[0] != 200;
            splice @res, $i+2, 0, @{$subres->[2]};
        }
    }

    [200, "OK", \@res];
}

sub _get_revdeps {
    my ($mod, $dbh) = @_;

    $log->tracef("Finding reverse dependencies for module %s ...", $mod);

    # first, check that module is listed
    my ($mod_id) = $dbh->selectrow_array("SELECT id FROM module WHERE name=?", {}, $mod)
        or return [404, "No such module: $mod"];

    # get all dists that depend on that module
    my $sth = $dbh->prepare("SELECT
  (SELECT name    FROM dist WHERE dp.dist_id=dist.id) AS dist,
  (SELECT version FROM dist WHERE dp.dist_id=dist.id) AS dist_version,
  -- phase,
  -- rel,
  version req_version
FROM dep dp
WHERE module_id=?
ORDER BY dist");
    $sth->execute($mod_id);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        #next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        #next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        #delete $row->{phase} unless $phase eq 'ALL';
        #delete $row->{rel}   unless $rel   eq 'ALL';
        push @res, $row;
    }

    [200, "OK", \@res];
}

my %mod_args = (
    module => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_mod,
    },
);

my %deps_args = (
    phase => {
        schema => ['str*' => {
            in => [qw/develop configure build runtime test ALL/],
        }],
        default => 'runtime',
    },
    rel => {
        schema => ['str*' => {
            in => [qw/requires recommends suggests conflicts ALL/],
        }],
        default => 'requires',
    },
    level => {
        summary => 'Recurse for a number of levels (-1 means unlimited)',
        schema  => 'int*',
        default => 1,
        cmdline_aliases => {
            l => {},
            R => {
                summary => 'Recurse (alias for `--level -1`)',
                is_flag => 1,
                code => sub { $_[0]{level} = -1 },
            },
        },
    },
    include_core => {
        summary => 'Include Perl core modules',
        'summary.alt.bool.not' => 'Exclude Perl core modules',
        schema  => 'bool',
        default => 0,
    },
    perl_version => {
        summary => 'Set base Perl version for determining core modules',
        schema  => 'str*',
        default => "$^V",
        cmdline_aliases => {V=>{}},
    },
);

$SPEC{'list_local_cpan_deps'} = {
    v => 1.1,
    summary => 'List dependencies of a module, data from local CPAN',
    args => {
        %common_args,
        %mod_args,
        %deps_args,
    },
};
sub list_local_cpan_deps {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $mod     = $args{module};
    my $phase   = $args{phase} // 'runtime';
    my $rel     = $args{rel} // 'requires';
    my $plver   = $args{perl_version} // "$^V";
    my $level   = $args{level} // 1;
    my $include_core = $args{include_core} // 0;

    my $dbh     = _connect_db($cpan);

    my $res = _get_prereqs($mod, $dbh, {}, 1, $level, $phase, $rel, $include_core, $plver);

    return $res unless $res->[0] == 200;
    for (@{$res->[2]}) {
        $_->{module} = ("  " x ($_->{level}-1)) . $_->{module};
        delete $_->{level};
    }

    $res;
}

$SPEC{'list_local_cpan_rev_deps'} = {
    v => 1.1,
    summary => 'List reverse dependencies of a module, data from local CPAN',
    args => {
        %common_args,
        %mod_args,
    },
};
sub list_local_cpan_rev_deps {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $mod     = $args{module};

    my $dbh     = _connect_db($cpan);

    _get_revdeps($mod, $dbh);
}

1;
# ABSTRACT: Manage your local CPAN mirror

=head1 SYNOPSIS

See L<local-cpan> script.


=head1 HISTORY

This application began as L<CPAN::SQLite::CPANMeta>, an extension of
L<CPAN::SQLite>. C<CPAN::SQLite> parses C<02packages.details.txt.gz> and
C<01mailrc.txt.gz> and puts the parse result into a SQLite database.
C<CPAN::SQLite::CPANMeta> parses the C<META.json>/C<META.yml> files in
individual release files and adds it to the SQLite database.

In order to simplify things for the users (one-step indexing) and get more
freedom in database schema, C<CPAN::Local> skips using C<CPAN::SQLite> and
creates the SQLite database itself. It also parses C<02packages.details.txt.gz>
but does not parse distribution names from it but instead uses C<META.json> and
C<META.yml> files extracted from the release files.

=cut
