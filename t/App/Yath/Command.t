use Test2::V0 -target => 'App::Yath::Command';
#skip_all "Not done, come back!";

local $ENV{HARNESS_PERL_SWITCHES};

use Config qw/%Config/;

use File::Temp qw/tempdir/;

use Cwd qw/cwd/;

use ok $CLASS;

can_ok($CLASS, [qw/settings signal args plugins/], "Got public attributes");

can_ok(
    $CLASS, [
        qw{
            handle_list_args
            feeder
            cli_args
            internal_only
            has_jobs
            has_runner
            has_logger
            has_display
            show_bench
            always_keep_dir
            name
            summary
            description
            group
        }
    ],
    "Got public methods subclasses are expected to override"
);

{

    package App::Yath::Command::fake;
    use parent 'App::Yath::Command';

    sub cli_args { 'xxx' }
}

my $TCLASS = 'App::Yath::Command::fake';

subtest for_override => sub {
    is([$CLASS->handle_list_args], [], "handle_list_args returns empty list");
    is([$CLASS->feeder],           [], "feeder returns empty list");
    is([$CLASS->cli_args],         [], "cli_args returns empty list");

    is($CLASS->internal_only,   0, "internal_only defaults to 0");
    is($CLASS->has_jobs,        0, "has_jobs defaults to 0");
    is($CLASS->has_runner,      0, "has_runner defaults to 0");
    is($CLASS->has_logger,      0, "has_logger defaults to 0");
    is($CLASS->has_display,     0, "has_display defaults to 0");
    is($CLASS->always_keep_dir, 0, "always_keep_dir defaults to 0");

    is($CLASS->show_bench, 1, "show_bench defaults to 1");

    is($CLASS->summary,     "No Summary",     "sane default summary");
    is($CLASS->description, "No Description", "sane default description");

    is($TCLASS->name,      'fake', "got name of command from class");
    is($TCLASS->new->name, 'fake', "got name of command from instance");

    is($CLASS->group, "ZZZZZZ", "Default group is near the end in an ASCII sort");
};

subtest my_opts => sub {
    my $control = mock $TCLASS;

    $control->override(has_jobs => sub { 1 });
    my $opts = $TCLASS->my_opts;
    for my $opt (@$opts) {
        next if $opt->{used_by}->{all};
        next if $opt->{used_by}->{jobs};
        fail("Got opt $opt->{spec}");
    }
    $control->reset('has_jobs');

    $control->override(has_runner => sub { 1 });
    $opts = $TCLASS->my_opts;
    for my $opt (@$opts) {
        next if $opt->{used_by}->{all};
        next if $opt->{used_by}->{runner};
        fail("Got opt $opt->{spec}");
    }
    $control->reset('has_runner');

    $control->override(has_logger => sub { 1 });
    $opts = $TCLASS->my_opts;
    for my $opt (@$opts) {
        next if $opt->{used_by}->{all};
        next if $opt->{used_by}->{logger};
        fail("Got opt $opt->{spec}");
    }
    $control->reset('has_logger');

    $control->override(has_display => sub { 1 });
    $opts = $TCLASS->my_opts;
    for my $opt (@$opts) {
        next if $opt->{used_by}->{all};
        next if $opt->{used_by}->{display};
        fail("Got opt $opt->{spec}");
    }
    $control->reset('has_display');

    $control->override(has_display => sub { 1 });
    $control->override(has_jobs    => sub { 1 });
    $control->override(has_logger  => sub { 1 });
    $control->override(has_runner  => sub { 1 });
    $opts = $TCLASS->my_opts;
    is(@$opts, (my @foo = $CLASS->options({})), "Got all opts");

    my $one = $TCLASS->new;
    ref_is($one->my_opts, $one->my_opts, "Command instance caches result");
};

subtest init => sub {
    my $control = mock $TCLASS;

    my $one = bless {}, $TCLASS;

    ok(lives { $one->init }, "can call init on empty instance");

    ref_ok($one->settings,         'HASH',  'Got a hash reference for settings');
    ref_ok($one->settings->{libs}, 'ARRAY', "libs setting was normalized");
    ok(!$one->settings->{dir}, "no dir");

    $control->override(has_runner => sub { 1 });
    $one = $TCLASS->new();

    ok(my $dir = $one->settings->{dir}, "got a dir");
    my $garbage = File::Spec->canonpath($dir . '/garbage');

    open(my $fh, '>', $garbage) or die "Could not open file: $!";
    print $fh "garbage\n";
    close($fh);

    $one = undef;

    ok(-f $garbage, "Garbage file was left behind");

    like(
        dies { $one = $TCLASS->new(args => [-d => $dir]) },
        qr/^Work directory is not empty \(use -C to clear it\)/,
        "Cannot use a non-empty dir by default"
    );

    ok(lives { $one = $TCLASS->new(args => [-d => $dir, '-C']) }, "Can clear dir");
    ok(!-f $garbage, "garbage file was removed");

    $control->reset_all;

    local @INC = (File::Spec->canonpath('t/lib'), @INC);
    $one = $TCLASS->new(args => ['-pTest']);

    ok($INC{'App/Yath/Plugin/Test.pm'}, "Loaded test plugin") or return;

    is(
        App::Yath::Plugin::Test->GET_CALLS,
        {
            options   => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($one->settings)]],
            pre_init  => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($one->settings)]],
            post_init => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($one->settings)]],
        },
        "Called correct plugin methods",
    );
};

