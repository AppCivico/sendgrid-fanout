# Fan-out Event Webhook for SendGrid

With this repository you can send Event Webhook from SendGrid to multiple services.

This is written using Mojolicious, after an event is received, the raw request is saved on disk, outgoing requests
are started asynchronous and *200 OK* response is sent back to SendGrid ASAP (+ 1200/s per worker is expected on modern hardware).

If the outgoing requests fail (either Network or non-success HTTP responses), it will be written to disk for later processing
by the health-check endpoint. *If the process crash during the initial in-flight request, the error is not written to the disk yet, so for now individual events can be lost.*

# Why

SendGrid only support one Webhook per Account. SubAccounts are limited to `pro` plan.

**Each one of your services should process bounces/spam-reports and alert their users by some other way other than e-mail**
**(banner on web/app on logged users, SMS, WhatsApp, etc).**

To select which services will receive the event, you can use **one** SendGrid event field as a condition. [See limitations.](#Limitations)

If you integrate with SendGrid SMTP, you can include `X-SMTPAPI` encoded with pure-ASCII JSON, using `unique_args`. Sendgrid API v3 uses `custom_args` to identify your application. [Read SendGrid docs here](https://docs.sendgrid.com/for-developers/sending-email/building-an-x-smtpapi-header).


# Usage

    cp .env.sample .env
    cp sample.config.json config.json
    # edit .env to your needs
    # edit config.json to your needs
    docker-compose up --build


    docker restart sendgrid_fanout_www

    docker rm sendgrid_fanout_www

## Envs

DISABLE_TRACE_DIR - disable logging of raw requests
TRACE_DIR - directory to log raw requests
ERROR_DIR - directory to keep temporary errors requests to be retried
AUTO_START_DIR - enable attempt to create directory on if not exists
CONFIG_FILE - where to read config json file

# Testing

run `$ prove -v test.pl`.

# Endpoints

`GET /health-check` - should be called each minute by monitoring tool.

- Returns `200 OK` with `ok` if everything is fine.
- Returns `200 OK` with `Failed requested: XX` if upstream is having a bad time.
- Returns `400 Bad Request` with `server busy` if this endpoint cannot be locked for processing after 60 seconds.

`GET /ping` - Test if application is alive

- Returns `200 OK` with `pong`

`POST /` - Eats the SendGrid JSON

- Returns `200 OK` with `ok`
- Returns `400 OK` with `not defined or not object` if json cannot be parsed or if the first level is not an array.




# Configuration

Copy `sample.config.json` to `config.json` and edit the fields:

    [
        {
            "lookup_key": "email",
            "lookup_value": "some@email.com",
            "send_to": [
                "http://mautic-instance.com/mailer/sendgrid_api/callback",
                "http://keen.io/path/to/endpoint"
            ]
        },
        {
            "lookup_key": "app",
            "lookup_value": "foobar",
            "send_to": [
                "https://another-host/path/to/endpoint"
            ]
        }
    ]

Given above configuration, if you receive the following events from SendGrid:

    [
        {
            "attempt": "1",
            "email": "some@email.com",
            "event": "deferred",
            "mc_stats": "singlesend",
            "phase_id": "send",
            "response": "unable to get mx info: ...",
            "send_at": "1639468221",
            "sg_event_id": "AAAAAAAAAAAAAAA",
            "sg_message_id": "oirD2QEKQYKs6NGAOpCqiQ.filterdrecv-7bc86b958d-j46hl-1-61B84CF4-21.0",
            "sg_template_id": "d-355ddad65f7f43f2bc7f1b8536401415",
            "sg_template_name": "Version 2021-12-14T07:46:44.368Z",
            "singlesend_id": "fc59bd25-5cb1-11ec-a05d-f2509ce774e9",
            "singlesend_name": "Untitled Single Send",
            "smtp-id": "<oirD2QEKQYKs6NGAOpCqiQ@ismtpd0211p1mdw1.sendgrid.net>",
            "template_hash": "4d47ef12c8fbae877a8441d800cc9dc151e1edf6eb9fde9a47abcfc2e6975c4b",
            "template_id": "d-355ddad65f7f43f2bc7f1b8536401415",
            "template_version_id": "8ceb52d5-e5aa-4388-8184-f8107ec42e88",
            "timestamp": 1639468306,
            "tls": 0
        },
        {
            "app": "foobar",
            "attempt": "1",
            "email": "some@email.com",
            "event": "deferred",
            "mc_stats": "singlesend",
            "phase_id": "send",
            "response": "foobar",
            "send_at": "1639468221",
            "sg_event_id": "BBBBBBBBBBBB",
            "sg_message_id": "oirD2QEKQYKs6NGAOpCqiQ.filterdrecv-7bc86b958d-j46hl-1-61B84CF4-21.0",
            "sg_template_id": "d-355ddad65f7f43f2bc7f1b8536401415",
            "sg_template_name": "Version 2021-12-14T07:46:44.368Z",
            "singlesend_id": "fc59bd25-5cb1-11ec-a05d-f2509ce774e9",
            "singlesend_name": "Untitled Single Send",
            "smtp-id": "<oirD2QEKQYKs6NGAOpCqiQ@ismtpd0211p1mdw1.sendgrid.net>",
            "template_hash": "4d47ef12c8fbae877a8441d800cc9dc151e1edf6eb9fde9a47abcfc2e6975c4b",
            "template_id": "d-355ddad65f7f43f2bc7f1b8536401415",
            "template_version_id": "8ceb52d5-e5aa-4388-8184-f8107ec42e88",
            "timestamp": 1639468306,
            "tls": 0
        }
    ]

This application will generate 3 POST requests, 2 requests for the first event (`sg_event_id=AAAAAAAAAAAAAAA`) to `http://mautic-instance.com/mailer/sendgrid_api/callback` and `http://keen.io/path/to/endpoint` and the other event to `https://another-host/path/to/endpoint`


## Limitations

For performance reasons, it skip the event matching after the first match is found.
Similarly, the only matching scheme now is "equal".

You should do further filtering on your application.
