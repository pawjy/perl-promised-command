use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;

my $dhh_host;
BEGIN {
  $dhh_host = rand () . '.test';
  $ENV{PROMISED_COMMAND_DOCKERHOST_HOST} = $dhh_host;
}

use Promised::Command::Docker;

test {
  my $c = shift;
  my $r = Promised::Command::Docker->dockerhost_host_for_container;
  test {
    is $r, $dhh_host, $dhh_host;
  } $c;
  done $c;
} n => 1, name => 'dockerhost_host_for_container (class method)';

test {
  my $c = shift;
  my $d = Promised::Command::Docker->new;
  test {
    is $d->dockerhost_host_for_container, $dhh_host;
  } $c;
  done $c;
} n => 1, name => 'dockerhost_host_for_container (object method)';

run_tests;

=head1 LICENSE

Copyright 2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