subtest normalize_settings => sub {
    my $control = mock $TCLASS;
    my $one = bless {}, $TCLASS;

    $control->override(
        my_opts => sub {
            return [
                {
                    spec    => 'foo',
                    field   => 'foo',
                    default => 1,
                },

                {
                    spec    => 'bar',
                    field   => 'bar',
                    default => 1,
                    action  => sub {
                        my $self = shift;
                        my ($settings, $field, $val, $opt) = @_;

                        $settings->{bar} = {self => $self, field => $field, val => $val, opt => $opt};
                    },
                },

                {
                    spec    => 'baz',
                    field   => 'bugaboo',
                    default => 1,
                    action  => sub {
                        my $self = shift;
                        my ($settings, $field, $val, $opt) = @_;

                        $settings->{baz} = {self => $self, field => $field, val => $val, opt => $opt};
                    },
                },

                {
                    spec    => 'boo',
                    field   => 'boo',
                    default => sub {
                        my $self = shift;
                        my ($settings, $field) = @_;

                        return {self => $self, settings => $settings, field => $field};
                    },
                },

                {
                    spec      => 'bun=s',
                    field     => 'bun',
                    default   => 'a value',
                    normalize => sub {
                        my $self = shift;
                        my ($settings, $field, $val) = @_;

                        return {self => $self, settings => $settings, field => $field, val => $val};
                    },
                }
            ];
        }
    );

    $one->{settings} = {};
    $one->settings->{libs} = ['xfoo', 'xbar'];
    $one->settings->{lib}  = 1;
    $one->settings->{blib} = 1;
    $one->settings->{tlib} = 1;

    {
        local $ENV{PERL5LIB} = 'xbaz' . $Config{path_sep} . 'xbat';
        my $fs_control = mock 'File::Spec' => (
            override => [
                rel2abs => sub { return "ABS $_[-1]" },
            ],
        );
        $one->normalize_settings();
    }

    is(
        $one->settings,
        hash {
            field lib  => 1;
            field blib => 1;
            field tlib => 1;
            field foo  => 1;

            field bar => {self => exact_ref($one), field => 'bar',     val => 1, opt => undef};
            field baz => {self => exact_ref($one), field => 'bugaboo', val => 1, opt => undef};
            field boo => {self => exact_ref($one), settings => exact_ref($one->settings), field => 'boo'};
            field bun => {self => exact_ref($one), settings => exact_ref($one->settings), field => 'bun', val => 'a value'};

            field env_vars => {HARNESS_IS_VERBOSE => 0, T2_HARNESS_IS_VERBOSE => 0};

            field libs => bag {
                item "ABS xfoo";
                item "ABS xbar";
                item "ABS xbaz";
                item "ABS xbat";
                item "ABS lib";
                item "ABS blib/lib";
                item "ABS blib/arch";
                item "ABS t/lib";
                end;
            };
            end;
        },
        "Got settings"
    );
};

subtest run => sub {
    my $control = mock $TCLASS;

    my $one = $TCLASS->new;

    $control->override('run_command' => sub { 321 });

    $control->override('pre_run' => sub { 123 });
    is($one->run, 123, "pre-run returned a value, did not call run_command");

    $control->override('pre_run' => sub { 0 });
    is($one->run, 0, "pre-run returned a 0 value, did not call run_command");

    $control->override('pre_run' => sub { undef });
    is($one->run, 321, "called run_command");
};

subtest pre_run => sub {
    my $control = mock $TCLASS;

    my $injected = 0;
    $control->override(inject_signal_handlers => sub { $injected++ });

    my @painted;
    $control->override(paint => sub { shift; push @painted => @_ });

    my $one = $TCLASS->new();

    $one->settings->{help} = 1;
    is($one->pre_run, 0, "returned 0 for help");
    is(\@painted, [$one->usage], "Painted usage info");
    ok(!$injected, "did not inject signal handlers");

    @painted = ();

    delete $one->settings->{help};
    $one->settings->{show_opts} = 1;
    $one->settings->{input}     = 'foo' x 1000;
    require Test2::Harness::Util::JSON;
    my $json = Test2::Harness::Util::JSON::encode_pretty_json({%{$one->settings}, input => '<TRUNCATED>'});
    is($one->pre_run, 0, "show opts returned 0");
    is(\@painted, [$json], "got options");
    ok(!$injected, "did not inject signal handlers");

    delete $one->settings->{show_opts};
    is($one->pre_run, undef, "pre_run did not return a defined value");
    is($injected,     1,     "injected signal handlers");
};

subtest paint => sub {
    my $one = $TCLASS->new;

    my $out = '';
    open(my $fh, '>', \$out);
    my $old = select $fh;

    my $ok = eval {
        $one->settings->{quiet} = 1;
        $one->paint("foo\n");
        ok(!$out, "did not paint in quiet mode");

        $one->settings->{quiet} = 0;
        $one->paint("bar\n");
        is($out, "bar\n", "wrote outside of quiet mode");
    };
    my $err = $@;

    select $old;

    die $err unless $ok;
};

