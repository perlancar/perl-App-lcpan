package App::lcpan::Cmd::rdeps_from_other_author;

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
    base_name => 'App::lcpan::rdeps',
    output_name => 'handle_cmd',
    remove_args => ['authors', 'authors_arent'],
    summary => 'List reverse dependencies from distributions of other authors',
    output_code => sub {
        my %args = @_;

        my $state = App::lcpan::_init(\%args, 'ro');
        my $dbh = $state->{dbh};

        my @authors;
        if ($args{modules}) {
            my $sth = $dbh->prepare(
                "SELECT DISTINCT cpanid FROM module WHERE name IN (".
                join(", ", map { $dbh->quote($_) } @{ $args{modules} }).")");
            $sth->execute;
            while (my @row = $sth->fetchrow_array) {
                push @authors, $row[0];
            }
            $sth->finish;
            return [404, "No such module(s)"] unless @authors;
        } elsif ($args{dists}) {
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
            return [400, "Please specify either modules/dists"];
        }

        App::lcpan::rdeps(
            %args,
            authors_arent => \@authors,
        );
    },
);

1;
# ABSTRACT:
