use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Promised::Command;
use AnyEvent;

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigterm received!\n";
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGTERM received\nsigterm received!\n.*terminated by SIGTERM};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'has handler';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigterm received!\n";
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    Promised::Command::Signals->_remove_handler (TERM => $code);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    test {
      ok 0;
    } $c;
  }, sub {
    my $result = $_[0];
    test {
      is $result->signal, 15;
      unlike $stderr, qr{sigterm};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'handler removed';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigterm received!\n";
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    undef $sig;
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    test {
      ok 0;
    } $c;
  }, sub {
    my $result = $_[0];
    test {
      is $result->signal, 15;
      unlike $stderr, qr{sigterm};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'handler destroyed';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigint received 1\n";
    };
    my $code2 = sub {
      warn "sigint received 2\n";
    };
    my $sig1 = Promised::Command::Signals->add_handler (INT => $code);
    my $sig2 = Promised::Command::Signals->add_handler (INT => $code2);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'INT', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGINT received\n(?:sigint received 1\nsigint received 2\n|sigint received 2\nsigint received 1\n).*terminated by SIGINT};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'has multiple handlers';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigint received 1\n";
    };
    my $code2 = sub {
      warn "sigint received 2\n";
    };
    my $sig1 = Promised::Command::Signals->add_handler (INT => $code);
    my $sig2 = Promised::Command::Signals->add_handler (INT => $code2);
    undef $sig1;
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'INT', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGINT received\nsigint received 2\n.*terminated by SIGINT};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'has some handler';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promise;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigquit received!\n";
      return Promise->new (sub {
        my $ok = $_[0];
        my $timer; $timer = AE::timer 0.1, 0, sub {
          $ok->();
          undef $timer;
        };
      })->then (sub {
        warn "sigquit promise resolved\n";
      });
    };
    my $sig = Promised::Command::Signals->add_handler (QUIT => $code);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'QUIT', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGQUIT received\nsigquit received!\nsigquit promise resolved\n.*terminated by SIGQUIT};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'has promised handler';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      die "sigterm received!";
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGTERM received\n.*Died within signal handler "": sigterm received! at .+\n.*terminated by SIGTERM};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'died in handler';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promise;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      die "sigterm received!";
    };
    my $code2 = sub {
      Promise->resolve->then (sub {
        warn "sigterm received then.";
      });
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    my $sig = Promised::Command::Signals->add_handler (TERM => $code2);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGTERM received\n(?:.*sigterm received then.+\n.*Died within signal handler "": sigterm received! at .+|.*Died within signal handler "": sigterm received! at .+\n.*sigterm received then.+)\n.*terminated by SIGTERM};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'died in handler, and not dead';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promise;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      return Promise->reject ("sigterm received!");
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGTERM received\n.*Died within signal handler "": sigterm received!.*\n.*terminated by SIGTERM};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'rejected in handler';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigterm received!\n";
      $_[0]->();
    };
    my $sig = Promised::Command::Signals->add_handler (TERM => $code);
    my $sig2 = Promised::Command::Signals->add_handler (INT => sub {
      warn "sigint received\n";
    });
    $cv->recv;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'INT', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 1;
      like $stderr, qr{SIGTERM received\nsigterm received!\n.*SIGINT received\nsigint received\n.*terminated by SIGINT};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'has handler, canceled';

test {
  my $c = shift;
  my $cmd = Promised::Command->new (['perl', '-e', q{
    use AnyEvent;
    use Promised::Command::Signals;
    my $cv = AE::cv;
    my $code = sub {
      warn "sigterm received!\n";
      my $t; $t = AE::timer 3, 0, sub {
        $cv->send;
        undef $t;
      };
    };
    Promised::Command::Signals->abort_signal->manakai_onabort ($code);
    $cv->recv;
    warn "ended\n";
    exit 3;
  }]);
  $cmd->stderr (\my $stderr);
  $cmd->run->then (sub {
    return Promise->new (sub {
      my $ok = $_[0];
      my $timer; $timer = AE::timer 0.5, 0, sub {
        kill 'TERM', $cmd->pid;
        $ok->();
        undef $timer;
      };
    });
  })->then (sub {
    return $cmd->wait;
  })->then (sub {
    my $result = $_[0];
    test {
      is $result->exit_code, 3;
      like $stderr, qr{SIGTERM received\nsigterm received!\nended\n$};
    } $c;
    done $c;
    undef $c;
  });
} n => 2, name => 'ac: has handler';

run_tests;

=head1 LICENSE

Copyright 2015-2022 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