subtest make_run_from_settings => sub {
    my $one = bless(
        {
            settings => {
                run_id           => 123,
                job_count        => 3,
                switches         => ['-w'],
                libs             => ['foo', 'bar'],
                lib              => 1,
                blib             => 1,
                tlib             => 1,
                preload          => ['Scalar::Util'],
                load             => [],
                load_import      => [],
                pass             => ['--foo'],
                input            => "my input",
                search           => ['t', 't2'],
                unsafe_inc       => 1,
                env_vars         => {foo => 1, bar => 2},
                use_stream       => 1,
                use_fork         => 1,
                times            => 1,
                verbose          => 2,
                no_long          => 0,
                exclude_patterns => [qr/xxx/],
                exclude_files    => ['t/xxx.t'],
            },
            plugins => ['Foo::Bar'],
        },
        $TCLASS
    );

    my $fs_control = mock 'File::Spec' => (
        override => [
            rel2abs => sub { return "ABS $_[-1]" },
        ],
    );

    is(
        $one->make_run_from_settings(load => ['Foo::Bar']),
        object {
            call run_id           => 123;
            call job_count        => 3;
            call switches         => ['-w'];
            call libs             => ['foo', 'bar'];
            call lib              => 1;
            call blib             => 1;
            call tlib             => 1;
            call preload          => ['Scalar::Util'];
            call load             => ['Foo::Bar'];
            call load_import      => [];
            call args             => ['--foo'];
            call input            => "my input";
            call search           => ['t', 't2'];
            call unsafe_inc       => 1;
            call use_stream       => 1;
            call use_fork         => 1;
            call times            => 1;
            call verbose          => 2;
            call no_long          => 0;
            call plugins          => ['Foo::Bar'];
            call exclude_patterns => [qr/xxx/];
            call exclude_files    => {'ABS t/xxx.t' => 1};
            call env_vars         => hash {
                field foo => 1;
                field bar => 2;
                etc;
            };
        },
        "Got expected run"
    );
};

subtest section_order => sub {
    # Just test we get a sane list of strings, do not actually test order, that
    # can change for many reasons in the future.
    my @got = $CLASS->section_order;
    ok(@got > 1, "More than 1 item");
    ok((!grep { ref($_) } @got), "No references");
};

subtest options => sub {
    my $control = mock $TCLASS;

    $control->override(has_display => sub { 1 });
    $control->override(has_jobs    => sub { 1 });
    $control->override(has_logger  => sub { 1 });
    $control->override(has_runner  => sub { 1 });

    subtest show_opts => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{show_opts}, "not on by default");

        my $two = $TCLASS->new(args => ['--show-opts']);
        ok($two->settings->{show_opts}, "toggled on");
    };

    subtest help => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{help}, "not on by default");

        my $two = $TCLASS->new(args => ['--help']);
        ok($two->settings->{help}, "toggled on");

        my $three = $TCLASS->new(args => ['-h']);
        ok($three->settings->{help}, "toggled on (short)");
    };

    subtest include => sub {
        local $ENV{PERL5LIB};
        my $one = $TCLASS->new(args => ['--no-lib', '--no-blib', '--no-tlib']);
        ok(!$one->settings->{libs} || !@{$one->settings->{libs}}, "not on by default");

        my $two = $TCLASS->new(args => ['--no-lib', '--no-blib', '--no-tlib', '--include' => 'foo', '-Ibar', '-I' => 'baz', '--include=bat']);
        like(
            $two->settings->{libs},
            bag {
                item qr/foo$/;
                item qr/bar$/;
                item qr/baz$/;
                item qr/bat$/;
                end;
            },
            "Got added libs"
        );
    };

    subtest times => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{times}, "not on by default");

        my $two = $TCLASS->new(args => ['-T']);
        ok($two->settings->{times}, "toggled on");

        my $three = $TCLASS->new(args => ['--times']);
        ok($three->settings->{times}, "toggled on");

        my $four = $TCLASS->new(args => ['--times', '--no-times']);
        ok(!$four->settings->{times}, "toggled off");
    };

    subtest tlib => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{tlib}, "not on by default");

        my $two = $TCLASS->new(args => ['--tlib']);
        ok($two->settings->{tlib}, "toggled on");

        my $three = $TCLASS->new(args => ['--tlib', '--no-tlib']);
        ok(!$three->settings->{tlib}, "toggled off");
    };

    subtest lib => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{lib}, "on by default");

        my $two = $TCLASS->new(args => ['--no-lib']);
        ok(!$two->settings->{lib}, "toggled off");
    };

    subtest blib => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{blib}, "on by default");

        my $two = $TCLASS->new(args => ['--no-blib']);
        ok(!$two->settings->{blib}, "toggled off");
    };

    subtest input => sub {
        my $one = $TCLASS->new(args => []);
        ok(!defined($one->settings->{input}), "none by default");

        $one = $TCLASS->new(args => ['--input', 'foo bar baz']);
        is($one->settings->{input}, 'foo bar baz', "set the input string");
    };

    subtest 'keep-dir' => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{keep_dir}, "not on by default");

        my $two = $TCLASS->new(args => ['-k']);
        ok($two->settings->{keep_dir}, "toggled on");

        my $three = $TCLASS->new(args => ['--keep-dir']);
        ok($three->settings->{keep_dir}, "toggled on");

        my $four = $TCLASS->new(args => ['--keep-dir', '--no-keep-dir']);
        ok(!$four->settings->{keep_dir}, "toggled off");
    };

    subtest 'author-testing' => sub {
        my $one = $TCLASS->new(args => []);
        ok(!defined($one->settings->{env_vars}->{AUTHOR_TESTING}), "not on by default");

        my $two = $TCLASS->new(args => ['-A']);
        ok($two->settings->{env_vars}->{AUTHOR_TESTING}, "toggled on");

        my $three = $TCLASS->new(args => ['--author-testing']);
        ok($three->settings->{env_vars}->{AUTHOR_TESTING}, "toggled on");

        my $four = $TCLASS->new(args => ['--author-testing', '--lib', '--no-author-testing']);
        ok(!$four->settings->{env_vars}->{AUTHOR_TESTING},         "toggled off");
        ok(defined($four->settings->{env_vars}->{AUTHOR_TESTING}), "off, but defined");
    };

    subtest tap => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{use_stream}, "stream by default");

        my $two = $TCLASS->new(args => ['--tap']);
        ok(!$two->settings->{use_stream}, "use tap");

        my $three = $TCLASS->new(args => ['--TAP']);
        ok(!$three->settings->{use_stream}, "use TAP");
    };

    subtest use_stream => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{use_stream}, "stream by default");

        my $two = $TCLASS->new(args => ['--no-stream']);
        ok(!$two->settings->{use_stream}, "use tap");
    };

    subtest fork => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{use_fork}, "fork by default");

        my $two = $TCLASS->new(args => ['--no-fork']);
        ok(!$two->settings->{use_fork}, "no fork");
    };

    # Use is() for these to verify the normalization to 1 and 0
    subtest 'unsafe-inc' => sub {
        subtest undef_var => sub {
            local $ENV{PERL_USE_UNSAFE_INC};

            my $one = $TCLASS->new(args => []);
            is($one->settings->{unsafe_inc}, 1, "unsafe-inc by default");

            my $two = $TCLASS->new(args => ['--no-unsafe-inc']);
            is($two->settings->{unsafe_inc}, 0, "no unsafe-inc");
        };

        subtest true_var => sub {
            local $ENV{PERL_USE_UNSAFE_INC} = 'YES';

            my $one = $TCLASS->new(args => []);
            is($one->settings->{unsafe_inc}, 1, "unsafe-inc");

            my $two = $TCLASS->new(args => ['--no-unsafe-inc']);
            is($two->settings->{unsafe_inc}, 0, "no unsafe-inc");
        };

        subtest false_var => sub {
            local $ENV{PERL_USE_UNSAFE_INC} = '';

            my $one = $TCLASS->new(args => []);
            is($one->settings->{unsafe_inc}, 0, "no unsafe-inc");

            my $two = $TCLASS->new(args => ['--no-unsafe-inc']);
            is($two->settings->{unsafe_inc}, 0, "no unsafe-inc");
        };
    };

    subtest env_vars => sub {
        my $one = $TCLASS->new(args => ['-E', 'FOO=foo', '-EBAR=bar', '--env-var', 'BAZ=baz']);
        is(
            $one->settings->{env_vars},
            hash {
                field FOO => 'foo';
                field BAR => 'bar';
                field BAZ => 'baz';
                etc;
            },
            "Set env vars"
        );
    };

    subtest switch => sub {
        my $one = $TCLASS->new(args => [qw/-S -w -S-t --switch -e=foo=bar/]);
        is(
            $one->settings->{switches},
            [qw/-w -t -e foo=bar/],
            "Set switches"
        );
    };

    subtest clear => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{clear_dir}, "not on by default");

        my $two = $TCLASS->new(args => ['-C']);
        ok($two->settings->{clear_dir}, "toggled on");

        my $three = $TCLASS->new(args => ['--clear']);
        ok($three->settings->{clear_dir}, "toggled on");
    };

    subtest shm => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{use_shm}, "on by default");

        my $two = $TCLASS->new(args => ['--no-shm']);
        ok(!$two->settings->{use_shm}, "toggled off");
    };

    subtest tmpdir => sub {
        if (grep { -d $_ } map { File::Spec->canonpath($_) } '/dev/shm', '/run/shm') {
            my $one = $TCLASS->new(args => []);
            is($one->settings->{tmp_dir}, match qr{^/(run|dev)/shm/?$}, "temp dir in shm");
        }

        my $dir = tempdir(CLEANUP => 1, TMP => 1);

        local $ENV{TMPDIR} = $dir;
        my $two = $TCLASS->new(args => ['--no-shm']);
        is($two->settings->{tmp_dir}, $dir, "temp dir in set by TMPDIR");

        local $ENV{TEMPDIR} = delete $ENV{TMPDIR};
        my $three = $TCLASS->new(args => ['--no-shm']);
        is($three->settings->{tmp_dir}, $dir, "temp dir in set by TEMPDIR");

        delete $ENV{TEMPDIR};
        my $four = $TCLASS->new(args => ['--no-shm']);
        is($four->settings->{tmp_dir}, File::Spec->tmpdir, "system temp dir");
    };

    subtest workdir => sub {
        my $dir = tempdir(CLEANUP => 1, TMP => 1);

        local $ENV{T2_WORKDIR} = $dir;
        my $one = $TCLASS->new(args => []);
        is($one->settings->{dir}, $dir, "Set via env var");

        delete $ENV{T2_WORKDIR};

        delete $ENV{TMPDIR};
        delete $ENV{TEMPDIR};
        my $two = $TCLASS->new(args => []);
        like($two->settings->{dir}, qr{yath-test-$$}, "Generated a directory");
    };

    subtest no_long => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{no_long}, "off by default");

        my $two = $TCLASS->new(args => ['--no-long']);
        ok($two->settings->{no_long}, "toggled on");
    };

    subtest exclude_files => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{exclude_files}, [], "default is an empty array");

        my $two = $TCLASS->new(args => ['-x', 'xxx.t']);
        is($two->settings->{exclude_files}, ['xxx.t'], "excluded a file");

        my $three = $TCLASS->new(args => ['--exclude-file', 'xxx.t']);
        is($three->settings->{exclude_files}, ['xxx.t'], "excluded a file");
    };

    subtest exclude_pattern => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{exclude_patterns}, [], "default is an empty array");

        my $two = $TCLASS->new(args => ['-X', qr/xyz/]);
        is($two->settings->{exclude_patterns}, [qr/xyz/], "excluded a pattern");

        my $three = $TCLASS->new(args => ['--exclude-pattern', qr/xyz/]);
        is($three->settings->{exclude_patterns}, [qr/xyz/], "excluded a pattern");
    };

    subtest run_id => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{run_id}, "default is a timestamp");

        my $two = $TCLASS->new(args => ['--id', 'foo']);
        is($two->settings->{run_id}, 'foo', "set id to foo");

        my $three = $TCLASS->new(args => ['--run-id', 'foo']);
        is($three->settings->{run_id}, 'foo', "set id to foo");
    };

    subtest job_count => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{job_count}, 1, "default is 1");

        my $two = $TCLASS->new(args => ['-j3']);
        is($two->settings->{job_count}, 3, "set to 3");

        my $three = $TCLASS->new(args => ['--jobs', '3']);
        is($three->settings->{job_count}, 3, "set to 3");

        my $four = $TCLASS->new(args => ['--job-count', '3']);
        is($four->settings->{job_count}, 3, "set to 3");
    };

    subtest preload => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{preload}, undef, "No preloads");

        my $two = $TCLASS->new(args => ['-PScalar::Util', '--preload', 'List::Util']);
        is($two->settings->{preload}, ['Scalar::Util', 'List::Util'], "Added preload");

        my $three = $TCLASS->new(args => ['-PScalar::Util', '--preload', 'List::Util', '--no-preload', '-PData::Dumper']);
        is($three->settings->{preload}, ['Data::Dumper'], "Added preload after canceling previous ones");
    };

    subtest plugin => sub {
        my $one = $TCLASS->new(args => []);
        is($one->plugins, [], "No plugins");

        @INC = ('t/lib', @INC);

        my $two = $TCLASS->new(args => ['-pTest', '--plugin', 'TestNew']);
        is($two->plugins, ['App::Yath::Plugin::Test', object { prop blessed => 'App::Yath::Plugin::TestNew' }], "Added plugin");

        my $three = $TCLASS->new(args => ['-pFail', '--plugin', 'Fail', '--no-plugins', '-pTest']);
        is($three->plugins, ['App::Yath::Plugin::Test'], "Added plugin after canceling previous ones");
    };

    subtest dummy => sub {
        local $ENV{T2_HARNESS_DUMMY} = 0;
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{dummy}, "not dummy by default");

        $ENV{T2_HARNESS_DUMMY} = 1;
        my $two = $TCLASS->new(args => []);
        ok($two->settings->{dummy}, "dummy by default with env var");

        $ENV{T2_HARNESS_DUMMY} = 0;
        my $three = $TCLASS->new(args => ['-D']);
        ok($three->settings->{dummy}, "dummy turned on");

        my $four = $TCLASS->new(args => ['--dummy']);
        ok($four->settings->{dummy}, "dummy turned on");
    };

    subtest load => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{load}, "no loads by default");

        my $two = $TCLASS->new(args => ['-mFoo', '-m', 'Bar', '--load', 'Baz', '--load-module', 'Bat']);
        is($two->settings->{load}, [qw/Foo Bar Baz Bat/], "Added some loads");
    };

    subtest load_import => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{load_import}, "no loads by default");

        my $two = $TCLASS->new(args => ['-MFoo', '-M', 'Bar=foo,bar,baz', '--loadim', 'Baz', '--load-import', 'Bat']);
        is($two->settings->{load_import}, ['Foo', 'Bar=foo,bar,baz', 'Baz', 'Bat'], "Added some loads");
    };

    subtest cover => sub {
        local $INC{'Devel/Cover.pm'} = 1;
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{cover},       "no cover by default");
        ok($one->settings->{use_fork},     "fork allowed by default");
        ok(!$one->settings->{load_import}, "no loads by default");

        my $two = $TCLASS->new(args => ['--cover']);
        ok($two->settings->{cover}, "cover turned on");
        is($two->settings->{use_fork}, 0, "fork disabled");
        is(
            $two->settings->{load_import},
            ['Devel::Cover=-silent,1,+ignore,^t/,+ignore,^t2/,+ignore,^xt,+ignore,^test.pl'],
            "Added Devel::Cover to loads"
        );
    };

    subtest event_timeout => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{event_timeout}, 60, "Default event timeout is 60");

        my $two = $TCLASS->new(args => ['--et', '30']);
        is($two->settings->{event_timeout}, 30, "Changed to 30");

        my $three = $TCLASS->new(args => ['--event_timeout', '25']);
        is($three->settings->{event_timeout}, 25, "Changed to 25");
    };

    subtest post_exit_timeout => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{post_exit_timeout}, 15, "Default event timeout is 15");

        my $two = $TCLASS->new(args => ['--pet', '30']);
        is($two->settings->{post_exit_timeout}, 30, "Changed to 30");

        my $three = $TCLASS->new(args => ['--post-exit-timeout', '25']);
        is($three->settings->{post_exit_timeout}, 25, "Changed to 25");
    };

    subtest logging => sub {
        my $dir = tempdir(CLEANUP => 1, TMP => 1);
        my $old = cwd();
        chdir($dir);

        subtest log_file => sub {
            my $one = $TCLASS->new(args => []);
            ok(!$one->settings->{log_file}, "no log file by default");

            my $two = $TCLASS->new(args => ['--log']);
            my $run_id = $two->settings->{run_id};
            like($two->settings->{log_file}, qr{test-logs/\d{4}-\d{2}-\d{2}~\d{2}:\d{2}:\d{2}~\Q$run_id\E~\Q$$\E\.jsonl$}, "default log file");
            ok(-d 'test-logs', "Created test-logs dir");
        };

        subtest bzip2_log => sub {
            my $one = $TCLASS->new(args => []);
            ok(!$one->settings->{bzip2_log}, "no log by default");

            for ('-B', '--bz2', '--bzip2-log') {
                my $two = $TCLASS->new(args => [$_]);
                ok($two->settings->{bzip2_log}, "bzip2 logging");
                ok($two->settings->{log},       "logging turned on");
            }
        };

        subtest gzip_log => sub {
            my $one = $TCLASS->new(args => []);
            ok(!$one->settings->{gzip_log}, "no log by default");

            for ('-G', '--gz', '--gzip-log') {
                my $two = $TCLASS->new(args => [$_]);
                ok($two->settings->{gzip_log}, "gzip logging");
                ok($two->settings->{log},      "logging turned on");
            }
        };

        subtest log => sub {
            my $one = $TCLASS->new(args => []);
            ok(!$one->settings->{log}, "no log by default");

            my $two = $TCLASS->new(args => ['-L']);
            ok($two->settings->{log}, "logging enabled");

            my $three = $TCLASS->new(args => ['--log']);
            ok($three->settings->{log}, "logging enabled");
        };

        chdir($old);
    };

    subtest color => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{color}, "color by default");

        my $two = $TCLASS->new(args => ['--no-color']);
        ok(!$two->settings->{color}, "color turned off");
    };

    subtest quiet => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{quiet}, "quiet off by default");

        my $two = $TCLASS->new(args => ['--quiet']);
        ok($two->settings->{quiet}, "quiet turned on");
    };

    subtest renderer => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{renderer}, '+Test2::Harness::Renderer::Formatter', "Default renderer");

        my $two = $TCLASS->new(args => ['--renderer', 'foo']);
        is($two->settings->{renderer}, 'foo', "set renderer");
    };

    subtest formatter => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{formatter}, '+Test2::Formatter::Test2', "Default formatter");

        my $two = $TCLASS->new(args => ['--formatter', 'foo']);
        is($two->settings->{formatter}, 'foo', "set formatter");
    };

    subtest verbose => sub {
        my $one = $TCLASS->new(args => []);
        is($one->settings->{verbose}, 0, "Verbose is off by default");

        my $two = $TCLASS->new(args => ['-v']);
        is($two->settings->{verbose}, 1, "Verbose is on by default");

        my $three = $TCLASS->new(args => ['-vvv']);
        is($three->settings->{verbose}, 3, "Verbose is higher now");
    };

    subtest show_job_end => sub {
        my $one = $TCLASS->new(args => []);
        ok($one->settings->{show_job_end}, "show_job_end is on by default");

        my $two = $TCLASS->new(args => ['--no-show-job-end']);
        ok(!$two->settings->{show_job_end}, "show_job_end turned off");
    };

    subtest show_job_info => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{show_job_info}, "show_job_info is off by default");

        my $two = $TCLASS->new(args => ['--show-job-info']);
        ok($two->settings->{show_job_info}, "show_job_info turned on");

        my $three = $TCLASS->new(args => ['-vv']);
        ok($three->settings->{show_job_info}, "show_job_info turned on by double verbose mode");
    };

    subtest show_job_launch => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{show_job_launch}, "show_job_launch is off by default");

        my $two = $TCLASS->new(args => ['--show-job-launch']);
        ok($two->settings->{show_job_launch}, "show_job_launch turned on");

        my $three = $TCLASS->new(args => ['-vv']);
        ok($three->settings->{show_job_launch}, "show_job_launch turned on by double verbose mode");
    };

    subtest show_run_info => sub {
        my $one = $TCLASS->new(args => []);
        ok(!$one->settings->{show_run_info}, "show_run_info is off by default");

        my $two = $TCLASS->new(args => ['--show-run-info']);
        ok($two->settings->{show_run_info}, "show_run_info turned on");

        my $three = $TCLASS->new(args => ['-vv']);
        ok($three->settings->{show_run_info}, "show_run_info turned on by double verbose mode");
    };
};

