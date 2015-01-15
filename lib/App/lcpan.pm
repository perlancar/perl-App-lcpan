package App::lcpan;

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
                       list_local_cpan_releases
                       list_local_cpan_authors
                       list_local_cpan_deps
                       list_local_cpan_rev_deps

                       mod2dist
                       mod2rel
                       dist2rel
                       distmods
                       authormods
                       authordists
                       authorrels
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

sub _relpath {
    my ($filename, $cpan, $cpanid) = @_;
    $cpanid = uc($cpanid); # just to be safe
    "$cpan/authors/id/".substr($cpanid, 0, 1)."/".
        substr($cpanid, 0, 2)."/$cpanid/$filename";
}

sub _create_schema {
    require SQL::Schema::Versioned;

    my $dbh = shift;

    my $spec = {
        latest_v => 3,

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
                 -- nofile (file does not exist in mirror), unsupported (file
                 -- type is not supported, e.g. rar, non archive), metaerr
                 -- (META.json/META.yml has some error), nometa (no
                 -- META.json/META.yml found), err (other error).
                 status TEXT,

                 has_metajson INTEGER,
                 has_metayml INTEGER,
                 has_makefilepl INTEGER,
                 has_buildpl INTEGER
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

        upgrade_to_v2 => [
            # actually we don't have any schema changes in v2, but we want to
            # reindex release files that haven't been successfully indexed
            # because aside from META.{json,yml}, we now can get information
            # from Makefile.PL or Build.PL.
            qq|DELETE FROM dep  WHERE dist_id IN (SELECT id FROM dist WHERE file_id IN (SELECT id FROM file WHERE status<>'ok'))|, # shouldn't exist though
            qq|DELETE FROM dist WHERE file_id IN (SELECT id FROM file WHERE status<>'ok')|,
            qq|DELETE FROM file WHERE status<>'ok'|,
        ],

        upgrade_to_v3 => [
            # empty data, we'll reindex because we'll need to set has_* and
            # discard all info
            'DELETE FROM dist',
            'DELETE FROM module',
            'DELETE FROM file',
            'ALTER TABLE file ADD COLUMN has_metajson INTEGER',
            'ALTER TABLE file ADD COLUMN has_metayml INTEGER',
            'ALTER TABLE file ADD COLUMN has_makefilepl INTEGER',
            'ALTER TABLE file ADD COLUMN has_buildpl INTEGER',
        ],
    }; # spec

    my $res = SQL::Schema::Versioned::create_or_update_db_schema(
        dbh => $dbh, spec => $spec);
    die "Can't create/update schema: $res->[0] - $res->[1]\n"
        unless $res->[0] == 200;
}

sub _connect_db {
    require DBI;

    my $cpan = shift;

    my $db_path = "$cpan/index.db";
    $log->tracef("Connecting to SQLite database at %s ...", $db_path);
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path", undef, undef,
                           {RaiseError=>1});
    _create_schema($dbh);
    $dbh;
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
    summary => 'Update local CPAN mirror files using minicpan command',
    description => <<'_',

This subcommand runs the `minicpan` command to download/update your local CPAN
mirror files.

Note: you can also run `minicpan` yourself.

_
    args => {
        %common_args,
        max_file_size => {
            summary => 'If set, skip downloading files larger than this',
            schema => 'int',
        },
        remote_url => {
            summary => 'Select CPAN mirror to download from',
            schema => 'str*',
        },
    },
};
sub update_local_cpan_files {
    require IPC::System::Options;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $remote_url = $args{remote_url} // "http://mirrors.kernel.org/cpan";
    my $max_file_size = $args{max_file_size};

    local $ENV{PERL5OPT} = "-MLWP::UserAgent::Patch::FilterMirrorMaxSize=-size,".($max_file_size+0).",-verbose,1"
        if defined $max_file_size;

    my @cmd = ("minicpan", "-l", $cpan, "-r", $remote_url);

    IPC::System::Options::system(
        {die=>1, log=>1},
        @cmd,
    );
    [200];
}

sub _check_meta {
    my $meta = shift;

    unless (ref($meta) eq 'HASH') {
        $log->infof("  meta is not a hash");
        return 0;
    }
    unless (defined $meta->{name}) {
        $log->errorf("  meta does not contain name");
        return 0;
    }
    1;
}

