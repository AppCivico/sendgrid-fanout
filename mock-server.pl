use Mojolicious::Lite;
my $stats = {};

my $should_error = 1;
get '/stats' => sub {
    my ($c) = @_;
    return $c->render(json => $stats);
};

post '/disable-err' => sub {
    my ($c) = @_;
    $should_error = 0;
    return $c->render(json => []);
};

any '/*uri' => sub {
    my ($c) = @_;

    my $key = join('/', uc $c->req->method, $c->stash('uri'));
    $stats->{$key}++;

    if ($key eq 'POST/req-err' && $should_error) {
        $c->res->code(400);
        return $c->render(text => 'err');
    }

    return $c->render(text => 'ok');
};
app->start;
