use Mojolicious::Lite -signatures;

any '/*' => sub ($c) {
    $c->render(text => '200',);
};

app->start;
