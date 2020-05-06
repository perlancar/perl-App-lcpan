#!perl

use 5.010001;
use strict;
use warnings;
use FindBin '$Bin';
use Test::More 0.98;

# list of minicpans test data:
#
# - minicpan1:
#   + 4 authors, only contains 1 release (BUDI)
# - minicpan2:
#   + 1 new author (KADAL), 1 removed author (NINA), 1 changed author (BUDI, email)
#   + 2 new distros
#     - Kadal-Busuk-1.00.tar.bz2 (naked, no containing folder)
#       + no changes, manifest, license, readme
#       + modules: Kadal::Busuk, Kadal::Busuk::Sekali (no pod, no abstract, no version)
#       + dep: runtime-requires to Foo::Bar
#       + dep: test-requires to Foo::Bar::Baz
#     - Kadal-Rusak-1.00.tar.gz (not a tar.gz, cannot be extracted)
#     - Kadal-Hilang-1.00.tar.gz (indexed but does not exist)
#     - Kadal-Jelek-1.00.tar.bz2
#       + modules: Kadal::Jelek, Kadal::Jelek::Sekali (all put in top-level dir)
#       + no distro metadata, but has Makefile.PL which can be run to produce MYMETA.*
#       + 2 scripts (in bin/, script/)
#   + 1 updated distro (Foo-Bar-0.02)
#     - release file now in subdir subdir1/
#     - format changed to zip
#     - has META.yml now instead of META.json
#     - add a module: Foo::Bar::Qux (different version: 3.10)
#     - removed a module: Foo::Bar::Baz
#     - update module: Foo::Bar (abstract, add subs)
#     - add, remove some deps, update some deps (version)
# - TODO minicpan3:
# - TODO minicpan4:
#
# list of releases test data:
#
# - Foo-Bar-0.01.tar.gz: META.json
#
# todo:
# - module that change maintainer
# - removed distro
# - added scripts
# - updated scripts (abstract, distro)
# - removed scripts
# - option: skipped files
# - option: skipped files from sub indexing
# - pod:
# - mentions

use File::Copy::Recursive qw(dircopy fcopy);
use File::Temp qw(tempdir tempfile);
use IPC::System::Options qw(system);
use JSON::MaybeXS;

my $tempdir = tempdir(CLEANUP => !$ENV{DEBUG});

