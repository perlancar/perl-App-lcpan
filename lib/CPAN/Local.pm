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
               );

our %SPEC;

my %common_args = (
    cpan => {
        schema => 'str*',
        req => 1,
        summary => 'Location of your local CPAN mirror, e.g. /path/to/cpan',
    },
);

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Index CPAN Meta information in CPAN::SQLite database',
};

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
            # some differences with CPAN::SQLite's version:
            # - column sizes are expanded
            # - some indexes are converted to unique index
            # - remove chapter table/columns
            # - dists: add index on dist_file
            'CREATE TABLE mods (
                 mod_id INTEGER NOT NULL PRIMARY KEY,
                 mod_name VARCHAR(255) NOT NULL,
                 dist_id INTEGER NOT NULL,
                 mod_abs TEXT,
                 mod_vers VARCHAR(20),
                 dslip VARCHAR(5)
                 -- chapterid INTEGER
             )',
            'CREATE INDEX ix_mods_dist_id ON mods(dist_id)',
            'CREATE UNIQUE INDEX ix_mods_mod_name ON mods(dist_id)',

            'CREATE TABLE dists (
                 dist_id INTEGER NOT NULL PRIMARY KEY,
                 dist_name VARCHAR(90) NOT NULL,
                 auth_id INTEGER NOT NULL,
                 dist_file VARCHAR(255) NOT NULL,
                 dist_vers VARCHAR(20),
                 dist_abs TEXT,
                 dist_dslip VARCHAR(5)
             )',
            'CREATE INDEX ix_dists_auth_id ON dists(auth_id)',
            'CREATE UNIQUE INDEX ix_dists_dist_name ON dists(dist_name)',
            'CREATE UNIQUE INDEX ix_dists_dist_file ON dists(dist_file)',

            'CREATE TABLE auths (
                 auth_id INTEGER NOT NULL PRIMARY KEY,
                 cpanid VARCHAR(20) NOT NULL,
                 fullname VARCHAR(255) NOT NULL,
                 email TEXT
             )',
            'CREATE UNIQUE INDEX ix_auths_cpanid ON auths(cpanid)',

            'CREATE TABLE files (
                 file_id INTEGER NOT NULL PRIMARY KEY,
                 file_name TEXT NOT NULL,
                 status TEXT -- ok, nometa, nofile, unsupported, metaerr, err
             )',
            'CREATE UNIQUE INDEX ix_files_file_name ON files(file_name)',

            'CREATE TABLE IF NOT EXISTS deps (
                 dep_id INTEGER NOT NULL PRIMARY KEY,
                 file_id INTEGER,
                 dist_id INTEGER,
                 mod_id INTEGER, -- if module is known (listed in mods table), only its id will be recorded here
                 mod_name TEXT,  -- if module is unknown (unlisted in mods), only the name will be recorded here
                 rel TEXT, -- relationship: requires, ...
                 phase TEXT, -- runtime, ...
                 version TEXT,
                 FOREIGN KEY (file_id) REFERENCES files(file_id),
                 FOREIGN KEY (dist_id) REFERENCES dists(dist_id),
                 FOREIGN KEY (mod_id) REFERENCES mods(mod_id)
             )',
            'CREATE INDEX IF NOT EXISTS ix_deps_mod_name ON deps(mod_name)',
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
    my ($file_id, $dist_id, $hash, $phase, $rel, $sth_insdep, $sth_selmod) = @_;
    $log->tracef("  Adding prereqs (%s %s): %s", $phase, $rel, $hash);
    for my $mod (keys %$hash) {
        $sth_selmod->execute($mod);
        my $row = $sth_selmod->fetchrow_hashref;
        my ($mod_id, $mod_name);
        if ($row) {
            $mod_id = $row->{mod_id};
        } else {
            $mod_name = $mod;
        }
        $sth_insdep->execute($file_id, $dist_id, $mod_id, $mod_name, $phase,
                             $rel, $hash->{$mod});
    }
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
    my $cpan = $args{cpan} or return [400, "Please specify 'cpan'"];

    my $dbh  = _connect_db($cpan);
    _create_schema($dbh);

    {
        my $path = "$cpan/authors/01mailrc.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        my $sth = $dbh->prepare("INSERT OR IGNORE INTO auths (cpanid,fullname,email) VALUES (?,?,?)");
        $dbh->begin_work;
        my $line = 0;
        while (<$fh>) {
            $line++;
            my ($cpanid, $fullname, $email) = /^alias (\S+)\s+"(.*) <(.+)>"/ or do {
                $log->warnf("  line %d: syntax error, skipped: %s", $line, $_);
                next;
            };
            $sth->execute($cpanid, $fullname, $email);
            my $auth_id = $dbh->last_insert_id("","","","");
            if ($auth_id) {
                $log->debugf("  new author: %s", $cpanid);
            }
        }
        $dbh->commit;
    }

    {
        my $path = "$cpan/modules/02packages.details.txt.gz";
        $log->infof("Parsing %s ...", $path);
        open my($fh), "<:gzip", $path or die "Can't open $path (<:gzip): $!";

        my $sth = $dbh->prepare("INSERT OR IGNORE INTO files (file_name) VALUES (?)");

        my $line = 0;
        my $newfiles = 0;
        my $after_begin = 0;
        while (<$fh>) {
            # commit after every 500 new files
            if ($newfiles % 500 == 499) {
                $log->tracef("  COMMIT");
                $dbh->commit;
                $after_begin = 0;
            }
            if ($newfiles % 500 == 0 && !$after_begin) {
                $log->tracef("  BEGIN");
                $dbh->begin_work;
                $after_begin = 1;
            }
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
            $sth->execute($file);
            my $file_id = $dbh->last_insert_id("","","","");
            if ($file_id) {
                $log->debugf("  New file: %s", $file);
            }
            # XXX parse dist, insert into dists
            # XXX insert into mods
            # XXX insert into deps
        } # while <fh>
        if ($after_begin) {
            $log->tracef("  COMMIT");
            $dbh->commit;
        }
    }

    return [200];

    # delete files in 'files' table no longer in 'dists' table
  DEL_FILES:
    {
        my $sth = $dbh->prepare("SELECT file_name
FROM files
WHERE NOT EXISTS (SELECT 1 FROM dists WHERE file_name=dist_file)
");
        $sth->execute;
        my @files;
        while (my $row = $sth->fetchrow_hashref) {
            push @files, $row->{file_name};
        }
        last DEL_FILES unless @files;
        $log->infof("Deleting files no longer in dists: %s ...", \@files);
        $dbh->do("DELETE
FROM deps WHERE file_id IN (
  SELECT file_id FROM files f
  WHERE NOT EXISTS (SELECT 1 FROM dists WHERE file_name=dist_file)
)");
        $dbh->do("DELETE
FROM files
WHERE NOT EXISTS (SELECT 1 FROM dists WHERE file_name=dist_file)
");
    }

    # list files in 'dists' but not already in 'files' table
    my $sth = $dbh->prepare("SELECT
  d.dist_id dist_id,
  dist_name,
  dist_file,
  cpanid,
  a.auth_id auth_id
FROM dists d
  LEFT JOIN auths a USING(auth_id)
WHERE NOT EXISTS (SELECT 1 FROM files WHERE file_name=dist_file)
ORDER BY dist_file
");
    $sth->execute;
    my @files;
    while (my $row = $sth->fetchrow_hashref) {
        push @files, $row;
    }

    my $sth_insfile;
    my $sth_seldist = $dbh->prepare("SELECT * FROM dists WHERE dist_name=?");
    my $sth_insdist = $dbh->prepare("INSERT INTO dists (dist_file,dist_vers,dist_name,auth_id) VALUES (?,?,?,?)");
    my $sth_selmod  = $dbh->prepare("SELECT * FROM mods WHERE mod_name=?");
    my $sth_insdep  = $dbh->prepare("INSERT INTO deps (file_id,dist_id,mod_id,mod_name,phase, rel,version) VALUES (?,?,?,?,?, ?,?)");

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

        $log->tracef("[#%i] Processing file %s ...", $i, $file->{dist_file});
        my $status;
        my $path = "$cpan/authors/id/".substr($file->{cpanid}, 0, 1)."/".
            substr($file->{cpanid}, 0, 2)."/$file->{cpanid}/$file->{dist_file}";

        unless (-f $path) {
            $log->errorf("File %s doesn't exist, skipped", $file->{dist_file});
            $sth_insfile->execute($file->{dist_file}, "nofile");
            next FILE;
        }

        # try to get META.yml or META.json
        my $meta;
      GET_META:
        {
            unless ($path =~ /(.+)\.(tar|tar\.gz|tar\.bz2|tar\.Z|tgz|tbz2?|zip)$/i) {
                $log->errorf("Doesn't support file type: %s, skipped", $file->{dist_file});
                $sth_insfile->execute($file->{dist_file}, "unsupported");
                next FILE;
            }

            my ($name, $ext) = ($1, $2);
            if (-f "$name.meta") {
                $log->tracef("Getting meta from .meta file: %s", "$name.meta");
                eval { $meta = _parse_json(~~File::Slurp::Tiny::read_file("$name.meta")) };
                unless ($meta) {
                    $log->errorf("Can't read %s: %s", "$name.meta", $@) if $@;
                    $sth_insfile->execute($file->{dist_file}, "err");
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
                $sth_insfile->execute($file->{dist_file}, "err");
                next FILE;
            }
        } # GET_META

        unless ($meta) {
            $log->infof("File %s doesn't contain META.json/META.yml, skipped", $path);
            $sth_insfile->execute($file->{dist_file}, "nometa");
            next FILE;
        }

        unless (ref($meta) eq 'HASH') {
            $log->infof("meta is not a hash, skipped");
            $sth_insfile->execute($file->{dist_file}, "metaerr");
            next FILE;
        }

        # check if dist record is in dists
        {
            my $dist_name = $meta->{name};
            if (!defined($dist_name)) {
                $log->errorf("meta does not contain name, skipped");
                $sth_insfile->execute($file->{dist_file}, "metaerr");
                next FILE;
            }
            $dist_name =~ s/::/-/g; # sometimes author miswrites module name
            $sth_seldist->execute($dist_name);
            my $row = $sth_seldist->fetchrow_hashref;
            if (!$row) {
                $log->warnf("Distribution %s not yet in dists, adding ...", $dist_name);
                $sth_insdist->execute($file->{dist_file}, $meta->{version}, $dist_name, $file->{dist_id});
            }
        }

        # insert dependency information
        {
            $sth_insfile->execute($file->{dist_file}, "ok");
            my $file_id = $dbh->last_insert_id("","","","");
            my $dist_id = $file->{dist_id};
            if (ref($meta->{build_requires}) eq 'HASH') {
                _add_prereqs($file_id, $dist_id, $meta->{build_requires}, 'build', 'requires', $sth_insdep, $sth_selmod);
            }
            if (ref($meta->{configure_requires}) eq 'HASH') {
                _add_prereqs($file_id, $dist_id, $meta->{configure_requires}, 'configure', 'requires', $sth_insdep, $sth_selmod);
            }
            if (ref($meta->{requires}) eq 'HASH') {
                _add_prereqs($file_id, $dist_id, $meta->{requires}, 'runtime', 'requires', $sth_insdep, $sth_selmod);
            }
            if (ref($meta->{prereqs}) eq 'HASH') {
                for my $phase (keys %{ $meta->{prereqs} }) {
                    my $phprereqs = $meta->{prereqs}{$phase};
                    for my $rel (keys %$phprereqs) {
                        _add_prereqs($file_id, $dist_id, $phprereqs->{$rel}, $phase, $rel, $sth_insdep, $sth_selmod);
                    }
                }
            }
        }
    } # for file

    $dbh->commit if $after_begin;
    undef $sth_insfile;
    undef $sth_seldist;
    undef $sth_insdist;
    undef $sth_selmod;
    undef $sth_insdep;
    undef $sth;

    $log->tracef("Disconnecting from SQLite database ...");
    $dbh->disconnect;

    [200];
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
