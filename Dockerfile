FROM debian:buster-slim

RUN apt-get update

# needed to start the compiler
RUN apt-get install -y libtinfo-dev

COPY entr /usr/local/bin/

RUN useradd --create-home --shell /bin/sh jai
USER jai
WORKDIR /home/jai
