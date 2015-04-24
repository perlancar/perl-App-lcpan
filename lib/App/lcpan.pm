package App::lcpan;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Function::Fallback::CoreOrPP qw(clone);
use POSIX ();

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       update
                       modules
                       dists
                       releases
                       authors
                       deps
                       rdeps
               );

our %SPEC;

our %common_args = (
    cpan => {
        schema => 'str*',
        summary => 'Location of your local CPAN mirror, e.g. /path/to/cpan',
        description => <<'_',

Defaults to C<~/cpan>.

_
        tags => ['common'],
    },
    index_name => {
        summary => 'Filename of index',
        schema  => 'str*',
        default => 'index.db',
        tags => ['common'],
        completion => sub {
            my %args = @_;
            my $word    = $args{word} // '';
            my $cmdline = $args{cmdline};
            my $r       = $args{r};

            return undef unless $cmdline;

            # force reading config file
            $r->{read_config} = 1;
            my $res = $cmdline->parse_argv($r);

            my $args = $res->[2];
            _set_args_default($args);

            require Complete::Util;
            Complete::Util::complete_file(
                word => $word,
                starting_path => $args->{cpan},
                filter => sub {
                    # file or index.db*
                    (-d $_[0]) || $_[0] =~ /index\.db/;
                },
            );
        },
    },
);

our %query_args = (
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

our %fauthor_args = (
    author => {
        summary => 'Filter by author',
        schema => 'str*',
        cmdline_aliases => {a=>{}},
        completion => \&_complete_cpanid,
    },
);

our %fdist_args = (
    dist => {
        summary => 'Filter by distribution',
        schema => 'str*',
        cmdline_aliases => {d=>{}},
        completion => \&_complete_dist,
    },
);

our %flatest_args = (
    latest => {
        schema => ['bool*'],
    },
);

our %full_path_args = (
    full_path => {
        schema => ['bool*' => is=>1],
    },
);

our %mod_args = (
    module => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_mod,
    },
);

our %mods_args = (
    modules => {
        schema => ['array*', of=>'str*', min_len=>1],
        'x.name.is_plural' => 1,
        req => 1,
        pos => 0,
        greedy => 1,
        element_completion => \&_complete_mod,
    },
);

our %author_args = (
    author => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_cpanid,
    },
);

our %dist_args = (
    dist => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_dist,
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
    $args->{index_name} //= 'index.db';
    if (!defined($args->{num_backups})) {
        $args->{num_backups} = 7;
    }
}

sub _fmt_time {
    my $epoch = shift;
    return '' unless defined($epoch);
    POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($epoch));
}

sub _numify_ver {
    my $v;
    eval { $v = version->parse($_[0]) };
    $v ? $v->numify : undef;
}

sub _relpath {
    my ($filename, $cpan, $cpanid) = @_;
    $cpanid = uc($cpanid); # just to be safe
    "$cpan/authors/id/".substr($cpanid, 0, 1)."/".
        substr($cpanid, 0, 2)."/$cpanid/$filename";
}

our $db_schema_spec = {
    latest_v => 5,

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
             cpanid VARCHAR(20) NOT NULL REFERENCES author(cpanid), -- [cache]
             file_id INTEGER NOT NULL,
             version VARCHAR(20),
             version_numified DECIMAL
         )',
        'CREATE UNIQUE INDEX ix_module__name ON module(name)',
        'CREATE INDEX ix_module__file_id ON module(file_id)',
        'CREATE INDEX ix_module__cpanid ON module(cpanid)',

        'CREATE TABLE dist (
             id INTEGER NOT NULL PRIMARY KEY,
             name VARCHAR(90) NOT NULL,
             cpanid VARCHAR(20) NOT NULL REFERENCES author(cpanid), -- [cache]
             abstract TEXT,
             file_id INTEGER NOT NULL,
             version VARCHAR(20),
             version_numified DECIMAL,
             is_latest BOOLEAN -- [cache]
         )',
        'CREATE INDEX ix_dist__name ON dist(name)',
        'CREATE UNIQUE INDEX ix_dist__file_id ON dist(file_id)',
        'CREATE INDEX ix_dist__cpanid ON dist(cpanid)',

        'CREATE TABLE dep (
             file_id INTEGER,
             dist_id INTEGER, -- [cache]
             module_id INTEGER, -- if module is known (listed in module table), only its id will be recorded here
             module_name TEXT,  -- if module is unknown (unlisted in module table), only the name will be recorded here
             rel TEXT, -- relationship: requires, ...
             phase TEXT, -- runtime, ...
             version VARCHAR(20),
             version_numified DECIMAL,
             FOREIGN KEY (file_id) REFERENCES file(id),
             FOREIGN KEY (dist_id) REFERENCES dist(id),
             FOREIGN KEY (module_id) REFERENCES module(id)
         )',
        'CREATE INDEX ix_dep__module_name ON dep(module_name)',
        # 'CREATE UNIQUE INDEX ix_dep__file_id__module_id ON dep(file_id,module_id)', # not all module have module_id anyway, and ones with module_id should already be correct because dep is a hash with module name as key
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
        'ALTER TABLE file ADD COLUMN has_metajson   INTEGER',
        'ALTER TABLE file ADD COLUMN has_metayml    INTEGER',
        'ALTER TABLE file ADD COLUMN has_makefilepl INTEGER',
        'ALTER TABLE file ADD COLUMN has_buildpl    INTEGER',
        'ALTER TABLE dist   ADD COLUMN version_numified DECIMAL',
        'ALTER TABLE module ADD COLUMN version_numified DECIMAL',
        'ALTER TABLE dep    ADD COLUMN version_numified DECIMAL',
    ],

    upgrade_to_v4 => [
        # there is some changes to data structure: 1) add column 'cpanid' to
        # module & dist (for improving performance of some queries); 2) we
        # record deps per-file, not per-dist so we can delete old files'
        # data more easily. we also empty data to force reindexing.

        'DELETE FROM dist',
        'DELETE FROM module',
        'DELETE FROM file',

        'ALTER TABLE module ADD COLUMN cpanid VARCHAR(20) NOT NULL DEFAULT \'\' REFERENCES author(cpanid)',
        'CREATE INDEX ix_module__cpanid ON module(cpanid)',
        'ALTER TABLE dist ADD COLUMN cpanid VARCHAR(20) NOT NULL DEFAULT \'\' REFERENCES author(cpanid)',
        'CREATE INDEX ix_dist__cpanid ON dist(cpanid)',

        'DROP TABLE dep',
        'CREATE TABLE dep (
             file_id INTEGER,
             dist_id INTEGER, -- [cache]
             module_id INTEGER, -- if module is known (listed in module table), only its id will be recorded here
             module_name TEXT,  -- if module is unknown (unlisted in module table), only the name will be recorded here
             rel TEXT, -- relationship: requires, ...
             phase TEXT, -- runtime, ...
             version VARCHAR(20),
             version_numified DECIMAL,
             FOREIGN KEY (file_id) REFERENCES file(id),
             FOREIGN KEY (dist_id) REFERENCES dist(id),
             FOREIGN KEY (module_id) REFERENCES module(id)
         )',
        'CREATE INDEX ix_dep__module_name ON dep(module_name)',
    ],

    upgrade_to_v5 => [
        'ALTER TABLE dist ADD COLUMN is_latest BOOLEAN',
    ],

    # for testing
    install_v1 => [
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
    ],
}; # spec