subtest pre_parse_args => sub {
    my ($opts, $list, $pass, $plugins);

    ($opts, $list, $pass, $plugins) = $CLASS->pre_parse_args(
        [
            '-x',
            '--longer' => 'arg',
            qw/foo bar baz/,
            '-pFoo',
            '--plugin' => 'Bar',
            '-p=Baz',
            '--plugin=Bat',
            '--',
            '-p' => 'uhg',
            'bleh',
            'blotch',
            '::',
            'pear',
            'apple',
            'bananananan',
            '-xyz',
        ]
    );
    is($opts, ['-x', '--longer' => 'arg', qw/foo bar baz/], "Got opts");
    is($list, ['-p', 'uhg', 'bleh', 'blotch'], "Got list");
    is($pass, ['pear', 'apple', 'bananananan', '-xyz'], "Got args to pass");
    is($plugins, [qw/Foo Bar Baz Bat/], "Got plugins");

    ($opts, $list, $pass, $plugins) = $CLASS->pre_parse_args(
        [
            '-x',
            '--longer' => 'arg',
            qw/foo bar baz/,
            '-pFoo',
            '--plugin' => 'Bar',
            '-p=Baz',
            '--no-plugins', # <---- this is what we are testing now
            '--plugin=Bat',
            '--',
            '-p' => 'uhg',
            'bleh',
            'blotch',
            '::',
            'pear',
            'apple',
            'bananananan',
            '-xyz',
        ]
    );
    is($opts, ['-x', '--longer' => 'arg', qw/foo bar baz/], "Got opts");
    is($list, ['-p', 'uhg', 'bleh', 'blotch'], "Got list");
    is($pass, ['pear', 'apple', 'bananananan', '-xyz'], "Got args to pass");
    is($plugins, [qw/Bat/], "Got only 1 plugin");

    ($opts, $list, $pass, $plugins) = $CLASS->pre_parse_args(
        [
            '-x',
            '--longer' => 'arg',
            qw/foo bar baz/,
            '-pFoo',
            '--plugin' => 'Bar',
            '-p=Baz',
            '--plugin=Bat',
            '::',
            'pear',
            'apple',
            'bananananan',
            '-xyz',
        ]
    );
    is($opts, ['-x', '--longer' => 'arg', qw/foo bar baz/], "Got opts");
    is($list, [], "Got empty list");
    is($pass, ['pear', 'apple', 'bananananan', '-xyz'], "Got args to pass");
    is($plugins, [qw/Foo Bar Baz Bat/], "Got plugins");
};

subtest parse_args => sub {
    my $list;

    require App::Yath::Plugin::Test;
    require App::Yath::Plugin::TestNew;
    App::Yath::Plugin::Test->CLEAR_CALLS;
    App::Yath::Plugin::TestNew->CLEAR_CALLS;

    my $control = mock $TCLASS;

    $control->override(has_display => sub { 1 });
    $control->override(has_jobs    => sub { 1 });
    $control->override(has_logger  => sub { 1 });
    $control->override(has_runner  => sub { 1 });
    $control->override(handle_list_args => sub { $list = pop });

    my $one = $TCLASS->new(args => [
        '-x' => 'foo.t',
        '-p' => 'Test',
        '-p' => '+App::Yath::Plugin::TestNew',
        '-E' => 'FOO=123',
        '-v',
        '-B',
        '--no-fork',
        'bar.t',
        't',
        '--',
        'baz.t',
        'bat.t',
        '--foo',
        '::',
        '-arg1' => 1,
        '-arg2' => 2,
    ]);
    my $settings = $one->settings;

    is($list, ['bar.t', 't', 'baz.t', 'bat.t', '--foo'], "Got list args from both before and after --");
    is($one->plugins, ['App::Yath::Plugin::Test', object { prop blessed => 'App::Yath::Plugin::TestNew' }], "got plugins");
    is($settings->{exclude_files}, ['foo.t'], "Excluded foo.t");
    is($settings->{env_vars}->{FOO}, 123, "Set an env var (used an Action)");
    is($settings->{verbose}, 1, "Turned on verbose (set via field)");
    ok($settings->{log}, "turned on logging");
    ok(!$settings->{use_fork}, "turned off forking");
    is($settings->{pass}, [qw/-arg1 1 -arg2 2/], "Got pass args");

    is(
        App::Yath::Plugin::Test->GET_CALLS,
        {
            options   => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($settings)]],
            pre_init  => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($settings)]],
            post_init => [['App::Yath::Plugin::Test', exact_ref($one), exact_ref($settings)]],
        },
        "Called correct plugin methods on class",
    );

    is(
        App::Yath::Plugin::TestNew->GET_CALLS,
        {
            options   => [[exact_ref($one->plugins->[1]), exact_ref($one), exact_ref($settings)]],
            pre_init  => [[exact_ref($one->plugins->[1]), exact_ref($one), exact_ref($settings)]],
            post_init => [[exact_ref($one->plugins->[1]), exact_ref($one), exact_ref($settings)]],
        },
        "Called correct plugin methods on instance",
    );
};

