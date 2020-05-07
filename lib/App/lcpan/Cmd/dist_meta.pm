package App::lcpan::Cmd::dist_meta;

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
    summary => 'Get distribution metadata',
    args => {
        %App::lcpan::common_args,
        %App::lcpan::dist_args,
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my ($dist_id, $cpanid, $file_name, $file_id, $has_metajson, $has_metayml) = $dbh->selectrow_array(
        "SELECT id, cpanid, name, has_metajson, has_metayml FROM file WHERE is_latest_dist AND dist_name=?", {}, $args{dist});
    $dist_id or return [404, "No such dist '$args{dist}'"];
    $has_metajson || $has_metayml or return [412, "Dist does not have metadata"];

    my $path = App::lcpan::_fullpath($file_name, $state->{cpan}, $cpanid);
    my $la_res = App::lcpan::_list_archive_members($path, $file_name, $file_id);
    return [500, "Can't read archive $path: $la_res->[1]"] unless $la_res->[0] == 200;

    my $gm_res = App::lcpan::_get_meta($la_res);
    return [500, "Can't extract distmeta from $path: $gm_res->[1]"] unless $gm_res->[0] == 200;
    $gm_res;
}

1;
# ABSTRACT:
