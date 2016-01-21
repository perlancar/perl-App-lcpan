package App::lcpan;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

use Function::Fallback::CoreOrPP qw(clone);

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

            require Complete::File;
            Complete::File::complete_file(
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
        cmdline_aliases => {l=>{}},
    },
);

our %query_multi_args = (
    query => {
        summary => 'Search query',
        schema => ['array*', of=>'str*'],
        cmdline_aliases => {q=>{}},
        pos => 0,
        greedy => 1,
    },
    detail => {
        schema => 'bool',
        cmdline_aliases => {l=>{}},
    },
    or => {
        summary => 'When there are more than one query, perform OR instead of AND logic',
        schema  => ['bool', is=>1],
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

our %sort_modules_args = (
    sort => {
        summary => 'Sort the result',
        schema => ['str*', in=>[map {($_,"-$_")} qw/name author rdeps/]],
        default => 'name',
        tags => ['category:ordering'],
    },
);

our %full_path_args = (
    full_path => {
        schema => ['bool*' => is=>1],
        tags => ['expose-fs-path'],
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

our %rel_args = (
    release => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_rel,
    },
);

our %overwrite_arg = (
    overwrite => {
        summary => 'Whether to overwrite existing file',
        schema => ['bool*', is=>1],
        cmdline_aliases => {o=>{}},
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
    require POSIX;

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

sub _fill_namespace {
    my $dbh = shift;

    my $sth_sel_mod = $dbh->prepare("SELECT name FROM module");
    my $sth_ins_ns  = $dbh->prepare("INSERT INTO namespace (name, num_sep, has_child, num_modules) VALUES (?,?,?,1)");
    my $sth_upd_ns_inc_num_mod = $dbh->prepare("UPDATE namespace SET num_modules=num_modules+1, has_child=1 WHERE name=?");
    $sth_sel_mod->execute;
    my %cache;
    while (my ($mod) = $sth_sel_mod->fetchrow_array) {
        my $has_child = 0;
        while (1) {
            if ($cache{$mod}++) {
                $sth_upd_ns_inc_num_mod->execute($mod);
            } else {
                my $num_sep = 0;
                while ($mod =~ /::/g) { $num_sep++ }
                $sth_ins_ns->execute($mod, $num_sep, $has_child);
            }
            $mod =~ s/::\w+\z// or last;
            $has_child = 1;
        }
    }
}

sub _set_namespace {
    my ($dbh, $mod) = @_;
    my $sth_sel_ns  = $dbh->prepare("SELECT name FROM namespace WHERE name=?");
    my $sth_ins_ns  = $dbh->prepare("INSERT INTO namespace (name, num_sep, has_child, num_modules) VALUES (?,?,?,1)");
    my $sth_upd_ns_inc_num_mod = $dbh->prepare("UPDATE namespace SET num_modules=num_modules+1, has_child=1 WHERE name=?");

    my $has_child = 0;
    while (1) {
        $sth_sel_ns->execute($mod);
        my $row = $sth_sel_ns->fetchrow_arrayref;
        if ($row) {
            $sth_upd_ns_inc_num_mod->execute($mod);
        } else {
            my $num_sep = 0;
            while ($mod =~ /::/g) { $num_sep++ }
            $sth_ins_ns->execute($mod, $num_sep, $has_child);
        }
        $mod =~ s/::\w+\z// or last;
        $has_child = 1;
    }
}

our $db_schema_spec = {
    latest_v => 6,

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

        'CREATE TABLE namespace (
            name VARCHAR(255) NOT NULL,
            num_sep INT NOT NULL,
            has_child BOOL NOT NULL,
            num_modules INT NOT NULL
        )',
        'CREATE UNIQUE INDEX ix_namespace__name ON namespace(name)',

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

    upgrade_to_v6 => [
        'CREATE TABLE namespace (
            name VARCHAR(255) NOT NULL,
            num_sep INT NOT NULL,
            has_child BOOL NOT NULL,
            num_modules INT NOT NULL
        )',
        'CREATE UNIQUE INDEX ix_namespace__name ON namespace(name)',
        \&_fill_namespace,
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

# all subcommands (except special ones like 'update') call this first. lcpan can
# be used in daemon mode or CLI, and this routine handles both case. in daemon
# mode, we set $App::lcpan::state (containing database handle, etc) and reuse
# it. in CLI, there is no reuse between invocation.
sub _init {
    my ($args, $mode) = @_;

    unless ($App::lcpan::state) {
        _set_args_default($args);
        my $state = {
            dbh => _connect_db($mode, $args->{cpan}, $args->{index_name}),
            cpan => $args->{cpan},
            index_name => $args->{index_name},
        };
        $App::lcpan::state = $state;
    }
    $App::lcpan::state;
}

sub _parse_meta_json {
    require Parse::CPAN::Meta;

    my $content = shift;

    my $data;
    eval {
        $data = Parse::CPAN::Meta->load_json_string($content);
    };
    if ($@) {
        $log->errorf("Can't parse META.json: %s", $@);
        return undef;
    } else {
        return $data;
    }
}

sub _parse_meta_yml {
    require Parse::CPAN::Meta;

    my $content = shift;

    my $data;
    eval {
        $data = Parse::CPAN::Meta->load_yaml_string($content);
    };
    if ($@) {
        $log->errorf("Can't parse META.yml: %s", $@);
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
        my $our_version = ${__PACKAGE__.'::VERSION'};

        my ($indexer_version) = $dbh->selectrow_array("SELECT value FROM meta WHERE name='indexer_version'");
        last unless $indexer_version;
        if ($our_version && version->parse($indexer_version) > version->parse($our_version)) {
            return [412, "Database is indexed by version ($indexer_version) newer than current software's version ($our_version), bailing out"];
        }
        if (version->parse($indexer_version) <= version->parse("0.35")) {
            $log->infof("Reindexing from scratch, deleting previous index content ...");
            _reset($dbh);
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
        my $sth_upd_mod  = $dbh->prepare("UPDATE module SET file_id=?,cpanid=?,version=?,version_numified=? WHERE name=?"); # sqlite currently does not have upsert

        $dbh->begin_work;

        my %file_ids_in_table;
        my $sth = $dbh->prepare("SELECT name,id FROM file");
        $sth->execute;
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
                _set_namespace($dbh, $pkg);
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
            $log->tracef("  Deleting old dep records");
            $dbh->do("DELETE FROM dep WHERE file_id IN (".join(",",@old_file_ids).")");
            {
                my $sth = $dbh->prepare("SELECT name FROM module WHERE file_id IN (".join(",",@old_file_ids).")");
                $sth->execute;
                my @mods;
                while (my ($mod) = $sth->fetchrow_array) {
                    push @mods, $mod;
                }

                my $sth_upd_ns_dec_num_mod = $dbh->prepare("UPDATE namespace SET num_modules=num_modules-1 WHERE name=?");
                for my $mod (@mods) {
                    while (1) {
                        $sth_upd_ns_dec_num_mod->execute($mod);
                        $mod =~ s/::\w+\z// or last;
                    }
                }
                $dbh->do("DELETE FROM namespace WHERE num_modules <= 0");

                $log->tracef("  Deleting old module records");
                $dbh->do("DELETE FROM module WHERE file_id IN (".join(",",@old_file_ids).")");
            }
            {
                my $sth = $dbh->prepare("SELECT name FROM dist WHERE file_id IN (".join(",",@old_file_ids).")");
                $sth->execute;
                while (my @row = $sth->fetchrow_array) {
                    $changed_dists{$row[0]}++;
                }
                $log->tracef("  Deleting old dist records");
                $dbh->do("DELETE FROM dist WHERE file_id IN (".join(",",@old_file_ids).")");
            }
            $log->tracef("  Deleting old file records (%d): %s", ~~@old_filenames, \@old_filenames);
            $dbh->do("DELETE FROM file WHERE id IN (".join(",",@old_file_ids).")");
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
        my $sth_upd_dist = $dbh->prepare("UPDATE dist SET cpanid=?,abstract=?,file_id=?,version=?,version_numified=? WHERE id=?");
        my $sth_ins_dep = $dbh->prepare("INSERT OR REPLACE INTO dep (file_id,dist_id,module_id,module_name,phase,rel, version,version_numified) VALUES (?,?,?,?,?,?, ?,?)");
        my $sth_sel_mod  = $dbh->prepare("SELECT * FROM module WHERE name=?");

        my $i = 0;
        my $after_begin;

      FILE:
        for my $file (@files) {
            if ($args{skip_index_files} && grep {$_ eq $file->{name}} @{ $args{skip_index_files} }) {
                $log->infof("Skipped file %s (skip_index_files)", $file->{name});
                next FILE;
            }

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

            $log->infof("[#%i] Processing file %s ...", $i, $file->{name});
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
                        $has_metajson   = (grep {m!^[/\\]?(?:[^/\\]+[/\\])?META\.json$!} @members) ? 1:0;
                        $has_metayml    = (grep {m!^[/\\]?(?:[^/\\]+[/\\])?META\.yml$!} @members) ? 1:0;
                        $has_makefilepl = (grep {m!^[/\\]?(?:[^/\\]+[/\\])?Makefile\.PL$!} @members) ? 1:0;
                        $has_buildpl    = (grep {m!^[/\\]?(?:[^/\\]+[/\\])?Build\.PL$!} @members) ? 1:0;

                        for my $member (@members) {
                            if ($member->fileName =~ m!(?:/|\\)(META\.yml|META\.json)$!) {
                                $log->tracef("  found %s", $member->fileName);
                                my $type = $1;
                                #$log->tracef("content=[[%s]]", $content);
                                my $content = $zip->contents($member);
                                if ($type eq 'META.yml') {
                                    $meta = _parse_meta_yml($content);
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                } elsif ($type eq 'META.json') {
                                    $meta = _parse_meta_json($content);
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
                        $has_metajson   = (grep {m!/([^/]+)?META\.json$!} @members) ? 1:0;
                        $has_metayml    = (grep {m!/([^/]+)?META\.yml$!} @members) ? 1:0;
                        $has_makefilepl = (grep {m!/([^/]+)?Makefile\.PL$!} @members) ? 1:0;
                        $has_buildpl    = (grep {m!/([^/]+)?Build\.PL$!} @members) ? 1:0;

                        for my $member (@members) {
                            if ($member =~ m!/(META\.yml|META\.json)$!) {
                                $log->tracef("  found %s", $member);
                                my $type = $1;
                                my ($obj) = $tar->get_files($member);
                                my $content = $obj->get_content;
                                #$log->trace("[[$content]]");
                                if ($type eq 'META.yml') {
                                    $meta = _parse_meta_yml($content);
                                    $found_meta++;
                                    if (_check_meta($meta)) { return } else { undef $meta } # from eval
                                } elsif ($type eq 'META.json') {
                                    $meta = _parse_meta_json($content);
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
            my $dist_id;
            if (($dist_id) = $dbh->selectrow_array("SELECT id FROM dist WHERE name=?", {}, $dist_name)) {
                $sth_upd_dist->execute(            $file->{cpanid}, $dist_abstract, $file->{id}, $dist_version, _numify_ver($dist_version), $dist_id);
            } else {
                $sth_ins_dist->execute($dist_name, $file->{cpanid}, $dist_abstract, $file->{id}, $dist_version, _numify_ver($dist_version));
                $dist_id = $dbh->last_insert_id("","","","");
            }

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
    args_rels => {
        # it should be: update_index=0 conflicts with force_update_index
        #choose_one => [qw/update_index force_update_index/],
    },
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
        force_update_index => {
            summary => 'Update the index even though there is no change in files',
            schema => ['bool', is=>1],
        },
        skip_index_files => {
            summary => 'Skip one or more files from being indexed',
            'x.name.is_plural' => 1,
            'summary.alt.plurality.singular' => 'Skip a file from being indexed',
            schema => ['array*', of=>'str*'],
            cmdline_aliases => {
                F => {
                    summary => 'Alias for --skip-index-file',
                    code => sub {
                        $_[0]{skip_index_files} //= [];
                        push @{ $_[0]{skip_index_files} }, $_[1];
                    },
                },
            },
        },
    },
    tags => ['write-to-db', 'write-to-fs'],
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
        _update_files(%args); # it only returns 200 or dies
    }
    my @st2 = stat($packages_path);

    if (!$args{update_index} && !$args{force_update_index}) {
        $log->infof("Skipped updating index (option)");
    } elsif (!$args{force_update_index} && $args{update_files} &&
                 @st1 && @st2 && $st1[9] == $st2[9] && $st1[7] == $st2[7]) {
        $log->infof("%s doesn't change mtime/size, skipping updating index",
                    $packages_path);
        return [304, "Files did not change, index not updated"];
    } else {
        my $res = _update_index(%args);
        return $res unless $res->[0] == 200;
    }
    [200, "OK"];
}

sub _reset {
    my $dbh = shift;
    $dbh->do("DELETE FROM dep");
    $dbh->do("DELETE FROM namespace");
    $dbh->do("DELETE FROM module");
    $dbh->do("DELETE FROM dist");
    $dbh->do("DELETE FROM file");
    $dbh->do("DELETE FROM author");
}

$SPEC{'reset'} = {
    v => 1.1,
    summary => 'Reset (empty) the database index',
    args => {
        %common_args,
    },
    tags => ['write-to-db'],
};
sub reset {
    require IO::Prompt::I18N;

    my %args = @_;

    my $state = _init(\%args, 'rw');
    my $dbh = $state->{dbh};

    return [200, "Cancelled"]
        unless IO::Prompt::I18N::confirm("Confirm reset index", {default=>0});

    _reset($dbh);
    [200, "Reset"];
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

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $stat = {};

    ($stat->{num_authors}) = $dbh->selectrow_array("SELECT COUNT(*) FROM author");
    ($stat->{num_authors_with_releases}) = $dbh->selectrow_array("SELECT COUNT(DISTINCT cpanid) FROM file");
    ($stat->{num_modules}) = $dbh->selectrow_array("SELECT COUNT(*) FROM module");
    ($stat->{num_namespaces}) = $dbh->selectrow_array("SELECT COUNT(*) FROM namespace");
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
        my @st = stat "$state->{cpan}/modules/02packages.details.txt.gz";
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

    # XXX follow Complete::Common::OPT_CI

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

sub _complete_ns {
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
        "SELECT name FROM namespace WHERE name LIKE ? ORDER BY name");
    $sth->execute($word . '%');

    # XXX follow Complete::Common::OPT_CI

    my @res;
    while (my ($ns) = $sth->fetchrow_array) {
        # only complete one level deeper at a time
        if ($ns =~ /:\z/) {
            next unless $ns =~ /\A\Q$word\E:*\w+\z/i;
        } else {
            next unless $ns =~ /\A\Q$word\E\w*(::\w+)?\z/i;
        }
        push @res, $ns;
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

    # XXX follow Complete::Common::OPT_CI

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

    # XXX follow Complete::Common::OPT_CI

    my @res;
    while (my ($cpanid) = $sth->fetchrow_array) {
        push @res, $cpanid;
    }

    \@res;
};

sub _complete_rel {
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
        "SELECT name FROM file WHERE name LIKE ? ORDER BY name");
    $sth->execute($word . '%');

    # XXX follow Complete::Common::OPT_CI

    my @res;
    while (my ($rel) = $sth->fetchrow_array) { #
        push @res, $rel;
    }

    \@res;
};

$SPEC{authors} = {
    v => 1.1,
    summary => 'List authors',
    args => {
        %common_args,
        %query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any cpanid exact-cpanid fullname email exact-email/]],
            default => 'any',
        },
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
            'x.doc.show_result' => 0,
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

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any') {
                my $q = uc($q0 =~ /%/ ? $q0 : '%'.$q0.'%');
                push @q_where, "(cpanid LIKE ? OR fullname LIKE ? OR email like ?)";
                push @bind, $q, $q, $q;
            } elsif ($qt eq 'cpanid') {
                my $q = uc($q0 =~ /%/ ? $q0 : '%'.$q0.'%');
                push @q_where, "(cpanid LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-cpanid') {
                push @q_where, "(cpanid=?)";
                push @bind, uc($q0);
            } elsif ($qt eq 'fullname') {
                my $q = uc($q0 =~ /%/ ? $q0 : '%'.$q0.'%');
                push @q_where, "(fullname LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'email') {
                my $q = uc($q0 =~ /%/ ? $q0 : '%'.$q0.'%');
                push @q_where, "(email LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-email') {
                push @q_where, "(LOWER(email)=?)";
                push @bind, lc($q0);
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
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
    $resmeta->{'table.fields'} = [qw/id name email/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

$SPEC{modules} = {
    v => 1.1,
    summary => 'List modules/packages',
    args => {
        %common_args,
        %query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name abstract/]],
            default => 'any',
        },
        %fauthor_args,
        %fdist_args,
        %flatest_args,
        namespaces => {
            'x.name.is_plural' => 1,
            summary => 'Select modules belonging to certain namespace(s)',
            schema => ['array*', of=>'str*'],
            tags => ['category:filtering'],
            element_completion => \&_complete_ns,
        },
        %sort_modules_args,
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

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $author = uc($args{author} // '');
    my $qt = $args{query_type} // 'any';

    my $order = do {
        my $sort = $args{sort} // '';
        my $is_desc = $sort =~ s/^-//;
        my $order;
        if ($sort eq 'author') { $order = 'author' }
        elsif ($sort eq 'rdeps') { $order = 'rdeps' }
        else { $order = 'name' }
        $order .= " DESC" if $is_desc;
        $order;
    };

    my @cols = (
        'name',
        ['cpanid', 'author'],
        'version',
        ['(SELECT name FROM dist WHERE dist.file_id=module.file_id)', 'dist'],
        ['(SELECT abstract FROM dist WHERE dist.file_id=module.file_id)', 'abstract', 1], # only used for searching
    );

    if ($order =~ /rdeps/) {
        push @cols, (
            ['(SELECT COUNT(DISTINCT dist_id) FROM dep WHERE module_id=module.id)', 'rdeps'],
        );
    }

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            #push @q_where, "(name LIKE ? OR dist LIKE ?)"; # rather slow
            if ($qt eq 'any') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(name LIKE ? OR abstract LIKE ?)";
                push @bind, $q, $q;
            } elsif ($qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(name=?)";
                push @bind, $q0;
            } elsif ($qt eq 'abstract') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(abstract LIKE ?)";
                push @bind, $q;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
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
    if ($args{namespaces} && @{ $args{namespaces} }) {
        my @ns_where;
        for my $ns (@{ $args{namespaces} }) {
            return [400, "Invalid namespace '$ns', please use Word or Word(::Sub)+"]
                unless $ns =~ /\A\w+(::\w+)*\z/;
            push @ns_where, "(name='$ns' OR name LIKE '$ns\::%')";
        }
        push @where, "(".join(" OR ", @ns_where).")";
    }
    if ($args{latest}) {
        push @where, "(SELECT is_latest FROM dist d WHERE d.file_id=module.file_id)";
    } elsif (defined $args{latest}) {
        push @where, "NOT(SELECT is_latest FROM dist d WHERE d.file_id=module.file_id)";
    }
    my $sql = "SELECT ".join(", ", map {ref($_) ? "$_->[0] AS $_->[1]" : $_} @cols).
        " FROM module".
        (@where ? " WHERE ".join(" AND ", @where) : "").
        " ORDER BY ".$order;

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        delete $row->{abstract};
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [map {ref($_) ? $_->[1] : $_} grep {!ref($_) || !$_->[2]} @cols]
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
        %query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name abstract/]],
            default => 'any',
        },
        %fauthor_args,
        %flatest_args,
        has_makefilepl => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
        has_buildpl => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
        has_metayml => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
        has_metajson => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
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
            'x.doc.show_result' => 0,
        },
        {
            summary => 'List all distributions (latest version only)',
            argv    => ['--cpan', '/cpan', '--latest'],
            test    => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Grep by distribution name, return detailed record',
            argv    => ['--cpan', '/cpan', 'data-table'],
            test    => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary   => 'Filter by author, return JSON',
            src       => '[[prog]] --cpan /cpan --author perlancar --json',
            src_plang => 'bash',
            test      => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub dists {
    my %args = @_;

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $author = uc($args{author} // '');
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(d.name LIKE ? OR abstract LIKE ?)";
                push @bind, $q, $q;
            } elsif ($qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(d.name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(d.name=?)";
                push @bind, $q0;
            } elsif ($qt eq 'abstract') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(abstract LIKE ?)";
                push @bind, $q;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
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
    if (defined $args{has_makefilepl}) {
        if ($args{has_makefilepl}) {
            push @where, "has_makefilepl<>0";
        } else {
            push @where, "has_makefilepl=0";
        }
    }
    if (defined $args{has_buildpl}) {
        if ($args{has_buildpl}) {
            push @where, "has_buildpl<>0";
        } else {
            push @where, "has_buildpl=0";
        }
    }
    if (defined $args{has_metayml}) {
        if ($args{has_metayml}) {
            push @where, "has_metayml<>0";
        } else {
            push @where, "has_metayml=0";
        }
    }
    if (defined $args{has_metajson}) {
        if ($args{has_metajson}) {
            push @where, "has_metajson<>0";
        } else {
            push @where, "has_metajson=0";
        }
    }
    my $sql = "SELECT
  d.name name,
  d.cpanid author,
  version,
  f.name file,
  abstract
FROM dist d
LEFT JOIN file f ON d.file_id=f.id
".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY d.name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name author version file abstract/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

$SPEC{'releases'} = {
    v => 1.1,
    summary => 'List releases/tarballs',
    args => {
        %common_args,
        %fauthor_args,
        %query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name/]],
            default => 'any',
        },
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

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $author = uc($args{author} // '');
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any' || $qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(f1.name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(f1.name=?)";
                push @bind, $q0;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
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
        push @where, "d.is_latest";
    } elsif (defined $args{latest}) {
        push @where, "NOT(d.is_latest)";
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
LEFT JOIN dist d ON f1.id=d.file_id
".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        if ($args{full_path}) { $row->{name} = _relpath($row->{name}, $state->{cpan}, $row->{author}) }
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name author has_metayml has_metajson has_makefilepl has_buildpl status/]
        if $detail;
    [200, "OK", \@res, $resmeta];
}

sub _get_prereqs {
    require Module::CoreList::More;
    require Version::Util;

    my ($mods, $dbh, $memory_by_mod_name, $memory_by_dist_id,
        $level, $max_level, $phase, $rel, $include_core, $plver, $flatten) = @_;

    $log->tracef("Finding dependencies for module(s) %s (level=%i) ...", $mods, $level);

    # first, check that all modules are listed and belong to a dist
    my @dist_ids;
    for my $mod0 (@$mods) {
        my ($mod, $dist_id);
        if (ref($mod0) eq 'HASH') {
            $mod = $mod0->{mod};
            $dist_id = $mod0->{dist_id};
            if (!$dist_id) {
                warn "module '$mod' does not have dist ID";
                next;
            }
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
  (SELECT name   FROM dist   WHERE id=dp.dist_id) AS dist,
  (SELECT name   FROM module WHERE id=dp.module_id) AS module,
  (SELECT cpanid FROM module WHERE id=dp.module_id) AS author,
  (SELECT id     FROM dist   WHERE is_latest AND file_id=(SELECT file_id FROM module WHERE id=dp.module_id)) AS module_dist_id,
  phase,
  rel,
  version
FROM dep dp
WHERE dp.dist_id IN (".join(",",grep {defined} @dist_ids).")
ORDER BY module".($level > 1 ? " DESC" : ""));
    $sth->execute;
    my @res;
  MOD:
    while (my $row = $sth->fetchrow_hashref) {
        next unless $row->{module};
        next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;

        # some dists, e.g. XML-SimpleObject-LibXML (0.60) have garbled prereqs,
        # e.g. they write PREREQ_PM => { mod1, mod2 } when it should've been
        # PREREQ_PM => {mod1 => 0, mod2=>1.23}. we ignore such deps.
        unless (eval { version->parse($row->{version}); 1 }) {
            $log->info("Invalid version $row->{version} (in dependency to $row->{module}), skipped");
            next;
        }

        if (exists $memory_by_mod_name->{$row->{module}}) {
            if ($flatten) {
                $memory_by_mod_name->{$row->{module}} = $row->{version}
                    if version->parse($row->{version}) > version->parse($memory_by_mod_name->{$row->{module}});
            } else {
                next MOD;
            }
        }

        $row->{is_core} = Module::CoreList::More->is_still_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        next if !$include_core && $row->{is_core};
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
                                  $level+1, $max_level, $phase, $rel, $include_core, $plver, $flatten);
        return $subres if $subres->[0] != 200;
        if ($flatten) {
            my %deps; # key = module name
            for my $s (@{$subres->[2]}, @res) {
                $s->{version} = $memory_by_mod_name->{$s->{module}};
                $deps{ $s->{module} } = $s;
            }
            @res = map {$deps{$_}} sort keys %deps;
        } else {
            # insert to res in appropriate places
          SUBRES_TO_INSERT:
            for my $s (@{$subres->[2]}) {
                for my $i (0..@res-1) {
                    my $r = $res[$i];
                    if (defined($s->{dependant_dist_id}) && defined($r->{module_dist_id}) &&
                            $s->{dependant_dist_id} == $r->{module_dist_id}) {
                        splice @res, $i+1, 0, $s;
                        next SUBRES_TO_INSERT;
                    }
                }
                return [500, "Bug? Can't insert subres (module=$s->{module}, dist_id=$s->{module_dist_id})"];
            }
        }
    }

    [200, "OK", \@res];
}

sub _get_revdeps {
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
  (SELECT name    FROM module WHERE dp.module_id=module.id) AS module,
  (SELECT name    FROM dist WHERE dp.dist_id=dist.id)       AS dist,
  (SELECT cpanid  FROM file WHERE dp.file_id=file.id)       AS author,
  (SELECT version FROM dist WHERE dp.dist_id=dist.id)       AS dist_version,
  phase,
  rel,
  version req_version
FROM dep dp
WHERE ".join(" AND ", @wheres)."
ORDER BY dist".($level > 1 ? " DESC" : ""));
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
            for my $i (reverse 0..@res-1) {
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
    flatten => {
        summary => 'Instead of showing tree-like information, flatten it',
        schema => 'bool',
        description => <<'_',

When recursing, the default is to show the final result in a tree-like table,
i.e. indented according to levels, e.g.:

    % lcpan deps -R MyModule
    | module            | author  | version |
    |-------------------|---------|---------|
    | Foo               | AUTHOR1 | 0.01    |
    |   Bar             | AUTHOR2 | 0.23    |
    |   Baz             | AUTHOR3 | 1.15    |
    | Qux               | AUTHOR2 | 0       |

To be brief, if `Qux` happens to also depends on `Bar`, it will not be shown in
the result. Thus we don't know the actual `Bar` version that is needed by the
dependency tree of `MyModule`. For example, if `Qux` happens to depends on `Bar`
version 0.45 then `MyModule` indirectly requires `Bar` 0.45.

To list all the direct and indirect dependencies on a single flat list, with
versions already resolved to the largest version required, use the `flatten`
option:

    % lcpan deps -R --flatten MyModule
    | module            | author  | version |
    |-------------------|---------|---------|
    | Foo               | AUTHOR1 | 0.01    |
    | Bar               | AUTHOR2 | 0.45    |
    | Baz               | AUTHOR3 | 1.15    |
    | Qux               | AUTHOR2 | 0       |

Note that `Bar`'s required version is already 0.45 in the above example.

_
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
    with_xs_or_pp => {
        summary => 'Check each dependency as XS/PP',
        schema  => ['bool*', is=>1],
        tags => ['category:filter'],
    },
);

our $deps_args_rels = {
    dep_any => [flatten => ['level']],
};

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
    args_rels => $deps_args_rels,
};
sub deps {
    require Module::XSOrPP;
    my %args = @_;

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $mods    = $args{modules};
    my $phase   = $args{phase} // 'runtime';
    my $rel     = $args{rel} // 'requires';
    my $plver   = $args{perl_version} // "$^V";
    my $level   = $args{level} // 1;
    my $include_core = $args{include_core} // 0;
    my $with_xs_or_pp = $args{with_xs_or_pp};

    my $res = _get_prereqs($mods, $dbh, {}, {}, 1, $level, $phase, $rel,
                           $include_core, $plver, $args{flatten});

    return $res unless $res->[0] == 200;
    my @cols;
    push @cols, (qw/module/);
    push @cols, "dist" if @$mods > 1;
    push @cols, (qw/author version/);
    push @cols, "is_core" if $include_core;
    push @cols, "xs_or_pp" if $with_xs_or_pp;
    for (@{$res->[2]}) {
        if ($with_xs_or_pp) {
            $_->{xs_or_pp} = Module::XSOrPP::xs_or_pp($_->{module});
        }
        $_->{module} = ("  " x ($_->{level}-1)) . $_->{module}
            unless $args{flatten};
        delete $_->{level};
        delete $_->{dist} unless @$mods > 1;
        delete $_->{dependant_dist_id};
        delete $_->{module_dist_id};
        delete $_->{is_core} unless $include_core;
    }

    my $resmeta = {};
    $resmeta->{'table.fields'} = \@cols;
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

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $mods    = $args{modules};
    my $level   = $args{level} // 1;
    my $author =  $args{author} ? [map {uc} @{$args{author}}] : undef;
    my $author_isnt = $args{author_isnt} ? [map {uc} @{$args{author_isnt}}] : undef;

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
        delete $_->{module} unless @$mods > 1;
        delete $_->{is_latest};
    }

    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/module dist author dist_version req_version/];
    $res->[3] = $resmeta;
    $res;
}

$SPEC{namespaces} = {
    v => 1.1,
    summary => 'List namespaces',
    args => {
        %common_args,
        %query_multi_args,
        query_type => {
            schema => ['str*', in=>[qw/any name exact-name/]],
            default => 'any',
        },
        from_level => {
            schema => ['int*', min=>0],
            tags => ['category:filtering'],
        },
        to_level => {
            schema => ['int*', min=>0],
            tags => ['category:filtering'],
        },
        level => {
            schema => ['int*', min=>0],
            tags => ['category:filtering'],
        },
        sort => {
            schema => ['str*', in=>[qw/name -name num_modules -num_modules/]],
            default => 'name',
            tags => ['category:sorting'],
        },
    },
};
sub namespaces {
    my %args = @_;

    my $state = _init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $detail = $args{detail};
    my $qt = $args{query_type} // 'any';

    my @bind;
    my @where;
    {
        my @q_where;
        for my $q0 (@{ $args{query} // [] }) {
            if ($qt eq 'any' || $qt eq 'name') {
                my $q = $q0 =~ /%/ ? $q0 : '%'.$q0.'%';
                push @q_where, "(name LIKE ?)";
                push @bind, $q;
            } elsif ($qt eq 'exact-name') {
                push @q_where, "(name=?)";
                push @bind, $q0;
            }
        }
        if (@q_where > 1) {
            push @where, "(".join(($args{or} ? " OR " : " AND "), @q_where).")";
        } elsif (@q_where == 1) {
            push @where, @q_where;
        }
    }
    if (defined $args{from_level}) {
        push @where, "(num_sep >= ?)";
        push @bind, $args{from_level}-1;
    }
    if (defined $args{to_level}) {
        push @where, "(num_sep <= ?)";
        push @bind, $args{to_level}-1;
    }
    if (defined $args{level}) {
        push @where, "(num_sep = ?)";
        push @bind, $args{level}-1;
    }
    my $order = 'name';
    if ($args{sort} eq 'num_modules') {
        $order = "num_modules";
    } elsif ($args{sort} eq '-num_modules') {
        $order = "num_modules DESC";
    }
    my $sql = "SELECT
  name,
  num_modules
FROM namespace".
    (@where ? " WHERE ".join(" AND ", @where) : "")."
ORDER BY $order";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    my $resmeta = {};
    $resmeta->{'table.fields'} = [qw/name num_modules/]
        if $detail;
    [200, "OK", \@res, $resmeta];
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