subtest minicpan1 => sub {
    dircopy("$Bin/data/minicpan1", "$tempdir/minicpan1");

    my $res;

    run_lcpan_ok("update", "--cpan", "$tempdir/minicpan1", "--no-use-bootstrap", "--no-update-files");

    subtest "authors" => sub {

        $res = run_lcpan_json("authors", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [qw/BUDI NINA TONO WATI/]);

        $res = run_lcpan_json("authors", "--cpan", "$tempdir/minicpan1", "-l");
        is_deeply($res->{stdout}, [
            {id=>'BUDI', name=>'Budi Bahagia', email=>'CENSORED'},
            {id=>'NINA', name=>'Nina Nari', email=>'nina1993@example.org'},
            {id=>'TONO', name=>'Tono Tentram', email=>'CENSORED'},
            {id=>'WATI', name=>'Wati Legowo', email=>'wati@example.com'},
        ]);

        # XXX test options
    };

    subtest "modules, mods" => sub {

        $res = run_lcpan_json("modules", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [qw/Foo::Bar Foo::Bar::Baz/]);

        $res = run_lcpan_json("mods", "--cpan", "$tempdir/minicpan1", "-l");
        is($res->{stdout}[0]{module}, 'Foo::Bar');
        is($res->{stdout}[0]{dist}, 'Foo-Bar');
        is($res->{stdout}[0]{author}, 'BUDI');
        is($res->{stdout}[0]{version}, '0.01');
        is($res->{stdout}[0]{abstract}, 'A Foo::Bar module for testing');

        is($res->{stdout}[1]{module}, 'Foo::Bar::Baz');
        is($res->{stdout}[1]{dist}, 'Foo-Bar');
        is($res->{stdout}[1]{author}, 'BUDI');
        is($res->{stdout}[1]{version}, '0.01');
        is($res->{stdout}[1]{abstract}, 'A Foo::Bar::Baz module for testing');

        # XXX test options
    };

    subtest "dists" => sub {

        $res = run_lcpan_json("dists", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [qw/Foo-Bar/]);

        $res = run_lcpan_json("dists", "--cpan", "$tempdir/minicpan1", "-l");
        is($res->{stdout}[0]{dist}, 'Foo-Bar');
        is($res->{stdout}[0]{author}, 'BUDI');
        is($res->{stdout}[0]{version}, '0.01');
        is($res->{stdout}[0]{release}, 'Foo-Bar-0.01.tar.gz');
        is($res->{stdout}[0]{abstract}, 'A Foo::Bar module for testing');

        # XXX test options
    };

    subtest "releases, rels" => sub {

        $res = run_lcpan_json("releases", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [qw!B/BU/BUDI/Foo-Bar-0.01.tar.gz!]);

        $res = run_lcpan_json("rels", "--cpan", "$tempdir/minicpan1", "-l");
        is_deeply($res->{stdout}[0]{name}, 'B/BU/BUDI/Foo-Bar-0.01.tar.gz');
        is_deeply($res->{stdout}[0]{author}, 'BUDI');
        is_deeply($res->{stdout}[0]{file_status}, 'ok');
        is_deeply($res->{stdout}[0]{file_error}, undef);
        is_deeply($res->{stdout}[0]{has_buildpl}, 0);
        is_deeply($res->{stdout}[0]{has_makefilepl}, 1);
        is_deeply($res->{stdout}[0]{has_metajson}, 1);
        is_deeply($res->{stdout}[0]{has_metayml}, 0);
        is_deeply($res->{stdout}[0]{meta_status}, 'ok');
        is_deeply($res->{stdout}[0]{meta_error}, undef);
        ok($res->{stdout}[0]{size} > 0);
        ok($res->{stdout}[0]{mtime} > 0);

    };

    subtest "deps" => sub {

        $res = run_lcpan_json("deps", "--cpan", "$tempdir/minicpan1", "--all", "Foo::Bar");
        my $deps = {};
        for (@{ $res->{stdout} }) { $deps->{ $_->{phase} }{ $_->{rel} }{ $_->{module} } = $_->{version} }
        is_deeply($deps, {
            develop => { requires => {
                'Pod::Coverage::TrustPod' => 0,
                'Test::Perl::Critic' => 0,
                'Test::Pod' => '1.41',
                'Test::Pod::Coverage' => '1.08',
            }},
            configure => { requires => {
                'ExtUtils::MakeMaker' => 0,
            }},
            test => { requires => {
                'File::Spec' => 0,
                'IO::Handle' => 0,
                'IPC::Open3' => 0,
                'Test::More' => 0,
            }},
        }) or diag explain $deps;

    };

    subtest "contents" => sub {

        $res = run_lcpan_json("contents", "--cpan", "$tempdir/minicpan1");
        ok(scalar(@{ $res->{stdout} }));

        # XXX test contents detail
    };
};

