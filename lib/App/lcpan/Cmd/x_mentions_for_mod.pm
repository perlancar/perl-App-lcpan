package App::lcpan::Cmd::x_mentions_for_mod;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'List distributions which has an x_mentions relationship '.
        'dependency for specified module',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::mod_args,
        %App::lcpan::detail_args,
    },
};
sub handle_cmd {
    my %args = @_;

    $args{modules} = [delete $args{module}];
    App::lcpan::rdeps(
        %args,
        rel => 'x_mentions',
        phase => 'x_mentions',
    );
}

1;
# ABSTRACT:

=head1 SEE ALSO

L<acme-cpanmodules-for>
