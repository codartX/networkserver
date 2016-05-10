FROM ubuntu:14.04

# make sure the package repository is up to date
RUN apt-get update

RUN mkdir -p /opt/networkserver

ADD *.so networkserver /opt/networkserver

WORKDIR /opt/networkserver
