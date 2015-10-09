package App::lcpan::Cmd::copy_rel;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => "Copy a release file to current directory",
    args => {
        %App::lcpan::common_args,
        %App::lcpan::rel_args,
        %App::lcpan::overwrite_arg,
    },
};
sub handle_cmd {
    require File::Copy;

    my %args = @_;

    App::lcpan::_set_args_default(\%args);
    my $cpan = $args{cpan};
    my $index_name = $args{index_name};
    my $rel = $args{release};

    my $dbh = App::lcpan::_connect_db('ro', $cpan, $index_name);

    my $row = $dbh->selectrow_hashref("SELECT
  cpanid,
  name
FROM file
WHERE name=?
", {}, $rel);

    return [404, "No such release"] unless $row;

    my $srcpath = App::lcpan::_relpath($row->{name}, $cpan, $row->{cpanid});
    my $targetpath = $row->{name};

    if ((-f $targetpath) && !$args{overwrite}) {
        return [412, "Refusing to overwrite existing file '$targetpath'"];
    }

    File::Copy::syscopy($srcpath, $targetpath)
          or return [500, "Can't copy '$srcpath' to '$targetpath': $!"];

    [200, "OK", undef, {
        'func.source_path'=>$srcpath,
        'func.target_path'=>$targetpath,
    }];
}

1;
# ABSTRACT:
