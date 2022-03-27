package App::lcpan::Cmd::inject;

use 5.010;
use strict;
use warnings;

require App::lcpan;
use Proc::ChildError qw(explain_child_error);

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Inject one or more tarballs to the mirror',
    args => {
        %App::lcpan::common_args,
        author => {
            schema => ['str*'],
            req => 1,
            cmdline_aliases => {a=>{}},
            completion => \&_complete_cpanid,
        },
        files => {
            schema => ['array*', of=>'filename*', min_len=>1],
            'x.name.is_plural' => 1,
            req => 1,
            pos => 0,
            slurpy => 1,
        },
    },
    deps => {
        prog => 'orepan.pl',
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'rw');
    my $author = delete $args{author};
    my $files  = delete $args{files};
    my $dbh = $state->{dbh};

    for my $file (@$files) {
        system "orepan.pl", "--destination", $state->{cpan}, "--pause", $author,
            $file;
        return [500, "orepan.pl failed: ".explain_child_error()] if $?;
    }

    App::lcpan::update(
        %args,
        update_files => 0,
        update_index => 1,
    );
}

1;
# ABSTRACT:
