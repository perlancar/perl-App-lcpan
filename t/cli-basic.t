#!perl

use 5.010001;
use strict;
use warnings;
use FindBin '$Bin';
use Test2::Bundle::More;
use Test2::Tools::Cmd::Simple;

test_cmd(
    name => "--version",
    cmd => "$^X $Bin/../script/lcpan --version",
    test_exit_code => 0,
);

done_testing;
