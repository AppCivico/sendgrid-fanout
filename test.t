use Mojo::Base -strict;

use Test::Mojo;
use Test::More;
use JSON;
use Mojo::File qw(curfile tempdir tempfile);

my $backend  = Test::Mojo->new(curfile->sibling('mock-server.pl'));
my $endpoint = $backend->ua->server->nb_url;

$ENV{ERROR_DIR} = tempdir();
mkdir($ENV{ERROR_DIR});
$ENV{TRACE_DIR} = tempdir();
mkdir($ENV{TRACE_DIR});

$ENV{CONFIG_FILE} = tempfile();
Mojo::File->new($ENV{CONFIG_FILE})->spurt(
    to_json(
        [
            {
                lookup_key   => 'app',
                lookup_value => 'foobar',
                send_to      => [
                    $endpoint . 'req-ok',
                    $endpoint . 'req-2-ok',
                ]
            },
            {
                lookup_key   => 'app',
                lookup_value => 'err',
                send_to      => [$endpoint . 'req-err']
            },
        ]
    )
);

my $t = Test::Mojo->new(curfile->sibling('server.pl'));
$t->get_ok('/ping')->status_is(200)->content_is('pong');
$t->get_ok('/health-check')->status_is(200)->content_is('ok');

$t->post_ok(
    '/',
    json => [
        {},
        {ignored => 1},
        {app     => 'foobar'},
        {app     => 'err', 'sg_event_id' => '1234'},

    ]
)->status_is(200, 'posted');

my $stats = $backend->get_ok('/stats')->tx->res->json;
is_deeply(
    $stats,
    {
        'POST/req-2-ok' => 1,
        'POST/req-ok'   => 1,
        'POST/req-err'  => 1,
    },
    'ok for now'
);
$t->get_ok('/health-check')->status_is(200)->content_is('Failed requested: 1');

$stats = $backend->get_ok('/stats')->tx->res->json;
is_deeply(
    $stats,
    {
        'POST/req-2-ok' => 1,
        'POST/req-ok'   => 1,
        'POST/req-err'  => 2,
    },
    'ok for now'
);

$backend->post_ok('/disable-err')->status_is(200);

# this will queue the delete onto ioloop, need to make the request again to reflect the request
$t->get_ok('/health-check')->status_is(200)->content_is('ok');

$stats = $backend->get_ok('/stats')->tx->res->json;
is_deeply(
    $stats,
    {
        'POST/req-2-ok' => 1,
        'POST/req-ok'   => 1,
        'POST/req-err'  => 3,
    },
    'ok for now'
);

done_testing();
