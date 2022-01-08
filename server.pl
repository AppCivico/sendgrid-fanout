use Mojolicious::Lite -signatures;
use JSON;
use Digest::MD5 qw/md5_hex/;
use Encode;
use Mojo::URL;
use Mojo::File qw/path/;
use POSIX qw(strftime);
use Lock::File qw(lockfile);
use Mojo::AsyncAwait;

sub is_array_ref {
    return ref(shift()) eq 'ARRAY' ? 1 : 0;
}
app->log->level('debug');

$ENV{MOJO_HYPNOTOAD_WORKERS} = 1 if !$ENV{MOJO_HYPNOTOAD_WORKERS} || $ENV{MOJO_HYPNOTOAD_WORKERS} < 0;
app->log->debug("v2");
app->config(hypnotoad => {listen => ['http://*:8080'], workers => $ENV{MOJO_HYPNOTOAD_WORKERS}});

my $error_dir = $ENV{ERROR_DIR};
die "env ERROR_DIR is not defined" if !$error_dir;
if ($ENV{AUTO_START_DIR} && !-d $error_dir) {
    mkdir($error_dir) or die "cannot create $error_dir $!";
}
die "$error_dir is not an directory" unless -d $error_dir;


my $disble_trace = $ENV{DISABLE_TRACE_DIR};
my $trace_dir = $ENV{TRACE_DIR};
if (!$disble_trace){
    die "env TRACE_DIR is not defined" if !$trace_dir;
    if ($ENV{AUTO_START_DIR} && !-d $trace_dir) {
        mkdir($trace_dir) or die "cannot create $trace_dir $!";
    }
    die "$trace_dir is not an directory" unless -d $trace_dir;
}
app->log->debug("reading config file...");

my $config = $ENV{CONFIG_FILE} ? Mojo::File->new($ENV{CONFIG_FILE})->slurp : app->home->rel_file('config.json')->slurp;
app->log->debug("config: $config");
$config = eval { from_json($config) };
if (!$config) {
    die "config.json is invalid: $@";
}


app->helper(
    record_error => sub {
        my ($c, $req_id, $url, $events) = @_;
        my $hash = $url;
        foreach my $event (@{$events}) {
            $hash .= exists $event->{sg_event_id} ? $event->{sg_event_id} : "$event";
        }
        $hash = md5_hex(encode_utf8($hash));

        my $file_name = Mojo::URL->new($url)->host;

        $file_name =~ s/[^A-Z-\.]+//gi;
        $file_name .= ".$hash.json";

        $file_name =~ s/^\.+//;

        $c->log->debug("writing error to $error_dir/$file_name");

        Mojo::File->new("$error_dir/$file_name")->spurt(
            to_json(
                {
                    req_id => $req_id,
                    epoch  => time(),
                    url    => $url,
                    events => $events,
                }
            )
        );
        return 1;
    }
);

app->helper(
    record_event => sub {
        my ($c, $req_id, $json) = @_;

        return 1 if $disble_trace;

        my $file_name = strftime('%F', gmtime()) . '-' . time() . ".$req_id.json";

        $c->log->debug("saving event to $trace_dir/$file_name");

        Mojo::File->new("$trace_dir/$file_name")->spurt(to_json($json));
        return 1;
    }
);

app->helper(
    retry_execution_p => sub {
        my ($c, $file_name) = @_;

        $c->log->debug("retrying $file_name...");
        my $json = Mojo::File->new($file_name)->slurp;
        my $obj  = from_json($json);

        my $url = $obj->{url};

        my $promise = $c->ua->post_p($url, json => $obj->{events})->then(
            sub ($tx) {
                $c->log->debug("-> $url: Response code " . $tx->res->code);
                if (!$tx->res->is_success) {
                    $c->log->error("-> $url: requested failed again...");
                }
                else {
                    $c->log->debug("removing $file_name...");
                    $file_name->remove;
                }

            }
        )->catch(
            sub ($err) {
                $c->log->error("-> $url: failed to connect: $err");
            }
        );

        return $promise;
    }
);

post '/' => sub ($c) {

    my $events = $c->req->json;

    if (!defined $events || !is_array_ref($events)) {
        return $c->render(text => 'not defined or not object');
    }

    my $req_id = $c->req->request_id;
    $c->record_event($req_id, $events);

    my $events_by_domain = {};

  EV:
    foreach my $event (@{$events}) {

        foreach my $test (@{$config}) {
            return $c->render(text => 'invalid object inside events array') if ref $test ne 'HASH';
            next unless exists $test->{send_to} && exists $test->{lookup_key} && exists $test->{lookup_value};

            if (exists $event->{$test->{lookup_key}} && $event->{$test->{lookup_key}} eq $test->{lookup_value}) {
                foreach my $send_to (@{$test->{send_to}}) {
                    push @{$events_by_domain->{$send_to}}, $event;
                }
                next EV;
            }
        }

    }

    while (my ($url, $events) = each %$events_by_domain) {

        $c->log->debug("-> $url: sending events...");

        $c->ua->post_p($url, json => $events)->then(
            sub ($tx) {
                $c->log->debug("-> $url: Response code " . $tx->res->code);

                if (!$tx->res->is_success) {
                    $c->log->error("-> $url: requested failed");

                    $c->record_error($req_id, $url, $events);
                }
            }
        )->catch(
            sub ($err) {
                $c->log->error("-> $url: failed to connect: $@");
                $c->record_error($req_id, $url, $events);
            }
        );
    }

    $c->render(text => 'ok');
};

get '/health-check' => async sub ($c) {

    my $started    = time();
    my $collection = path($error_dir)->list();

    my $lock = eval { lockfile('/tmp/sendgrid-fanout-health-check.lock', {blocking => 1, timeout => 60}) };

    if (!$lock) {
        return $c->render(text => 'server busy', status => 400);
    }

    if ($collection->size == 0) {
        return $c->render(text => 'ok');
    }

    # escolhe 10 requests para executar em 30 segundos
    my $repair = $collection->shuffle->head(10)->to_array;
    foreach my $error_file (@{$repair}) {
        last if time() - $started > 30;
        await $c->retry_execution_p($error_file);
    }

    # update status
    $collection = path($error_dir)->list();

    if ($collection->size > 0) {
        return $c->render(text => 'Failed requested: ' . $collection->size);
    }

    return $c->render(text => 'ok');
};

get '/ping' => sub ($c) {
    $c->render(text => 'pong');
};

any '/' => sub ($c) {
    $c->render(text => 'Method not allowed', status => 405);
};

any '/*' => sub ($c) {
    $c->render(text => 'endpoint does not exists', status => 404);
};

app->start;