subtest inject_signal_handlers => sub {
    local $SIG{INT} = 'IGNORE';
    local $SIG{TERM} = 'IGNORE';

    my $one = $TCLASS->new(args => []);

    $one->inject_signal_handlers;
    isnt($SIG{INT}, 'IGNORE', "Not ignoring SIGINT anymore");
    isnt($SIG{TERM}, 'IGNORE', "Not ignoring SIGINT anymore");
    ok(!$one->signal, "no signal seen yet");

    is(dies { kill('INT', $$); sleep 10 }, "Cought SIGINT, Attempting to shut down cleanly...\n", "SIGINT threw exception");
    is($one->signal, 'INT', "Recorded SIGINT");

    is(dies { kill('TERM', $$); sleep 10 }, "Cought SIGTERM, Attempting to shut down cleanly...\n", "SIGTERM threw exception");
    is($one->signal, 'TERM', "Recorded SIGTERM");
};

subtest loggers => sub {
    my $control = mock $TCLASS;
    $control->override(has_logger => sub { 1 });
    $control->override(has_jobs => sub { 1 });

    my $one = $TCLASS->new(args => []);
    is($one->loggers, [], "No loggers");

    my $two = $TCLASS->new(args => ['--log']);
    is(
        $two->loggers, [
            object {
                prop blessed => 'Test2::Harness::Logger::JSONL';
                call fh => meta { prop reftype => 'GLOB' };
            },
        ],
        "Got a logger with a plain file handle"
    );

    my $three = $TCLASS->new(args => ['-B']);
    is(
        $three->loggers, [
            object {
                prop blessed => 'Test2::Harness::Logger::JSONL';
                call fh => object { prop blessed => 'IO::Compress::Bzip2' };
            },
        ],
        "Got a logger with a bz2 file handle"
    );

    my $four = $TCLASS->new(args => ['-G']);
    is(
        $four->loggers, [
            object {
                prop blessed => 'Test2::Harness::Logger::JSONL';
                call fh => object { prop blessed => 'IO::Compress::Gzip' };
            },
        ],
        "Got a logger with a gz file handle"
    );
};

done_testing;

__END__