sub _create_schema {
    require SQL::Schema::Versioned;

    my $dbh = shift;

    my $res = SQL::Schema::Versioned::create_or_update_db_schema(
        dbh => $dbh, spec => $db_schema_spec);
    die "Can't create/update schema: $res->[0] - $res->[1]\n"
        unless $res->[0] == 200;
}

sub _db_path {
    my ($cpan, $index_name) = @_;
    "$cpan/$index_name";
}

sub _connect_db {
    require DBI;

    my ($mode, $cpan, $index_name) = @_;

    my $db_path = _db_path($cpan, $index_name);
    $log->tracef("Connecting to SQLite database at %s ...", $db_path);
    if ($mode eq 'ro') {
        # avoid creating the index file automatically if we are only in
        # read-only mode
        die "Can't find index '$db_path'\n" unless -f $db_path;
    }
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
    my ($file_id, $dist_id, $hash, $phase, $rel, $sth_ins_dep, $sth_sel_mod) = @_;
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
        my $ver = $hash->{$mod};
        $sth_ins_dep->execute($file_id, $dist_id, $mod_id, $mod_name, $phase,
                              $rel, $ver, _numify_ver($ver));
    }
}

sub _update_files {
    require IPC::System::Options;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};

    my $remote_url = $args{remote_url} // "http://mirrors.kernel.org/cpan";
    my $max_file_size = $args{max_file_size};

    my @filter_args;
    if ($args{max_file_size}) {
        push @filter_args, "-size", $args{max_file_size};
    }
    if ($args{include_author} && @{ $args{include_author} }) {
        push @filter_args, "-include_author", join(";", @{$args{include_author}});
    }
    if ($args{exclude_author} && @{ $args{exclude_author} }) {
        push @filter_args, "-exclude_author", join(";", @{$args{exclude_author}});
    }
    push @filter_args, "-verbose", 1 if $log->is_info;

    my @cmd = ("minicpan", "-l", $cpan, "-r", $remote_url);
    my $env = {};
    $env->{PERL5OPT} = "-MLWP::UserAgent::Patch::FilterLcpan=".join(",", @filter_args)
        if @filter_args;

    IPC::System::Options::system(
        {die=>1, log=>1, env=>$env},
        @cmd,
    );

    my $dbh = _connect_db('rw', $cpan, $index_name);
    $dbh->do("INSERT OR REPLACE INTO meta (name,value) VALUES (?,?)",
             {}, 'last_mirror_time', time());

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

sub _update_index {
    require DBI;
    require File::Slurp::Tiny;
    require File::Temp;
    require IO::Compress::Gzip;

    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};

    my $db_path = _db_path($cpan, $index_name);
    if ($args{num_backups} > 0 && (-f $db_path)) {
        require File::Copy;
        require Logfile::Rotate;
        $log->infof("Rotating old indexes ...");
        my $rotate = Logfile::Rotate->new(
            File  => $db_path,
            Count => $args{num_backups},
            Gzip  => 'no',
        );
        $rotate->rotate;
        File::Copy::copy("$db_path.1", $db_path)
              or return [500, "Copy $db_path.1 -> $db_path failed: $!"];
    }

    my $dbh  = _connect_db('rw', $cpan, $index_name);

    # check whether we need to reindex if a sufficiently old (and possibly
    # incorrect) version of us did the reindexing
    {
        no strict 'refs';
        last unless defined ${__PACKAGE__.'::VERSION'};

        my ($indexer_version) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='indexer_version'");
        if (!defined($indexer_version) || $indexer_version <= 0.28) {
            $log->infof("Reindexing from scratch, deleting previous index content ...");
            $dbh->do("DELETE FROM dep");
            $dbh->do("DELETE FROM module");
            $dbh->do("DELETE FROM dist");
            $dbh->do("DELETE FROM file");
        }
    }

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

    # these hashes maintain the dist names that are changed so we can refresh
    # the 'is_latest' field later at the end of indexing process
    my %changed_dists;

    # parse 02packages.details.txt.gz and insert the parse result to 'file' and
    # 'module' tables. we haven't parsed distribution names yet because that
    # will need information from META.{json,yaml} inside release files.
    {
        my $path = "$cpan/modules/02packages.details.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        my $sth_sel_file = $dbh->prepare("SELECT id FROM file WHERE name=?");
        my $sth_ins_file = $dbh->prepare("INSERT INTO file (name,cpanid) VALUES (?,?)");
        my $sth_ins_mod  = $dbh->prepare("INSERT INTO module (name,file_id,cpanid,version,version_numified) VALUES (?,?,?,?,?)");
        my $sth_upd_mod  = $dbh->prepare("UPDATE module SET file_id=?,cpanid=?,version=?,version_numified=? WHERE name=?");

        $dbh->begin_work;

        my %file_ids_in_table;
        my $sth = $dbh->prepare("SELECT name,id FROM file");
        while (my ($name, $id) = $sth->fetchrow_array) {
            $file_ids_in_table{$name} = $id;
        }

        my %file_ids_in_02packages; # key=filename, val=id (or undef if already exists in db)
        my $line = 0;
        while (<$fh>) {
            $line++;
            next unless /\S/;
            next if /^\S+:\s/;
            chomp;
            my ($pkg, $ver, $path) = split /\s+/, $_;
            $ver = undef if $ver eq 'undef';
            my ($author, $file) = $path =~ m!^./../(.+?)/(.+)! or do {
                $log->warnf("  line %d: Invalid path %s, skipped", $line, $path);
                next;
            };
            my $file_id;
            if (exists $file_ids_in_02packages{$file}) {
                $file_id = $file_ids_in_02packages{$file};
            } else {
                $sth_sel_file->execute($file);
                unless ($sth_sel_file->fetchrow_arrayref) {
                    $sth_ins_file->execute($file, $author);
                    $file_id = $dbh->last_insert_id("","","","");
                    $log->tracef("  New file: %s", $file);
                }
                $file_ids_in_02packages{$file} = $file_id;
            }
            next unless $file_id;

            if ($dbh->selectrow_array("SELECT id FROM module WHERE name=?", {}, $pkg)) {
                $sth_upd_mod->execute(      $file_id, $author, $ver, _numify_ver($ver), $pkg);
            } else {
                $sth_ins_mod->execute($pkg, $file_id, $author, $ver, _numify_ver($ver));
            }
            $log->tracef("  New/updated module: %s", $pkg);
        } # while <fh>

        # cleanup: delete file record (as well as dists, modules, and deps
        # records) for files in db that are no longer in 02packages.
      CLEANUP:
        {
            my @old_file_ids;
            my @old_filenames;
            for my $fname (sort keys %file_ids_in_table) {
                next if exists $file_ids_in_02packages{$fname};
                push @old_file_ids, $file_ids_in_table{$fname};
                push @old_filenames, $fname;
            }
            last CLEANUP unless @old_file_ids;
            $log->tracef("  Deleting old files: %s", \@old_filenames);
            $dbh->do("DELETE FROM dep WHERE file_id IN (".join(",",@old_file_ids)."))");
            $dbh->do("DELETE FROM module WHERE file_id IN (".join(",",@old_file_ids).")");
            {
                my $sth = $dbh->prepare("SELECT name FROM dist WHERE file_id IN (".join(",",@old_file_ids).")");
                $sth->execute;
                while (my @row = $sth->fetchrow_array) {
                    $changed_dists{$row[0]}++;
                }
                $dbh->do("DELETE FROM dist WHERE file_id IN (".join(",",@old_file_ids).")");
            }
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
        my $sth_ins_dist = $dbh->prepare("INSERT OR REPLACE INTO dist (name,cpanid,abstract,file_id,version,version_numified) VALUES (?,?,?,?,?,?)");
        my $sth_upd_dist = $dbh->prepare("UPDATE dist SET cpanid=?,abstract=?,file_id=?,version=?,version_numified=? WHERE name=?");
        my $sth_ins_dep = $dbh->prepare("INSERT OR REPLACE INTO dep (file_id,dist_id,module_id,module_name,phase,rel, version,version_numified) VALUES (?,?,?,?,?,?, ?,?)");
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
            my $path = _relpath($file->{name}, $cpan, $file->{cpanid});

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
                        $has_metajson, $has_metayml, $has_makefilepl, $has_buildpl,
                        $file->{id});
                } else {
                    $log->infof("File %s doesn't contain META.json/META.yml, skipped", $path);
                    $sth_set_file_status_etc->execute(
                        "nometa",
                        $has_metajson, $has_metayml, $has_makefilepl, $has_buildpl,
                        $file->{id});
                }
                next FILE;
            }

            my $dist_name = $meta->{name};
            my $dist_abstract = $meta->{abstract};
            my $dist_version = $meta->{version};
            $dist_name =~ s/::/-/g; # sometimes author miswrites module name
            # insert dist record
            if ($dbh->selectrow_array("SELECT id FROM dist WHERE name=?", {}, $dist_name)) {
                $sth_upd_dist->execute(            $file->{cpanid}, $dist_abstract, $file->{id}, $dist_version, _numify_ver($dist_version), $dist_name);
            } else {
                $sth_ins_dist->execute($dist_name, $file->{cpanid}, $dist_abstract, $file->{id}, $dist_version, _numify_ver($dist_version));
            }
            my $dist_id = $dbh->last_insert_id("","","","");

            # insert dependency information
            if (ref($meta->{configure_requires}) eq 'HASH') {
                _add_prereqs($file->{id}, $dist_id, $meta->{configure_requires}, 'configure', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{build_requires}) eq 'HASH') {
                _add_prereqs($file->{id}, $dist_id, $meta->{build_requires}, 'build', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{test_requires}) eq 'HASH') {
                _add_prereqs($file->{id}, $dist_id, $meta->{test_requires}, 'test', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{requires}) eq 'HASH') {
                _add_prereqs($file->{id}, $dist_id, $meta->{requires}, 'runtime', 'requires', $sth_ins_dep, $sth_sel_mod);
            }
            if (ref($meta->{prereqs}) eq 'HASH') {
                for my $phase (keys %{ $meta->{prereqs} }) {
                    my $phprereqs = $meta->{prereqs}{$phase};
                    for my $rel (keys %$phprereqs) {
                        _add_prereqs($file->{id}, $dist_id, $phprereqs->{$rel}, $phase, $rel, $sth_ins_dep, $sth_sel_mod);
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
        my $sth = $dbh->prepare("SELECT * FROM file WHERE NOT EXISTS (SELECT id FROM dist WHERE file_id=file.id)");
        my @files;
        $sth->execute;
        while (my $row = $sth->fetchrow_hashref) {
            push @files, $row;
        }

        my $sth_sel_mod = $dbh->prepare("SELECT * FROM module WHERE file_id=? ORDER BY name LIMIT 1");
        my $sth_ins_dist = $dbh->prepare("INSERT INTO dist (name,cpanid,file_id,version,version_numified) VALUES (?,?,?,?,?)");

        $dbh->begin_work;
      FILE:
        for my $file (@files) {
            $sth_sel_mod->execute($file->{id});
            my $row = $sth_sel_mod->fetchrow_hashref or next FILE;
            my $dist_name = $row->{name};
            $dist_name =~ s/::/-/g;
            $log->tracef("Setting dist name for %s as %s", $row->{name}, $dist_name);
            $sth_ins_dist->execute($dist_name, $file->{cpanid}, $file->{id}, $row->{version}, _numify_ver($row->{version}));
        }
        $dbh->commit;
    }

    {
        $log->tracef("Updating is_latest column ...");
        my %dists = %changed_dists;
        my $sth = $dbh->prepare("SELECT DISTINCT(name) FROM dist WHERE is_latest IS NULL");
        $sth->execute;
        while (my @row = $sth->fetchrow_array) {
            $dists{$row[0]}++;
        }
        last unless keys %dists;
        $dbh->do("UPDATE dist SET is_latest=(SELECT CASE WHEN EXISTS(SELECT name FROM dist d WHERE d.name=dist.name AND d.version_numified>dist.version_numified) THEN 0 ELSE 1 END)".
                     " WHERE name IN (".join(", ", map {$dbh->quote($_)} sort keys %dists).")");
    }

    $dbh->do("INSERT OR REPLACE INTO meta (name,value) VALUES (?,?)",
             {}, 'last_index_time', time());
    {
        # record the module version that does the indexing
        no strict 'refs';
        $dbh->do("INSERT OR REPLACE INTO meta (name,value) VALUES (?,?)",
                 {}, 'indexer_version', ${__PACKAGE__.'::VERSION'});
    }

    [200];
}

$SPEC{'update'} = {
    v => 1.1,
    summary => 'Create/update local CPAN mirror',
    description => <<'_',

This subcommand first create/update the mirror files by downloading from a
remote CPAN mirror, then update the index.

_
    args => {
        %common_args,
        max_file_size => {
            summary => 'If set, skip downloading files larger than this',
            schema => 'int',
            tags => ['category:filter'],
        },
        include_author => {
            summary => 'Only include files from certain author(s)',
            'summary.alt.plurality.singular' => 'Only include files from certain author',
            schema => ['array*', of=>['str*', match=>qr/\A[A-Z]{2,9}\z/]],
            tags => ['category:filter'],
        },
        exclude_author => {
            summary => 'Exclude files from certain author(s)',
            'summary.alt.plurality.singular' => 'Exclude files from certain author',
            schema => ['array*', of=>['str*', match=>qr/\A[A-Z]{2,9}\z/]],
            tags => ['category:filter'],
        },
        remote_url => {
            summary => 'Select CPAN mirror to download from',
            schema => 'str*',
        },
        update_files => {
            summary => 'Update the files',
            'summary.alt.bool.not' => 'Skip updating the files',
            schema => 'bool',
            default => 1,
        },
        update_index => {
            summary => 'Update the index',
            'summary.alt.bool.not' => 'Skip updating the index',
            schema => 'bool',
            default => 1,
        },
    },
};
sub update {
    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};

    my $packages_path = "$cpan/modules/02packages.details.txt.gz";
    my @st1 = stat($packages_path);
    if (!$args{update_files}) {
        $log->infof("Skipped updating files (option)");
    } else {
        _update_files(%args);
    }
    my @st2 = stat($packages_path);

    if (!$args{update_index}) {
        $log->infof("Skipped updating index (option)");
    } elsif ($args{update_files} &&
                 @st1 && @st2 && $st1[9] == $st2[9] && $st1[7] == $st2[7]) {
        $log->infof("%s doesn't change mtime/size, skipping updating index",
                $packages_path);
        return [304, "Files did not change, index not updated"];
    } else {
        _update_index(%args);
    }
    [200, "OK"];
}

$SPEC{'stats'} = {
    v => 1.1,
    summary => 'Statistics of your local CPAN mirror',
    args => {
        %common_args,
    },
};
sub stats {
    my %args = @_;
    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $dbh = _connect_db('ro', $cpan, $index_name);

    my $stat = {};

    ($stat->{num_authors}) = $dbh->selectrow_array("SELECT COUNT(*) FROM author");
    ($stat->{num_modules}) = $dbh->selectrow_array("SELECT COUNT(*) FROM module");
    ($stat->{num_dists}) = $dbh->selectrow_array("SELECT COUNT(DISTINCT name) FROM dist");
    (
        $stat->{num_releases},
        $stat->{num_releases_with_metajson},
        $stat->{num_releases_with_metayml},
        $stat->{num_releases_with_makefilepl},
        $stat->{num_releases_with_buildpl},
    ) = $dbh->selectrow_array("SELECT
  COUNT(*),
  SUM(CASE has_metajson WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_metayml WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_makefilepl WHEN 1 THEN 1 ELSE 0 END),
  SUM(CASE has_buildpl WHEN 1 THEN 1 ELSE 0 END)
FROM file");
    ($stat->{schema_version}) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='schema_version'");

    {
        my ($time) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='last_index_time'");
        $stat->{raw_last_index_time} = $time;
        $stat->{last_index_time} = _fmt_time($time);
    }
    {
        my ($ver) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='indexer_version'");
        $stat->{indexer_version} = $ver;
    }
    {
        my @st = stat "$cpan/modules/02packages.details.txt.gz";
        $stat->{mirror_mtime} = _fmt_time(@st ? $st[9] : undef);
        $stat->{raw_mirror_mtime} = $st[9];
    }

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
    eval { $dbh = _connect_db('ro', $res->[2]{cpan}, $res->[2]{index_name}) };

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
    eval { $dbh = _connect_db('ro', $res->[2]{cpan}, $res->[2]{index_name}) };

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
    eval { $dbh = _connect_db('ro', $res->[2]{cpan}, $res->[2]{index_name}) };

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

$SPEC{authors} = {
    v => 1.1,
    summary => 'List authors',
    args => {
        %common_args,
        %query_args,
    },
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
sub authors {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db('ro', $cpan, $index_name);

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
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/id name email/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

$SPEC{modules} = {
    v => 1.1,
    summary => 'List modules/packages',
    args => {
        %common_args,
        %query_args,
        %fauthor_args,
        %fdist_args,
        %flatest_args,
    },
    result => {
        description => <<'_',

By default will return an array of package names. If you set `detail` to true,
will return array of records.

_
    },
};
sub modules {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;
    my $author = uc($args{author} // '');

    my $dbh = _connect_db('ro', $cpan, $index_name);

    my @bind;
    my @where;
    if (length($q)) {
        #push @where, "(name LIKE ? OR dist LIKE ?)"; # rather slow
        push @where, "(name LIKE ? OR abstract LIKE ?)";
        push @bind, $q, $q;
    }
    if ($author) {
        push @where, "(author=?)";
        push @bind, $author;
    }
    if ($args{dist}) {
        #push @where, "(dist_id=(SELECT dist_id FROM dist WHERE dist_name=?))";
        push @where, "(dist=?)";
        push @bind, $args{dist};
    }
    if ($args{latest}) {
        push @where, "(SELECT is_latest FROM dist d WHERE d.file_id=module.file_id)";
    } elsif (defined $args{latest}) {
        push @where, "NOT(SELECT is_latest FROM dist d WHERE d.file_id=module.file_id)";
    }
    my $sql = "SELECT
  name,
  version,
  cpanid author,
  (SELECT name FROM dist WHERE dist.file_id=module.file_id) dist,
  (SELECT abstract FROM dist WHERE dist.file_id=module.file_id) abstract
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
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name author version dist abstract/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

$SPEC{packages} = $SPEC{modules};
sub packages { goto &modules }

$SPEC{dists} = {
    v => 1.1,
    summary => 'List distributions',
    args => {
        %common_args,
        %query_args,
        %fauthor_args,
        %flatest_args,
    },
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
            summary => 'List all distributions (latest version only)',
            argv    => ['--cpan', '/cpan', '--latest'],
            test    => 0,
        },
        {
            summary => 'Grep by distribution name, return detailed record',
            argv    => ['--cpan', '/cpan', 'data-table'],
            test    => 0,
        },
        {
            summary   => 'Filter by author, return JSON',
            src       => '[[prog]] --cpan /cpan --author perlancar --json',
            src_plang => 'bash',
            test      => 0,
        },
    ],
};
sub dists {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $detail = $args{detail};
    my $q = $args{query} // '';
    $q = '%'.$q.'%' unless $q =~ /%/;
    my $author = uc($args{author} // '');

    my $dbh = _connect_db('ro', $cpan, $index_name);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(name LIKE ? OR abstract LIKE ?)";
        push @bind, $q, $q;
    }
    if ($author) {
        push @where, "(author=?)";
        push @bind, $author;
    }
    if ($args{latest}) {
        push @where, "is_latest";
    } elsif (defined $args{latest}) {
        push @where, "NOT(is_latest)";
    }
    my $sql = "SELECT
  name,
  cpanid author,
  version,
  (SELECT name FROM file WHERE id=d1.file_id) file,
  abstract
FROM dist d1".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name author version file abstract/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

$SPEC{'releases'} = {
    v => 1.1,
    summary => 'List releases/tarballs',
    args => {
        %common_args,
        %fauthor_args,
        %query_args,
        has_metajson   => {schema=>'bool'},
        has_metayml    => {schema=>'bool'},
        has_makefilepl => {schema=>'bool'},
        has_buildpl    => {schema=>'bool'},
        %flatest_args,
        %full_path_args,
    },
    description => <<'_',

The status field is the processing status of the file/release by lcpan. `ok`
means file has been extracted and the meta files parsed, `nofile` means file is
not found in mirror (possibly because the mirroring process excludes the file
e.g. due to file size too large), `nometa` means file does not contain
META.{yml,json}, `unsupported` means file archive format is not supported (e.g.
rar), `err` means some other error in processing file.

_
};
sub releases {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;
    my $author = uc($args{author} // '');

    my $dbh = _connect_db('ro', $cpan, $index_name);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(f1.name LIKE ?)";
        push @bind, $q;
    }
    if ($author) {
        push @where, "(f1.cpanid=?)";
        push @bind, $author;
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
    if ($args{latest}) {
        push @where, "d1.is_latest";
    } elsif (defined $args{latest}) {
        push @where, "NOT(d1.is_latest)";
    }
    my $sql = "SELECT
  f1.name name,
  f1.cpanid author,
  has_metajson,
  has_metayml,
  has_makefilepl,
  has_buildpl,
  status
FROM file f1
LEFT JOIN dist d1 ON f1.id=d1.file_id
".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        if ($args{full_path}) { $row->{name} = _relpath($row->{name}, $cpan, $row->{cpanid}) }
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/name author has_metayml has_metajson has_makefilepl has_buildpl status/]]}}
        if $detail;
    [200, "OK", \@res, $resmeta];
}

sub _get_prereqs {
    require Module::CoreList::More;
    require Version::Util;

    my ($mods, $dbh, $memory_by_mod_name, $memory_by_dist_id,
        $level, $max_level, $phase, $rel, $include_core, $plver) = @_;

    $log->tracef("Finding dependencies for module(s) %s (level=%i) ...", $mods, $level);

    # first, check that all modules are listed and belong to a dist
    my @dist_ids;
    for my $mod0 (@$mods) {
        my ($mod, $dist_id);
        if (ref($mod0) eq 'HASH') {
            $mod = $mod0->{mod};
            $dist_id = $mod0->{dist_id};
        } else {
            $mod = $mod0;
            ($dist_id) = $dbh->selectrow_array("SELECT id FROM dist WHERE is_latest AND file_id=(SELECT file_id FROM module WHERE name=?)", {}, $mod)
                or return [404, "No such module: $mod"];
        }
        unless ($memory_by_dist_id->{$dist_id}) {
            push @dist_ids, $dist_id;
            $memory_by_dist_id->{$dist_id} = $mod;
        }
    }
    return [200, "OK", []] unless @dist_ids;

    # fetch the dependency information
    my $sth = $dbh->prepare("SELECT
  dp.dist_id dependant_dist_id,
  (SELECT name   FROM module WHERE id=dp.module_id) AS module,
  (SELECT cpanid FROM module WHERE id=dp.module_id) AS author,
  (SELECT id     FROM dist   WHERE is_latest AND file_id=(SELECT file_id FROM module WHERE id=dp.module_id)) AS module_dist_id,
  phase,
  rel,
  version
FROM dep dp
WHERE dp.dist_id IN (".join(",",@dist_ids).")
ORDER BY module DESC");
    $sth->execute;
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        next unless $row->{module};
        next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        next if exists $memory_by_mod_name->{$row->{module}};

        # some dists, e.g. XML-SimpleObject-LibXML (0.60) have garbled prereqs,
        # e.g. they write PREREQ_PM => { mod1, mod2 } when it should've been
        # PREREQ_PM => {mod1 => 0, mod2=>1.23}. we ignore such deps.
        unless (eval { version->parse($row->{version}); 1 }) {
            $log->info("Invalid version $row->{version} (in dependency to $row->{module}), skipped");
            next;
        }

        #say "include_core=$include_core, is_core($row->{module}, $row->{version}, $plver)=", Module::CoreList::More->is_still_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        next if !$include_core && Module::CoreList::More->is_still_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        next unless defined $row->{module}; # BUG? we can encounter case where module is undef
        if (defined $memory_by_mod_name->{$row->{module}}) {
            if (Version::Util::version_gt($row->{version}, $memory_by_mod_name->{$row->{module}})) {
                $memory_by_mod_name->{$row->{version}} = $row->{version};
            }
            next;
        }
        delete $row->{phase} unless $phase eq 'ALL';
        delete $row->{rel}   unless $rel   eq 'ALL';
        $memory_by_mod_name->{$row->{module}} = $row->{version};
        $row->{level} = $level;
        push @res, $row;
    }

    if (@res && ($max_level==-1 || $level < $max_level)) {
        my $subres = _get_prereqs([map { {mod=>$_->{module}, dist_id=>$_->{module_dist_id}} } @res], $dbh,
                                  $memory_by_mod_name,
                                  $memory_by_dist_id,
                                  $level+1, $max_level, $phase, $rel, $include_core, $plver);
        return $subres if $subres->[0] != 200;
        # insert to res in appropriate places
      SUBRES_TO_INSERT:
        for my $s (@{$subres->[2]}) {
            for my $i (0..@res-1) {
                my $r = $res[$i];
                if ($s->{dependant_dist_id} == $r->{module_dist_id}) {
                    splice @res, $i+1, 0, $s;
                    next SUBRES_TO_INSERT;
                }
            }
            return [500, "Bug? Can't insert subres (module=$s->{module}, dist_id=$s->{module_dist_id})"];
        }
    }

    [200, "OK", \@res];
}

sub _get_revdeps {
    use experimental 'smartmatch';

    my ($mods, $dbh, $memory_by_dist_name, $memory_by_mod_id,
        $level, $max_level, $filters, $phase, $rel) = @_;

    $log->tracef("Finding reverse dependencies for module(s) %s ...", $mods);

    # first, check that all modules are listed
    my @mod_ids;
    for my $mod0 (@$mods) {
        my ($mod, $mod_id) = @_;
        if (ref($mod0) eq 'HASH') {
            $mod = $mod0->{mod};
            $mod_id = $mod0->{mod_id};
        } else {
            $mod = $mod0;
            ($mod_id) = $dbh->selectrow_array("SELECT id FROM module WHERE name=?", {}, $mod)
                or return [404, "No such module: $mod"];
        }
        unless ($memory_by_mod_id->{$mod_id}) {
            push @mod_ids, $mod_id;
            $memory_by_mod_id->{$mod_id} = $mod;
        }
    }
    return [200, "OK", []] unless @mod_ids;

    my @wheres = ('module_id IN ('.join(",", @mod_ids).')');
    my @binds  = ();

    if ($filters->{author}) {
        push @wheres, '('.join(' OR ', ('author=?') x @{$filters->{author}}).')';
        push @binds, ($_) x @{$filters->{author}};
    }
    if ($filters->{author_isnt}) {
        for (@{ $filters->{author_isnt} }) {
            push @wheres, 'author <> ?';
            push @binds, $_;
        }
    }
    push @wheres, "is_latest";

    # get all dists that depend on that module
    my $sth = $dbh->prepare("SELECT
  dp.dist_id dist_id,
  (SELECT is_latest FROM dist WHERE id=dp.dist_id) is_latest,
  (SELECT id FROM dist WHERE is_latest AND file_id=(SELECT file_id FROM module WHERE id=dp.module_id)) module_dist_id,
  (SELECT name    FROM module WHERE dp.module_id=module.id) AS name,
  (SELECT name    FROM dist WHERE dp.dist_id=dist.id)       AS dist,
  (SELECT cpanid  FROM file WHERE dp.file_id=file.id)       AS author,
  (SELECT version FROM dist WHERE dp.dist_id=dist.id)       AS dist_version,
  phase,
  rel,
  version req_version
FROM dep dp
WHERE ".join(" AND ", @wheres)."
ORDER BY dist DESC");
    $sth->execute(@binds);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        next if exists $memory_by_dist_name->{$row->{dist}};
        $memory_by_dist_name->{$row->{dist}} = $row->{dist_version};
        delete $row->{phase} unless $phase eq 'ALL';
        delete $row->{rel} unless $rel eq 'ALL';
        $row->{level} = $level;
        push @res, $row;
    }

    if (@res && ($max_level==-1 || $level < $max_level)) {
        my $sth = $dbh->prepare("SELECT m.id id, m.name name FROM dist d JOIN module m ON d.file_id=m.file_id WHERE d.is_latest AND d.id IN (".join(", ", map {$_->{dist_id}} @res).")");
        $sth->execute();
        my @mods;
        while (my $row = $sth->fetchrow_hashref) {
            push @mods, {mod=>$row->{name}, mod_id=>$row->{id}};
        }
        my $subres = _get_revdeps(\@mods, $dbh,
                                  $memory_by_dist_name, $memory_by_mod_id,
                                  $level+1, $max_level, $filters, $phase, $rel);
        return $subres if $subres->[0] != 200;
        # insert to res in appropriate places
      SUBRES_TO_INSERT:
        for my $s (@{$subres->[2]}) {
            for my $i (0..@res-1) {
                my $r = $res[$i];
                if ($s->{module_dist_id} == $r->{dist_id}) {
                    splice @res, $i+1, 0, $s;
                    next SUBRES_TO_INSERT;
                }
            }
            return [500, "Bug? Can't insert subres (dist=$s->{dist}, dist_id=$s->{dist_id})"];
        }
    }

    [200, "OK", \@res];
}

our %deps_phase_arg = (
    phase => {
        schema => ['str*' => {
            in => [qw/develop configure build runtime test ALL/],
        }],
        default => 'runtime',
        cmdline_aliases => {
            all => {
                summary => 'Equivalent to --phase ALL --rel ALL',
                is_flag => 1,
                code => sub { $_[0]{phase} = 'ALL'; $_[0]{rel} = 'ALL' },
            },
        },
        tags => ['category:filter'],
    },
);

our %rdeps_phase_arg = %{clone(\%deps_phase_arg)};
$rdeps_phase_arg{phase}{default} = 'ALL';

our %deps_rel_arg = (
    rel => {
        schema => ['str*' => {
            in => [qw/requires recommends suggests conflicts ALL/],
        }],
        default => 'requires',
        tags => ['category:filter'],
    },
);

our %rdeps_rel_arg = %{clone(\%deps_rel_arg)};
$rdeps_rel_arg{rel}{default} = 'ALL';

our %deps_args = (
    %deps_phase_arg,
    %deps_rel_arg,
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
        tags => ['category:filter'],
    },
    perl_version => {
        summary => 'Set base Perl version for determining core modules',
        schema  => 'str*',
        default => "$^V",
        cmdline_aliases => {V=>{}},
    },
);

$SPEC{'deps'} = {
    v => 1.1,
    summary => 'List dependencies',
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
        %mods_args,
        %deps_args,
    },
};
sub deps {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $mods    = $args{modules};
    my $phase   = $args{phase} // 'runtime';
    my $rel     = $args{rel} // 'requires';
    my $plver   = $args{perl_version} // "$^V";
    my $level   = $args{level} // 1;
    my $include_core = $args{include_core} // 0;

    my $dbh     = _connect_db('ro', $cpan, $index_name);

    my $res = _get_prereqs($mods, $dbh, {}, {}, 1, $level, $phase, $rel, $include_core, $plver);

    return $res unless $res->[0] == 200;
    for (@{$res->[2]}) {
        $_->{module} = ("  " x ($_->{level}-1)) . $_->{module};
        delete $_->{level};
        delete $_->{dependant_dist_id};
        delete $_->{module_dist_id};
    }

    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/module author version/]]}};
    $res->[3] = $resmeta;
    $res;
}

