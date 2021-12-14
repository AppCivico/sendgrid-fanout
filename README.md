# Fan-out Event Webhook for SendGrid

With this repository you can send Event Webhook from SendGrid to multiple services.

You can filter by some key/value on each event, and send to one or more remote services.

This is written using Mojolicious, after an event is received, the raw request is saved into the disk, outgoing requests
are started asynchronous and the 200 response is sent back to SendGrid ASAP.

If the outgoing requests fail (network or non-success HTTP responses), it will be queued for retry later and by the health-check
endpoint.

**If the process crash during the initial in-flight request, the error is not written to the disk yet, so events can be lost.**

# Usage

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
Similarly, the only matching scheme now is "eq".

You should do further filtering on your application.

#