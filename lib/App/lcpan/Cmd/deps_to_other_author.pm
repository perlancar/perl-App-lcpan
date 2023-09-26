package App::lcpan::Cmd::deps_to_other_author;

use 5.010;
use strict;
use warnings;

require App::lcpan;
use Perinci::Sub::Util qw(gen_modified_sub);

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

gen_modified_sub(
    base_name => 'App::lcpan::deps',
    output_name => 'handle_cmd',
    summary => 'List dependencies to modules of other authors',
    output_code => sub {
        my %args = @_;

        my $state = App::lcpan::_init(\%args, 'ro');
        my $dbh = $state->{dbh};

        my @authors;
        if ($args{dists}) {
            my $sth = $dbh->prepare(
                "SELECT DISTINCT cpanid FROM file WHERE dist_name IN (".
                join(", ", map { $dbh->quote($_) } @{ $args{dists} }).")");
            $sth->execute;
            while (my @row = $sth->fetchrow_array) {
                push @authors, $row[0];
            }
            $sth->finish;
            return [404, "No such dist(s)"] unless @authors;
        } else {
            return [400, "Please specify dists"];
        }

        my $res = App::lcpan::deps(%args);
        return $res unless $res->[0] == 200;

        $res->[2] = [grep { my $author = $_->{author}; !defined($author) || !(grep {$author eq $_} @authors) } @{ $res->[2] }];
        $res;
    },
);

1;
# ABSTRACT:
