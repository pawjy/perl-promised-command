use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Promised::Command::Docker;
use Promised::Flow;

my $Docker = undef;

test {
  my $c = shift;
  my $cmd = Promised::Command::Docker->new (
    docker => $Docker,
    image => 'debian:sid',
    command => ['sleep', 100],
  );
  $cmd->get_dockerhost_ipaddr->then (sub {
    my $r = $_[0];
    test {
      like $r, qr{\A[0-9]+(?:\.[0-9]+){3}\z};
      ok $cmd->dockerhost_host_for_container;
    } $c;
    return $cmd->get_dockerhost_ipaddr->then (sub {
      my $r2 = $_[0];
      test {
        is $r2, $r;
      } $c;
    });
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 3, name => 'get_dockerhost_ipaddr (object method)';

test {
  my $c = shift;
  Promised::Command::Docker->get_dockerhost_ipaddr->then (sub {
    my $r = $_[0];
    test {
      like $r, qr{\A[0-9]+(?:\.[0-9]+){3}\z};
    } $c;
  })->then (sub {
    done $c;
    undef $c;
  });
} n => 1, name => 'get_dockerhost_ipaddr (class method)';

test {
  my $c = shift;
  my $r = Promised::Command::Docker->dockerhost_host_for_container;
  test {
    ok $r;
  } $c;
  done $c;
} n => 1, name => 'dockerhost_host_for_container (class method)';

run_tests;

=head1 LICENSE

Copyright 2017 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