my %rdeps_args = (
    %common_args,
    %mods_args,
    %rdeps_rel_arg,
    %rdeps_phase_arg,
    level => {
        summary => 'Recurse for a number of levels (-1 means unlimited)',
        schema  => ['int*', min=>1, max=>10],
        default => 1,
        cmdline_aliases => {
            l => {},
            R => {
                summary => 'Recurse (alias for `--level 10`)',
                is_flag => 1,
                code => sub { $_[0]{level} = 10 },
            },
        },
    },
    author => {
        summary => 'Filter certain author',
        schema => ['array*', of=>'str*'],
        description => <<'_',

This can be used to select certain author(s).

_
        completion => \&_complete_cpanid,
        tags => ['category:filter'],
    },
    author_isnt => {
        summary => 'Filter out certain author',
        schema => ['array*', of=>'str*'],
        description => <<'_',

This can be used to filter out certain author(s). For example if you want to
know whether a module is being used by another CPAN author instead of just
herself.

_
        completion => \&_complete_cpanid,
        tags => ['category:filter'],
    },
);

$SPEC{'rdeps'} = {
    v => 1.1,
    summary => 'List reverse dependencies',
    args => {
        %rdeps_args,
    },
};
sub rdeps {
    my %args = @_;

    _set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $mods    = $args{modules};
    my $level   = $args{level} // 1;
    my $author =  $args{author} ? [map {uc} @{$args{author}}] : undef;
    my $author_isnt = $args{author_isnt} ? [map {uc} @{$args{author_isnt}}] : undef;

    my $dbh     = _connect_db('ro', $cpan, $index_name);

    my $filters = {
        author => $author,
        author_isnt => $author_isnt,
    };

    my $res = _get_revdeps($mods, $dbh, {}, {}, 1, $level, $filters, $args{phase}, $args{rel});

    return $res unless $res->[0] == 200;
    for (@{$res->[2]}) {
        $_->{dist} = ("  " x ($_->{level}-1)) . $_->{dist};
        delete $_->{level};
        delete $_->{dist_id};
        delete $_->{module_dist_id};
        delete $_->{name};
        delete $_->{is_latest};
    }

    my $resmeta = {};
    $resmeta->{format_options} = {any=>{table_column_orders=>[[qw/dist author dist_version req_version/]]}};
    $res->[3] = $resmeta;
    $res;
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