sub renderers {
    my $self      = shift;
    my $settings  = $self->{+SETTINGS};
    my $renderers = [];

    return $renderers if $settings->{quiet};

    my $r = $settings->{renderer} or return $renderers;

    if ($r eq '+Test2::Harness::Renderer::Formatter' || $r eq 'Formatter') {
        require Test2::Harness::Renderer::Formatter;

        my $formatter = $settings->{formatter} or die "No formatter specified.\n";
        my $f_class;

        if ($formatter eq '+Test2::Formatter::Test2' || $formatter eq 'Test2') {
            require Test2::Formatter::Test2;
            $f_class = 'Test2::Formatter::Test2';
        }
        else {
            $f_class = fqmod('Test2::Formatter', $formatter);
            my $file = pkg_to_file($f_class);
            require $file;
        }

        push @$renderers => Test2::Harness::Renderer::Formatter->new(
            show_job_info   => $settings->{show_job_info},
            show_run_info   => $settings->{show_run_info},
            show_job_launch => $settings->{show_job_launch},
            show_job_end    => $settings->{show_job_end},
            formatter       => $f_class->new(verbose => $settings->{verbose}, color => $settings->{color}),
        );
    }
    elsif ($settings->{formatter}) {
        die "The formatter option is only available when the 'Formatter' renderer is in use.\n";
    }
    else {
        my $r_class = fqmod('Test2::Harness::Renderer', $r);
        require $r_class;
        push @$renderers => $r_class->new(verbose => $settings->{verbose}, color => $settings->{color});
    }

    return $renderers;
}


sub usage_opt_order {
    my $self = shift;

    my $idx = 1;
    my %lookup = map {($_ => $idx++)} $self->section_order;

    #<<< no-tidy
    return sort {
          ($lookup{$a->{section}} || 99) <=> ($lookup{$b->{section}} || 99)  # Sort by section first
            or ($a->{long_desc} ? 2 : 1) <=> ($b->{long_desc} ? 2 : 1)       # Things with long desc go to bottom
            or      lc($a->{usage}->[0]) cmp lc($b->{usage}->[0])            # Alphabetical by first usage example
            or       ($a->{field} || '') cmp ($b->{field} || '')             # By field if present
    } grep { $_->{section} } @{$self->my_opts};
    #>>>
}

sub usage_pod {
    my $in = shift;
    my $name = $in->name;

    my @list = $in->usage_opt_order;

    my $out = "\n=head1 COMMAND LINE USAGE\n";

    my @cli_args = $in->cli_args;
    @cli_args = ('') unless @cli_args;

    for my $args (@cli_args) {
        $out .= "\n    \$ yath $name [options]";
        $out .= " $args" if $args;
        $out .= "\n";
    }

    my $section = '';
    for my $opt (@list) {
        my $sec = $opt->{section};
        if ($sec ne $section) {
            $out .= "\n=back\n" if $section;
            $section = $sec;
            $out .= "\n=head2 $section\n";
            $out .= "\n=over 4\n";
        }

        for my $way (@{$opt->{usage}}) {
            my @parts = split /\s+-/, $way;
            my $count = 0;
            for my $part (@parts) {
                $part = "-$part" if $count++;
                $out .= "\n=item $part\n"
            }
        }

        for my $sum (@{$opt->{summary}}) {
            $out .= "\n$sum\n";
        }

        if (my $desc = $opt->{long_desc}) {
            chomp($desc);
            $out .= "\n$desc\n";
        }
    }

    $out .= "\n=back\n";

    return $out;
}

sub usage {
    my $self = shift;
    my $name = $self->name;

    my @list = $self->usage_opt_order;

    # Get the longest 'usage' item's length
    my $ul = max(map { length($_) } map { @{$_->{usage}} } @list);

    my $section = '';
    my @options;
    for my $opt (@list) {
        my $sec = $opt->{section};
        if ($sec ne $section) {
            $section = $sec;
            push @options => "  $section:";
        }

        my @set;
        for (my $i = 0; 1; $i++) {
            my $usage = $opt->{usage}->[$i]   || '';
            my $summ  = $opt->{summary}->[$i] || '';
            last unless length($usage) || length($summ);

            my $line = sprintf("    %-${ul}s    %s", $usage, $summ);

            if (length($line) > 80) {
                my @words = grep { $_ } split /(\s+)/, $line;
                my @lines;
                while (@words) {
                    my $prefix = @lines ? (' ' x ($ul + 8)) : '';
                    my $length = length($prefix);

                    shift @words while @lines && @words && $words[0] =~ m/^\s+$/;
                    last unless @words;

                    my @line;
                    while (@words && (!@line || 80 >= $length + length($words[0]))) {
                        $length += length($words[0]);
                        push @line => shift @words;
                    }
                    push @lines => $prefix . join '' => @line;
                }

                push @set => join "\n" => @lines;
            }
            else {
                push @set => $line;
            }
        }
        push @options => join "\n" => @set;

        if (my $desc = $opt->{long_desc}) {
            chomp($desc);

            my @words = grep { $_ } split /(\s+)/, $desc;
            my @lines;
            my $size = 0;
            while (@words && $size != @words) {
                $size = @words;
                my $prefix = '        ';
                my $length = 8;

                shift @words while @lines && @words && $words[0] =~ m/^\s+$/;
                last unless @words;

                my @line;
                while (@words && (!@line || 80 >= $length + length($words[0]))) {
                    $length += length($words[0]);
                    push @line => shift @words;
                }
                push @lines => $prefix . join '' => @line;
            }

            push @options => join("\n" => @lines) . "\n";
        }
    }

    chomp(my @cli_args    = $self->cli_args);
    chomp(my $description = $self->description);

    my $head_common = "$0 $name [options]";
    my $header = join(
        "\n",
        "Usage: $head_common " . shift(@cli_args),
        map { "       $head_common $_" } @cli_args
    );

    my $options = join "\n\n" => @options;

    my $usage = <<"    EOT";

$header

$description

OPTIONS:

$options

    EOT

    return $usage;
}