$SPEC{'update_local_cpan_index'} = {
    v => 1.1,
    summary => 'Create/update index.db in local CPAN mirror',
    description => <<'_',

This subcommand is called by the `update` subcommand after `update-files` but
can be performed separately via `update-index`. Its task is to create/update
`index.db` SQLite database containing list of authors, modules, dists, and
dependencies.

It gets list of authors from parsing `authors/01mailrc.txt.gz` file.

It gets list of packages from parsing `modules/02packages.details.txt.gz`.
Afterwards, it tries to extract dist metadata `META.yml` or `META.json` from
each release file to get distribution name, abstract, and dependencies
information.

_
    args => {
        %common_args,
    },
};
sub update_local_cpan_index {
    require DBI;
    require File::Slurp::Tiny;
    require File::Temp;
    require IO::Compress::Gzip;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    my $dbh  = _connect_db($cpan);

    # parse 01mailrc.txt.gz and insert the parse result to 'author' table
    {
        my $path = "$cpan/authors/01mailrc.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        # i would like to use INSERT OR IGNORE, but rows affected returned by
        # execute() is always 1?

        my $sth_ins_auth = $dbh->prepare("INSERT INTO author (cpanid,fullname,email) VALUES (?,?,?)");
        my $sth_sel_auth = $dbh->prepare("SELECT cpanid FROM author WHERE cpanid=?");

        $dbh->begin_work;
        my $line = 0;
        while (<$fh>) {
            $line++;
            my ($cpanid, $fullname, $email) = /^alias (\S+)\s+"(.*) <(.+)>"/ or do {
                $log->warnf("  line %d: syntax error, skipped: %s", $line, $_);
                next;
            };

            $sth_sel_auth->execute($cpanid);
            next if $sth_sel_auth->fetchrow_arrayref;
            $sth_ins_auth->execute($cpanid, $fullname, $email);
            $log->tracef("  new author: %s", $cpanid);
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

        my $sth_sel_file = $dbh->prepare("SELECT id FROM file WHERE name=?");
        my $sth_ins_file = $dbh->prepare("INSERT INTO file (name,cpanid) VALUES (?,?)");
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
                $sth_sel_file->execute($file);
                unless ($sth_sel_file->fetchrow_arrayref) {
                    $sth_ins_file->execute($file, $author);
                    $file_id = $dbh->last_insert_id("","","","");
                    $log->tracef("  New file: %s", $file);
                }
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

    # for each new file, try to extract its CPAN META or Makefile.PL/Build.PL
    {
        my $sth = $dbh->prepare("SELECT * FROM file WHERE status IS NULL");
        $sth->execute;
        my @files;
        while (my $row = $sth->fetchrow_hashref) {
            push @files, $row;
        }

        my $sth_set_file_status = $dbh->prepare("UPDATE file SET status=? WHERE id=?");
        my $sth_set_file_status_etc = $dbh->prepare("UPDATE file SET status=?,has_metajson=?,has_metayml=?,has_makefilepl=?,has_buildpl=? WHERE id=?");
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
            my $path = _relpath($file->{name}, $cpan, $cpanid);

            unless (-f $path) {
                $log->errorf("File %s doesn't exist, skipped", $path);
                $sth_set_file_status->execute("nofile", $file->{id});
                next FILE;
            }

            my ($meta, $found_meta);
            my ($has_metajson, $has_metayml, $has_makefilepl, $has_buildpl);
          GET_META:
            {
                unless ($path =~ /(.+)\.(tar|tar\.gz|tar\.bz2|tar\.Z|tgz|tbz2?|zip)$/i) {
                    $log->errorf("Doesn't support file type: %s, skipped", $file->{name});
                    $sth_set_file_status->execute("unsupported", $file->{id});
                    next FILE;
                }

              L1:
                eval {
                    if ($path =~ /\.zip$/i) {
                        require Archive::Zip;
                        my $zip = Archive::Zip->new;
                        $zip->read($path) == Archive::Zip::AZ_OK()
                            or die "Can't read zip file";
                        my @members = $zip->members;
                        $has_metajson   = (grep {m!(?:/|\\)META\.json$!} @members) ? 1:0;
                        $has_metayml    = (grep {m!(?:/|\\)META\.yml$!} @members) ? 1:0;
                        $has_makefilepl = (grep {m!(?:/|\\)Makefile\.PL$!} @members) ? 1:0;
                        $has_buildpl    = (grep {m!(?:/|\\)Build\.PL$!} @members) ? 1:0;

                        for my $member (@members) {
                            if ($member->fileName =~ m!(?:/|\\)(META\.yml|META\.json)$!) {
                                $log->tracef("  found %s", $member->fileName);
                                my $type = $1;
                                #$log->tracef("content=[[%s]]", $content);
                                my $content = $zip->contents($member);
                                if ($type eq 'META.yml') {
                                    $meta = _parse_yaml($content);
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                } elsif ($type eq 'META.json') {
                                    $meta = _parse_json($content);
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                }
                            }
                        }
                    } # if zip
                    else {
                        require Archive::Tar;
                        my $tar = Archive::Tar->new;
                        $tar->read($path);
                        my @members = $tar->list_files;
                        $has_metajson   = (grep {m!/META\.json$!} @members) ? 1:0;
                        $has_metayml    = (grep {m!/META\.yml$!} @members) ? 1:0;
                        $has_makefilepl = (grep {m!/Makefile\.PL$!} @members) ? 1:0;
                        $has_buildpl    = (grep {m!/Build\.PL$!} @members) ? 1:0;

                        for my $member (@members) {
                            if ($member =~ m!/(META\.yml|META\.json)$!) {
                                $log->tracef("  found %s", $member);
                                my $type = $1;
                                my ($obj) = $tar->get_files($member);
                                my $content = $obj->get_content;
                                #$log->trace("[[$content]]");
                                if ($type eq 'META.yml') {
                                    $meta = _parse_yaml($content);
                                    $found_meta++;
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                } elsif ($type eq 'META.json') {
                                    $meta = _parse_json($content);
                                    $found_meta++;
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                }
                            }
                        }
                    } # if tar
                }; # eval

                if ($@) {
                    $log->errorf("Can't extract info from file %s: %s", $path, $@);
                    $sth_set_file_status->execute("err", $file->{id});
                    next FILE;
                }
            } # GET_META

            unless ($meta) {
                if ($found_meta) {
                    $log->infof("File %s doesn't contain valid META.json/META.yml, skipped", $path);
                    $sth_set_file_status_etc->execute(
                        "metaerr",
                        $has_metajson, $has_metajson, $has_makefilepl, $has_buildpl,
                        $file->{id});
                } else {
                    $log->infof("File %s doesn't contain META.json/META.yml, skipped", $path);
                    $sth_set_file_status_etc->execute(
                        "nometa",
                        $has_metajson, $has_metajson, $has_makefilepl, $has_buildpl,
                        $file->{id});
                }
                next FILE;
            }

            my $dist_name = $meta->{name};
            my $dist_abstract = $meta->{abstract};
            my $dist_version = $meta->{version};
            $dist_name =~ s/::/-/g; # sometimes author miswrites module name
            # insert dist record
            $sth_ins_dist->execute($dist_name, $dist_abstract, $file->{id}, $dist_version);
            my $dist_id = $dbh->last_insert_id("","","","");

            # insert dependency information
            if (ref($meta->{configure_requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{configure_requires}, 'configure', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{build_requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{build_requires}, 'build', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{test_requires}) eq 'HASH') {
                _add_prereqs($dist_id, $meta->{test_requires}, 'test', 'requires', $sth_ins_dep, $sth_sel_mod);
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

            $sth_set_file_status_etc->execute(
                "ok",
                $has_metajson, $has_metajson, $has_makefilepl, $has_buildpl,
                $file->{id});
        } # for file
        if ($after_begin) {
            $log->tracef("COMMIT");
            $dbh->commit;
        }
    }

    # there remains some files for which we haven't determine the dist name of
    # (e.g. non-existing file, no info, other error). we determine the dist from
    # the module name.
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
    summary => 'Update local CPAN mirror files, followed by create/update the index.db',
    description => <<'_',

This subcommand calls the `update-files` followed by `update-index`.

_
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
    summary => 'Statistics of your local CPAN mirror',
    args => {
        %common_args,
    },
};
sub stat_local_cpan {
    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $dbh = _connect_db($cpan);

    my $stat = {};

    ($stat->{authors}) = $dbh->selectrow_array("SELECT COUNT(*) FROM author");
    ($stat->{modules}) = $dbh->selectrow_array("SELECT COUNT(*) FROM module");
    ($stat->{releases}) = $dbh->selectrow_array("SELECT COUNT(*) FROM file");
    ($stat->{distributions}) = $dbh->selectrow_array("SELECT COUNT(DISTINCT name) FROM dist");
    (
        $stat->{releases},
        $stat->{releases_have_metajson},
        $stat->{releases_have_metayml},
        $stat->{releases_have_makefilepl},
        $stat->{releases_have_buildpl},
    ) = $dbh->selectrow_array("SELECT
  COUNT(*),
  SUM(CASE has_metajson WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_metayml WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_makefilepl WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_buildpl WHEN 1 THEN 1 ELSE 0 END)
FROM file");

    # XXX last_update_time

    [200, "OK", $stat];
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
    summary => 'List authors',
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
    summary => 'List packages/modules',
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
        push @where, "(name LIKE ? OR abstract LIKE ?)";
        push @bind, $q, $q;
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
  (SELECT abstract FROM dist WHERE dist.file_id=module.file_id) abstract,
  (SELECT cpanid FROM file WHERE id=module.file_id) author
FROM module".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        delete $row->{abstract};
        push @res, $detail ? $row : $row->{name};
    }
    \@res;
}

$SPEC{list_local_cpan_modules} = $SPEC{list_local_cpan_packages};
sub list_local_cpan_modules {
    goto &list_local_cpan_packages;
}

my %author_args = (
    author => {
        summary => 'Filter by author',
        schema => 'str*',
        cmdline_aliases => {a=>{}},
        completion => \&_complete_cpanid,
    },
);

$SPEC{list_local_cpan_dists} = {
    v => 1.1,
    summary => 'List distributions',
    args => {
        %common_args,
        %query_args,
        %author_args,
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
        push @where, "(name LIKE ? OR abstract LIKE ?)";
        push @bind, $q, $q;
    }
    if ($args{author}) {
        #push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @where, "(author=?)";
        push @bind, $args{author};
    }
    my $sql = "SELECT
  name,
  abstract,
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

$SPEC{'list_local_cpan_releases'} = {
    v => 1.1,
    summary => 'List releases/tarballs',
    args => {
        %common_args,
        %author_args,
        %query_args,
        has_metajson   => {schema=>'bool'},
        has_metayml    => {schema=>'bool'},
        has_makefilepl => {schema=>'bool'},
        has_buildpl    => {schema=>'bool'},
    },
    result_naked=>1,
};
sub list_local_cpan_releases {
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
        push @where, "(name LIKE ?)";
        push @bind, $q;
    }
    if ($args{author}) {
        push @where, "(cpanid=?)";
        push @bind, $args{author};
    }
    if (defined $args{has_metajson}) {
        push @where, $args{has_metajson} ? "(has_metajson=1)" : "(has_metajson=0)";
    }
    if (defined $args{has_metayml}) {
        push @where, $args{has_metayml} ? "(has_metayml=1)" : "(has_metayml=0)";
    }
    if (defined $args{has_makefilepl}) {
        push @where, $args{has_makefilepl} ? "(has_makefilepl=1)" : "(has_makefilepl=0)";
    }
    if (defined $args{has_buildpl}) {
        push @where, $args{has_buildpl} ? "(has_buildpl=1)" : "(has_buildpl=0)";
    }
    my $sql = "SELECT
  name,
  cpanid,
  status,
  has_metajson,
  has_metayml,
  has_makefilepl,
  has_buildpl
FROM file".
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

my %mod_args = (
    module => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_mod,
    },
);

$SPEC{'mod2dist'} = {
    v => 1.1,
    summary => 'Get distribution name of a module',
    args => {
        %common_args,
        %mod_args,
    },
    result_naked=>1,
};
sub mod2dist {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $mod = $args{module};

    my $dbh = _connect_db($cpan);

    my ($res) = $dbh->selectrow_array("SELECT dist.name
FROM module
LEFT JOIN file ON module.file_id=file.id
LEFT JOIN dist ON file.id=dist.file_id
WHERE module.name=?", {}, $mod);
        $res;
}

my %full_path_args = (
    full_path => {
        schema => ['bool*' => is=>1],
    },
);

$SPEC{'mod2rel'} = {
    v => 1.1,
    summary => 'Get release name of a module',
    args => {
        %common_args,
        %full_path_args,
    },
    result_naked=>1,
};
sub mod2rel {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $mod = $args{module};

    my $dbh = _connect_db($cpan);

    my $row = $dbh->selectrow_hashref("SELECT
  file.cpanid cpanid,
  file.name name
FROM module
LEFT JOIN file ON module.file_id=file.id
WHERE module.name=?", {}, $mod);
    return undef unless $row;
    if ($args{full_path}) {
        _relcpan($row->{name}, $cpan, $row->{cpanid});
    } else {
        $row->{name};
    }
}

sub _get_prereqs {
    require Module::CoreList;
    require Version::Util;

    my ($mod, $dbh, $memory, $level, $max_level, $phase, $rel, $include_core, $plver) = @_;

    $log->tracef("Finding dependencies for module %s (level=%i) ...", $mod, $level);

    return [404, "No such module: $mod"] unless $dbh->selectrow_arrayref("SELECT id FROM module WHERE name=?", {}, $mod);

    # first find out which distribution that module belongs to
    my $sth = $dbh->prepare("SELECT id FROM dist WHERE file_id=(SELECT file_id FROM module WHERE name=?)");
    $sth->execute($mod);
    my ($dist_id) = $sth->fetchrow_array;
    return [404, "Module '$mod' is not in any dist, index problem?"] unless $dist_id;

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
    my ($mod, $dbh, $filters) = @_;

    $log->tracef("Finding reverse dependencies for module %s ...", $mod);

    # first, check that module is listed
    my ($mod_id) = $dbh->selectrow_array("SELECT id FROM module WHERE name=?", {}, $mod)
        or return [404, "No such module: $mod"];

    my @wheres = ('module_id=?');
    my @binds  = ($mod_id);

    if ($filters->{author}) {
        push @wheres, 'cpanid=?';
        push @binds, $filters->{author};
    }
    if ($filters->{author_isnt}) {
        push @wheres, 'cpanid <> ?';
        push @binds, $filters->{author_isnt};
    }

    # get all dists that depend on that module
    my $sth = $dbh->prepare("SELECT
  (SELECT name    FROM dist WHERE dp.dist_id=dist.id) AS dist,
  (SELECT version FROM dist WHERE dp.dist_id=dist.id) AS dist_version,
  (SELECT cpanid  FROM file WHERE dp.dist_id=(SELECT id FROM dist WHERE file.id=dist.file_id)) AS cpanid,
  -- phase,
  -- rel,
  version req_version
FROM dep dp
WHERE ".join(" AND ", @wheres)."
ORDER BY dist");
    $sth->execute(@binds);
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
    description => <<'_',

By default only runtime requires are displayed. To see prereqs for other phases
(e.g. configure, or build, or ALL) or for other relationships (e.g. recommends,
or ALL), use the `--phase` and `--rel` options.

Note that dependencies information are taken from `META.json` or `META.yml`
files. Not all releases (especially older ones) contain them. `lcpan` (like
MetaCPAN) does not extract information from `Makefile.PL` or `Build.PL` because
that requires running (untrusted) code.

Also, some releases specify dynamic config, so there might actually be more
dependencies.

_
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
    description => <<'_',


_
    args => {
        %common_args,
        %mod_args,
        %author_args,
        author_isnt => {
            summary => 'Filter out certain author',
            schema => 'str*',
            description => <<'_',

This can be used to filter out certain author. For example if you want to know
whether a module is being used by another CPAN author instead of just herself.

_
            completion => \&_complete_cpanid,
        },
    },
};
sub list_local_cpan_rev_deps {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $mod     = $args{module};

    my $dbh     = _connect_db($cpan);

    my $filters = {
        author => $args{author},
        author_isnt => $args{author_isnt},
    };

    _get_revdeps($mod, $dbh, $filters);
}

1;
# ABSTRACT: Manage your local CPAN mirror

=head1 SYNOPSIS

See L<lcpan> script.


=head1 HISTORY

This application began as L<CPAN::SQLite::CPANMeta>, an extension of
L<CPAN::SQLite>. C<CPAN::SQLite> parses C<02packages.details.txt.gz> and
C<01mailrc.txt.gz> and puts the parse result into a SQLite database.
C<CPAN::SQLite::CPANMeta> parses the C<META.json>/C<META.yml> files in
individual release files and adds it to the SQLite database.

In order to simplify things for the users (one-step indexing) and get more
freedom in database schema, C<lcpan> skips using C<CPAN::SQLite> and creates its
own SQLite database. It also parses C<02packages.details.txt.gz> but does not
parse distribution names from it but instead uses C<META.json> and C<META.yml>
files extracted from the release files. If no C<META.*> files exist, then it
will use the module name.

=cut
