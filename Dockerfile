# based on https://github.com/curioustechnoid/mojolicious/blob/main/Docker/Dockerfile
# Using Alphine linux as base image
FROM alpine:3.13.5

# Expose all default Mojolicious Ports
EXPOSE 8080 3000

# Create app group and user
RUN addgroup -S app && adduser -S app -G app

# Creating mojolicious directory for storing the src files
RUN mkdir -p /src \
    && chmod -R 755 /src \
    && chown -R app:app /src

# Install all necessary packages required by Mojolicious
RUN apk update && apk add --no-cache curl make gcc perl-app-cpanminus perl-net-ssleay libressl-dev perl-dev musl-dev

# For getting the latest wget
RUN apk update && apk add ca-certificates && update-ca-certificates && apk add wget


# Install cpanm
RUN curl -L https://cpanmin.us | perl - -M https://cpan.metacpan.org -n Mojolicious


# Install popular deps
RUN cpanm -n JSON::XS JSON EV LWP::Protocol::https Lock::File Mojo::AsyncAwait

WORKDIR /src

ADD cpanfile /src

RUN cpanm -nv --installdeps .

USER app

# Set the working directory to mojolicious directory created above
VOLUME ["/src", "/data"]

ADD . /src

# Run a shell as the default command
CMD ["/bin/sh"]