subtest minicpan2 => sub {
    dircopy("$Bin/data/minicpan2", "$tempdir/minicpan2");
    fcopy  ("$tempdir/minicpan1/index.db", "$tempdir/minicpan2/index.db");

    my $res;

    run_lcpan_ok("update", "--cpan", "$tempdir/minicpan2", "--no-update-files");

    subtest "authors" => sub {

        $res = run_lcpan_json("authors", "--cpan", "$tempdir/minicpan2");
        is_deeply($res->{stdout}, [qw/BUDI KADAL TONO WATI/]);

        $res = run_lcpan_json("authors", "--cpan", "$tempdir/minicpan2", "-l");
        is_deeply($res->{stdout}, [
            {id=>'BUDI' , name=>'Budi Bahagia', email=>'budi@example.org'},
            {id=>'KADAL', name=>'Kadal', email=>'CENSORED'},
            {id=>'TONO' , name=>'Tono Tentram', email=>'CENSORED'},
            {id=>'WATI' , name=>'Wati Legowo', email=>'wati@example.com'},
        ]);

        # XXX test options
    };

    subtest "modules, mods" => sub {

        $res = run_lcpan_json("modules", "--cpan", "$tempdir/minicpan2");
        is_deeply($res->{stdout}, [
            'Foo::Bar',             # [0]
            'Foo::Bar::Baz',        # [1]
            'Foo::Bar::Qux',        # [2]
            'Kadal::Busuk',         # [3]
            'Kadal::Busuk::Sekali', # [4]
            'Kadal::Hilang',        # [5]
            'Kadal::Jelek',         # [6]
            'Kadal::Jelek::Sekali', # [7]
            'Kadal::Rusak',         # [8]
        ]);

        $res = run_lcpan_json("mods", "--cpan", "$tempdir/minicpan1", "-l");
        is($res->{stdout}[0]{version}, '0.02', 'Foo::Bar version updated to 0.02');
        is($res->{stdout}[1]{version}, '0.01', 'Foo::Bar::Baz version still at 0.01, refers to old dist');
        # XXX why is Foo::Bar::Qux version 0.02 and not 3.10?

        # XXX test options
    };

    subtest "dists" => sub {

        $res = run_lcpan_json("dists", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [
            'Foo-Bar',
            # XXX Foo-Bar-Baz and Foo-Bar-Qux should not exist
            'Foo-Bar-Baz',
            'Foo-Bar-Qux',
        ]);

        $res = run_lcpan_json("dists", "--cpan", "$tempdir/minicpan1", "-l");
        is($res->{stdout}[0]{dist}, 'Foo-Bar');
        is($res->{stdout}[0]{author}, 'BUDI');
        is($res->{stdout}[0]{version}, '0.01');
        is($res->{stdout}[0]{release}, 'Foo-Bar-0.01.tar.gz');
        is($res->{stdout}[0]{abstract}, 'A Foo::Bar module for testing');

        # XXX test options
    };

    subtest "releases, rels" => sub {

        $res = run_lcpan_json("releases", "--cpan", "$tempdir/minicpan1");
        is_deeply($res->{stdout}, [qw!B/BU/BUDI/Foo-Bar-0.01.tar.gz!]);

        $res = run_lcpan_json("rels", "--cpan", "$tempdir/minicpan1", "-l");
        is_deeply($res->{stdout}[0]{name}, 'B/BU/BUDI/Foo-Bar-0.01.tar.gz');
        is_deeply($res->{stdout}[0]{author}, 'BUDI');
        is_deeply($res->{stdout}[0]{file_status}, 'ok');
        is_deeply($res->{stdout}[0]{file_error}, undef);
        is_deeply($res->{stdout}[0]{has_buildpl}, 0);
        is_deeply($res->{stdout}[0]{has_makefilepl}, 1);
        is_deeply($res->{stdout}[0]{has_metajson}, 1);
        is_deeply($res->{stdout}[0]{has_metayml}, 0);
        is_deeply($res->{stdout}[0]{meta_status}, 'ok');
        is_deeply($res->{stdout}[0]{meta_error}, undef);
        ok($res->{stdout}[0]{size} > 0);
        ok($res->{stdout}[0]{mtime} > 0);

    };

    subtest "deps" => sub {

        $res = run_lcpan_json("deps", "--cpan", "$tempdir/minicpan1", "--all", "Foo::Bar");
        my $deps = {};
        for (@{ $res->{stdout} }) { $deps->{ $_->{phase} }{ $_->{rel} }{ $_->{module} } = $_->{version} }
        is_deeply($deps, {
            develop => { requires => {
                'Pod::Coverage::TrustPod' => 0,
                'Test::Perl::Critic' => 0,
                'Test::Pod' => '1.41',
                'Test::Pod::Coverage' => '1.08',
            }},
            configure => { requires => {
                'ExtUtils::MakeMaker' => 0,
            }},
            test => { requires => {
                'File::Spec' => 0,
                'IO::Handle' => 0,
                'IPC::Open3' => 0,
                'Test::More' => 0,
            }},
        }) or diag explain $deps;

    };

    subtest "contents" => sub {

        $res = run_lcpan_json("contents", "--cpan", "$tempdir/minicpan1");
        ok(scalar(@{ $res->{stdout} }));

        # XXX test contents detail
    };
};

DONE_TESTING:
done_testing;

sub run_lcpan {
    my ($stdout, $stderr);
    system(
        {
            env => {PERL5OPT=>"-I$Bin/../lib"},
            log => 1,
            ($ENV{DEBUG} ? (tee_stdout => \$stdout) : (capture_stdout => \$stdout)),
            ($ENV{DEBUG} ? (tee_stderr => \$stderr) : (capture_stderr => \$stderr)),
        },
        $^X, "$Bin/../script/lcpan",
        "--no-config",
        ($ENV{DEBUG} ? ("--trace") : ()),
        @_,
    );

    my ($exit_code, $signal, $core_dump) = ($? < 0 ? $? : $? >> 8, $? & 127, $? & 128);
    return {
        exit_code => $exit_code,
        signal    => $signal,
        core_dump => $core_dump,
        stdout    => $stdout,
        stderr    => $stderr,
    };
}

sub run_lcpan_json {
    my $res = run_lcpan(@_, "--format=json");
    eval {
        $res->{stdout} = JSON::MaybeXS::decode_json($res->{stdout});
    };
    warn if $@;
    $res;
}

sub run_lcpan_ok {
    my $res = run_lcpan(@_);
    is($res->{exit_code}, 0);
    $res;
}
